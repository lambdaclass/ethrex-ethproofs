defmodule EthProofsClient.Prover do
  @moduledoc """
  GenServer that manages a queue of blocks to prove using cargo-zisk.

  ## State Machine

  The prover operates as a state machine with two states:
  - `:idle` - No proof in progress, ready to process next item
  - `{:proving, block_number, port}` - Currently proving a block
  """

  use GenServer
  require Logger

  alias EthProofsClient.MissedBlocksStore

  @output_dir "output"

  defstruct [
    :status,
    :zisk_elf,
    :airbender_bin,
    :airbender_enabled,
    :proving_since,
    :idle_since,
    :current_input_gen_duration,
    :current_block_input_paths,
    :timeout_ref,
    queue: :queue.new(),
    queued_blocks: MapSet.new(),
    prover_output: ""
  ]

  # --- Public API ---

  def start_link(prover_config, _opts \\ []) do
    GenServer.start_link(__MODULE__, prover_config, name: __MODULE__)
  end

  @doc """
  Enqueue a block for proving. Duplicates are automatically ignored.

  The optional `input_gen_duration` parameter tracks how long input generation took,
  so it can be displayed in the dashboard.
  """
  def prove(block_number, input_paths, input_gen_duration \\ nil) do
    GenServer.cast(__MODULE__, {:prove, block_number, input_paths, input_gen_duration})
  end

  @doc """
  Get the current status of the prover for debugging/monitoring.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # --- Callbacks ---

  @impl true
  def init(config) do
    Process.flag(:trap_exit, true)

    {:ok,
     %__MODULE__{
       status: :idle,
       zisk_elf: config.zisk_elf_path,
       airbender_bin: config.airbender_bin_path,
       airbender_enabled: config.airbender_enabled,
       idle_since: DateTime.utc_now()
     }}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status_info = %{
      status: sanitize_status(state.status),
      queue_length: :queue.len(state.queue),
      queued_blocks: MapSet.to_list(state.queued_blocks),
      proving_since: state.proving_since,
      proving_duration_seconds: proving_duration(state),
      idle_since: state.idle_since,
      idle_duration_seconds: idle_duration(state)
    }

    {:reply, status_info, state}
  end

  @impl true
  def handle_cast({:prove, block_number, input_paths, input_gen_duration}, state) do
    cond do
      MapSet.member?(state.queued_blocks, block_number) ->
        Logger.debug("Block #{block_number} already queued, skipping")
        {:noreply, state}

      currently_proving?(state, block_number) ->
        Logger.debug("Block #{block_number} already proving, skipping")
        {:noreply, state}

      true ->
        report_queued(block_number, :zisk)
        new_state = enqueue(state, block_number, input_paths, input_gen_duration)
        {:noreply, maybe_start_next(new_state)}
    end
  end

  # Handle port data output (accumulate for metadata parsing)
  @impl true
  def handle_info(
        {port, {:data, data}},
        %{status: {:proving, _block_number, _prover_type, port}} = state
      ) do
    Logger.debug("Prover output: #{data}")
    {:noreply, %{state | prover_output: state.prover_output <> data}}
  end

  # Handle normal port exit - this is the primary completion handler
  @impl true
  def handle_info(
        {port, {:exit_status, status}},
        %{status: {:proving, block_number, prover_type, port}} = state
      ) do
    Logger.info("#{prover_type} exited with status #{status} for block #{block_number}")

    # Unlink immediately to prevent receiving duplicate EXIT message
    Process.unlink(port)
    cancel_timeout(state.timeout_ref)

    new_state = handle_proof_completion(state, block_number, prover_type, status)

    new_state =
      case prover_type do
        :zisk when state.airbender_enabled ->
          # Chain to Airbender after ZisK succeeds
          maybe_start_airbender(new_state, block_number)

        _ ->
          maybe_start_next(new_state)
      end

    {:noreply, new_state}
  end

  # Handle abnormal port termination (only if exit_status wasn't received)
  @impl true
  def handle_info(
        {:EXIT, port, reason},
        %{status: {:proving, block_number, prover_type, port}} = state
      ) do
    Logger.warning(
      "#{prover_type} port died unexpectedly for block #{block_number}: #{inspect(reason)}. Continuing."
    )

    cancel_timeout(state.timeout_ref)

    MissedBlocksStore.add_block(block_number, %{
      stage: :proving,
      reason: "#{prover_type} crashed: #{format_error(reason)}"
    })

    new_state = %{
      state
      | status: :idle,
        proving_since: nil,
        idle_since: DateTime.utc_now(),
        timeout_ref: nil
    }

    {:noreply, maybe_start_next(new_state)}
  end

  # Handle proving timeout - kill the stuck prover process and move on
  @impl true
  def handle_info(
        {:proving_timeout, block_number},
        %{status: {:proving, block_number, _prover_type, port}} = state
      ) do
    Logger.warning(
      "Proving timeout (#{div(proving_timeout_ms(), 1_000)}s) reached for block #{block_number}, killing prover process"
    )

    Process.unlink(port)

    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} ->
        System.cmd("kill", ["-9", Integer.to_string(os_pid)])

      nil ->
        :ok
    end

    MissedBlocksStore.add_block(block_number, %{
      stage: :proving,
      reason: "Proving timeout: exceeded #{div(proving_timeout_ms(), 1_000)}s limit"
    })

    broadcast_status_update(:idle)

    new_state = %{
      state
      | status: :idle,
        proving_since: nil,
        idle_since: DateTime.utc_now(),
        timeout_ref: nil,
        current_input_gen_duration: nil
    }

    {:noreply, maybe_start_next(new_state)}
  end

  # Stale timeout for a block we're no longer proving (race condition)
  @impl true
  def handle_info({:proving_timeout, _block_number}, state) do
    Logger.debug("Ignoring stale proving timeout")
    {:noreply, state}
  end

  # Ignore messages from unknown/old ports
  @impl true
  def handle_info({port, {:data, _data}}, state) when is_port(port) do
    Logger.debug("Ignoring data from unknown port: #{inspect(port)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, _status}}, state) when is_port(port) do
    Logger.debug("Ignoring exit_status from unknown port: #{inspect(port)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, port, _reason}, state) when is_port(port) do
    Logger.debug("Ignoring EXIT from unknown port: #{inspect(port)}")
    {:noreply, state}
  end

  # Handle EXIT from PIDs (processes spawned by the port or linked processes)
  @impl true
  def handle_info({:EXIT, pid, reason}, state) when is_pid(pid) do
    Logger.debug("Ignoring EXIT from process #{inspect(pid)}: #{inspect(reason)}")
    {:noreply, state}
  end

  # Catch-all for any unexpected messages
  @impl true
  def handle_info(msg, state) do
    Logger.warning("Prover received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # --- Private Functions ---

  defp currently_proving?(%{status: {:proving, block_number, _type, _port}}, block_number),
    do: true

  defp currently_proving?(_state, _block_number), do: false

  defp enqueue(state, block_number, input_paths, input_gen_duration) do
    Logger.info("Enqueued block #{block_number} for proving")

    %{
      state
      | queue: :queue.in({block_number, input_paths, input_gen_duration}, state.queue),
        queued_blocks: MapSet.put(state.queued_blocks, block_number)
    }
  end

  defp maybe_start_next(%{status: :idle, queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, {block_number, input_paths, input_gen_duration}}, new_queue} ->
        zisk_input = input_paths.zisk
        port = start_zisk_prover(state.zisk_elf, block_number, zisk_input)
        Process.link(port)
        report_proving(block_number, :zisk)

        Logger.info(
          "Started ZisK prover for block #{block_number} (ELF: #{state.zisk_elf}, INPUT: #{zisk_input})"
        )

        broadcast_status_update({:proving, block_number})

        timeout_ref =
          Process.send_after(self(), {:proving_timeout, block_number}, proving_timeout_ms())

        %{
          state
          | status: {:proving, block_number, :zisk, port},
            queue: new_queue,
            queued_blocks: MapSet.delete(state.queued_blocks, block_number),
            proving_since: DateTime.utc_now(),
            idle_since: nil,
            current_input_gen_duration: input_gen_duration,
            current_block_input_paths: input_paths,
            timeout_ref: timeout_ref,
            prover_output: ""
        }

      {:empty, _queue} ->
        Logger.debug("Proof queue is empty, prover is idle")
        state
    end
  end

  # Already proving, do nothing
  defp maybe_start_next(state), do: state

  defp maybe_start_airbender(%{status: :idle} = state, block_number) do
    case state.current_block_input_paths do
      %{airbender: airbender_input} when airbender_input != nil ->
        port = start_airbender_prover(state.airbender_bin, block_number, airbender_input)
        Process.link(port)
        report_queued(block_number, :airbender)
        report_proving(block_number, :airbender)

        Logger.info(
          "Started Airbender prover for block #{block_number} (BIN: #{state.airbender_bin}, INPUT: #{airbender_input})"
        )

        broadcast_status_update({:proving, block_number})

        timeout_ref =
          Process.send_after(self(), {:proving_timeout, block_number}, proving_timeout_ms())

        %{
          state
          | status: {:proving, block_number, :airbender, port},
            proving_since: DateTime.utc_now(),
            idle_since: nil,
            timeout_ref: timeout_ref,
            prover_output: ""
        }

      _ ->
        Logger.warning("No Airbender input for block #{block_number}, skipping")
        maybe_start_next(state)
    end
  end

  defp maybe_start_airbender(state, _block_number), do: state

  defp start_zisk_prover(elf, block_number, input_path) do
    output_dir = Path.join(@output_dir, Integer.to_string(block_number))
    File.mkdir_p!(output_dir)

    Port.open(
      {:spawn_executable, System.find_executable("cargo-zisk")},
      [
        :binary,
        :exit_status,
        args: [
          "prove",
          "-e",
          elf,
          "-i",
          input_path,
          "-o",
          output_dir,
          "-a",
          "-u"
        ]
      ]
    )
  end

  defp start_airbender_prover(bin_path, block_number, input_path) do
    output_dir = Path.join(@output_dir, "airbender_#{block_number}")
    File.mkdir_p!(output_dir)
    output_file = Path.join(output_dir, "proof.bin")

    Port.open(
      {:spawn_executable, System.find_executable("cargo-airbender")},
      [
        :binary,
        :exit_status,
        {:env, [{~c"RUST_LOG", ~c"info"}]},
        args: [
          "prove",
          bin_path,
          "--input",
          input_path,
          "--output",
          output_file,
          "--backend",
          "gpu"
        ]
      ]
    )
  end

  defp handle_proof_completion(state, block_number, prover_type, exit_status) do
    proving_duration = proving_duration(state)
    input_gen_duration = state.current_input_gen_duration

    case read_proof_data(block_number, prover_type, state.prover_output, proving_duration) do
      {:ok, proof_data} ->
        Logger.info(
          "#{prover_type} proved block #{block_number} in #{proof_data.time / 1000}s using #{proof_data.cycles} cycles"
        )

        report_proved(block_number, prover_type, proof_data)

        EthProofsClient.ProvedBlocksStore.add_block(block_number, %{
          proved_at: DateTime.utc_now(),
          prover_type: prover_type,
          proving_duration_seconds: proving_duration,
          input_generation_duration_seconds: input_gen_duration
        })

      {:error, reason} ->
        Logger.error(
          "#{prover_type} failed for block #{block_number} (exit_status: #{exit_status}): #{inspect(reason)}"
        )

        MissedBlocksStore.add_block(block_number, %{
          stage: :proving,
          prover_type: prover_type,
          reason: "#{prover_type} failed (exit_status: #{exit_status}): #{format_error(reason)}"
        })
    end

    broadcast_status_update(:idle)

    %{
      state
      | status: :idle,
        proving_since: nil,
        idle_since: DateTime.utc_now(),
        timeout_ref: nil
    }
  end

  defp read_proof_data(block_number, :zisk, prover_output, _proving_duration) do
    block_dir = Integer.to_string(block_number)
    proof_path = Path.join([@output_dir, block_dir, "vadcop_final_proof.bin"])

    cycles = parse_stdout_field(prover_output, ~r/steps:\s*([\d,]+)/)
    time = parse_stdout_float(prover_output, ~r/Proof Time:\s*([\d.]+)\s*seconds/)
    id = parse_stdout_string(prover_output, ~r/Proof ID:\s*([0-9a-f]+)/)

    Process.sleep(1000)

    with {:ok, proof_binary} <- File.read(proof_path) do
      {:ok,
       %{
         cycles: cycles,
         time: if(time, do: trunc(time * 1000), else: 0),
         proof: Base.encode64(proof_binary, padding: false) |> String.replace(~r/\s+/, ""),
         verifier_id: id || "unknown"
       }}
    else
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
    end
  end

  defp read_proof_data(block_number, :airbender, prover_output, _proving_duration) do
    proof_path = Path.join([@output_dir, "airbender_#{block_number}", "proof.bin"])

    cycles = parse_stdout_field(prover_output, ~r/cycles:\s*([\d,]+)/)
    # Sum all proving layer times (base + recursion layers)
    time = sum_proving_times(prover_output)

    Process.sleep(1000)

    with {:ok, proof_binary} <- File.read(proof_path) do
      {:ok,
       %{
         cycles: cycles,
         time: if(time, do: trunc(time * 1000), else: 0),
         proof: Base.encode64(proof_binary, padding: false) |> String.replace(~r/\s+/, ""),
         verifier_id: nil
       }}
    else
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
    end
  end

  defp parse_stdout_field(output, regex) do
    case Regex.run(regex, output) do
      [_, value] -> value |> String.replace(",", "") |> String.to_integer()
      _ -> 0
    end
  end

  defp parse_stdout_float(output, regex) do
    case Regex.run(regex, output) do
      [_, value] -> String.to_float(value)
      _ -> nil
    end
  end

  defp parse_stdout_string(output, regex) do
    case Regex.run(regex, output) do
      [_, value] -> value
      _ -> nil
    end
  end

  # Sum all "proof done in X.XXXs" times from Airbender output
  # (base layer + unrolled recursion layers + unified recursion layers)
  defp sum_proving_times(output) do
    Regex.scan(~r/proof done in ([\d.]+)s/, output)
    |> Enum.reduce(0.0, fn [_, time_str], acc ->
      case Float.parse(time_str) do
        {time, _} -> acc + time
        :error -> acc
      end
    end)
  end

  defp sanitize_status(:idle), do: :idle
  defp sanitize_status({:proving, block_number, prover_type, _port}), do: {:proving, block_number, prover_type}

  defp proving_timeout_ms do
    :timer.seconds(Application.get_env(:ethproofs_client, :proving_timeout_seconds, 1200))
  end

  defp cancel_timeout(nil), do: :ok
  defp cancel_timeout(ref), do: Process.cancel_timer(ref)

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp proving_duration(%{proving_since: nil}), do: nil

  defp proving_duration(%{proving_since: since}) do
    DateTime.diff(DateTime.utc_now(), since, :second)
  end

  defp idle_duration(%{idle_since: nil}), do: nil

  defp idle_duration(%{idle_since: since}) do
    DateTime.diff(DateTime.utc_now(), since, :second)
  end

  # --- API Reporting Functions ---

  defp cluster_id_for(:zisk), do: EthProofsClient.Rpc.zisk_cluster_id()
  defp cluster_id_for(:airbender), do: EthProofsClient.Rpc.airbender_cluster_id()

  defp report_queued(block_number, prover_type) do
    case cluster_id_for(prover_type) do
      nil ->
        Logger.debug("No cluster ID for #{prover_type}, skipping queued report")

      cluster_id ->
        case EthProofsClient.Rpc.queued_proof(block_number, cluster_id) do
          {:ok, _proof_id} -> :ok
          {:error, reason} -> Logger.error("Failed to report queued for block #{block_number} (#{prover_type}): #{reason}")
        end
    end
  end

  defp report_proving(block_number, prover_type) do
    case cluster_id_for(prover_type) do
      nil ->
        :ok

      cluster_id ->
        case EthProofsClient.Rpc.proving_proof(block_number, cluster_id) do
          {:ok, _proof_id} -> :ok
          {:error, reason} -> Logger.error("Failed to report proving for block #{block_number} (#{prover_type}): #{reason}")
        end
    end
  end

  defp report_proved(block_number, prover_type, proof_data) do
    case cluster_id_for(prover_type) do
      nil ->
        :ok

      cluster_id ->
        case EthProofsClient.Rpc.proved_proof(
               block_number,
               cluster_id,
               proof_data.time,
               proof_data.cycles,
               proof_data.proof,
               proof_data.verifier_id
             ) do
          {:ok, _proof_id} -> :ok
          {:error, reason} -> Logger.error("Failed to report proved for block #{block_number} (#{prover_type}): #{reason}")
        end
    end
  end

  defp broadcast_status_update(status) do
    Phoenix.PubSub.broadcast(
      EthProofsClient.PubSub,
      "prover_status",
      {:prover_status, status}
    )
  rescue
    # PubSub might not be started during tests
    ArgumentError -> :ok
  end
end
