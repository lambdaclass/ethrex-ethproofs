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

  @output_dir "output"
  defstruct [
    :status,
    :elf,
    :proving_since,
    :zisk_action,
    queue: :queue.new(),
    queued_blocks: MapSet.new()
  ]

  # --- Public API ---

  def start_link(elf_path, _opts \\ []) do
    GenServer.start_link(__MODULE__, %{elf: elf_path}, name: __MODULE__)
  end

  @doc """
  Enqueue a block for proving. Duplicates are automatically ignored.
  """
  def prove(block_number, input_path) do
    GenServer.cast(__MODULE__, {:prove, block_number, input_path})
  end

  @doc """
  Get the current status of the prover for debugging/monitoring.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # --- Callbacks ---

  @impl true
  def init(%{elf: elf}) do
    Process.flag(:trap_exit, true)
    zisk_action = resolve_zisk_action()

    if dev_mode?() do
      Logger.info(
        "DEV mode enabled; using cargo-zisk execute and skipping EthProofs API reporting."
      )
    end

    {:ok, %__MODULE__{status: :idle, elf: elf, zisk_action: zisk_action}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status_info = %{
      status: sanitize_status(state.status),
      queue_length: :queue.len(state.queue),
      queued_blocks: MapSet.to_list(state.queued_blocks),
      proving_since: state.proving_since,
      proving_duration_seconds: proving_duration(state)
    }

    {:reply, status_info, state}
  end

  @impl true
  def handle_cast({:prove, block_number, input_path}, state) do
    cond do
      MapSet.member?(state.queued_blocks, block_number) ->
        Logger.debug("Block #{block_number} already queued, skipping")
        {:noreply, state}

      currently_proving?(state, block_number) ->
        Logger.debug("Block #{block_number} already proving, skipping")
        {:noreply, state}

      true ->
        if state.zisk_action == :prove do
          report_queued(block_number)
        end

        new_state = enqueue(state, block_number, input_path)
        {:noreply, maybe_start_next(new_state)}
    end
  end

  # Handle port data output (logging only)
  @impl true
  def handle_info({port, {:data, data}}, %{status: {:proving, _block_number, port}} = state) do
    Logger.debug("cargo-zisk output: #{data}")
    {:noreply, state}
  end

  # Handle normal port exit - this is the primary completion handler
  @impl true
  def handle_info(
        {port, {:exit_status, status}},
        %{status: {:proving, block_number, port}} = state
      ) do
    Logger.info(
      "cargo-zisk #{zisk_action_label(state.zisk_action)} exited with status #{status} for block #{block_number}"
    )

    # Unlink immediately to prevent receiving duplicate EXIT message
    Process.unlink(port)

    new_state =
      case state.zisk_action do
        :prove -> handle_proof_completion(state, block_number, status)
        :execute -> handle_execution_completion(state, block_number, status)
      end

    {:noreply, maybe_start_next(new_state)}
  end

  # Handle abnormal port termination (only if exit_status wasn't received)
  @impl true
  def handle_info({:EXIT, port, reason}, %{status: {:proving, block_number, port}} = state) do
    Logger.warning(
      "Port died unexpectedly for block #{block_number}: #{inspect(reason)}. Continuing with next item."
    )

    new_state = %{state | status: :idle, proving_since: nil}
    {:noreply, maybe_start_next(new_state)}
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

  # --- Private Functions ---

  defp currently_proving?(%{status: {:proving, block_number, _port}}, block_number), do: true
  defp currently_proving?(_state, _block_number), do: false

  defp enqueue(state, block_number, input_path) do
    Logger.info(
      "Enqueued block #{block_number} for #{zisk_action_label(state.zisk_action)} (input: #{input_path})"
    )

    %{
      state
      | queue: :queue.in({block_number, input_path}, state.queue),
        queued_blocks: MapSet.put(state.queued_blocks, block_number)
    }
  end

  defp maybe_start_next(%{status: :idle, queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, {block_number, input_path}}, new_queue} ->
        port = start_prover(state.elf, block_number, input_path, state.zisk_action)
        Process.link(port)

        if state.zisk_action == :prove do
          report_proving(block_number)
        end

        Logger.info(
          "Started cargo-zisk #{zisk_action_label(state.zisk_action)} for block #{block_number} (ELF: #{state.elf}, INPUT: #{input_path}, PORT: #{inspect(port)})"
        )

        %{
          state
          | status: {:proving, block_number, port},
            queue: new_queue,
            queued_blocks: MapSet.delete(state.queued_blocks, block_number),
            proving_since: DateTime.utc_now()
        }

      {:empty, _queue} ->
        Logger.debug("Proof queue is empty, prover is idle")
        state
    end
  end

  # Already proving, do nothing
  defp maybe_start_next(state), do: state

  defp start_prover(elf, block_number, input_path, :prove) do
    output_dir = Path.join(@output_dir, Integer.to_string(block_number))
    File.mkdir_p!(output_dir)

    Port.open(
      {:spawn_executable, System.find_executable("cargo-zisk")},
      [
        :binary,
        :exit_status,
        args: zisk_args(:prove, elf, input_path, output_dir)
      ]
    )
  end

  defp start_prover(elf, block_number, input_path, :execute) do
    output_dir = Path.join(@output_dir, Integer.to_string(block_number))

    Port.open(
      {:spawn_executable, System.find_executable("cargo-zisk")},
      [
        :binary,
        :exit_status,
        args: zisk_args(:execute, elf, input_path, output_dir)
      ]
    )
  end

  defp handle_proof_completion(state, block_number, exit_status) do
    case read_proof_data(block_number) do
      {:ok, proof_data} ->
        Logger.info(
          "Proved block #{block_number} in #{proof_data.time / 1000} seconds using #{proof_data.cycles} cycles"
        )

        report_proved(block_number, proof_data)

      {:error, reason} ->
        Logger.error(
          "Failed to read proof data for block #{block_number} (exit_status: #{exit_status}): #{inspect(reason)}"
        )
    end

    %{state | status: :idle, proving_since: nil}
  end

  defp handle_execution_completion(state, block_number, exit_status) do
    if exit_status == 0 do
      Logger.info(
        "Executed block #{block_number} with cargo-zisk #{zisk_action_label(state.zisk_action)}"
      )
    else
      Logger.error(
        "Execution failed for block #{block_number} with cargo-zisk #{zisk_action_label(state.zisk_action)} (status #{exit_status})"
      )
    end

    %{state | status: :idle, proving_since: nil}
  end

  defp read_proof_data(block_number) do
    block_dir = Integer.to_string(block_number)
    result_path = Path.join([@output_dir, block_dir, "result.json"])
    proof_path = Path.join([@output_dir, block_dir, "vadcop_final_proof.compressed.bin"])

    with {:ok, result_content} <- File.read(result_path),
         {:ok, %{"cycles" => cycles, "time" => time, "id" => id}} <- Jason.decode(result_content),
         {:ok, proof_binary} <- File.read(proof_path) do
      {:ok,
       %{
         cycles: cycles,
         time: trunc(time * 1000),
         proof: Base.encode64(proof_binary, padding: false) |> String.replace(~r/\s+/, ""),
         verifier_id: id
       }}
    else
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
    end
  end

  defp sanitize_status(:idle), do: :idle
  defp sanitize_status({:proving, block_number, _port}), do: {:proving, block_number}

  defp proving_duration(%{proving_since: nil}), do: nil

  defp proving_duration(%{proving_since: since}) do
    DateTime.diff(DateTime.utc_now(), since, :second)
  end

  defp resolve_zisk_action do
    if dev_mode?(), do: :execute, else: :prove
  end

  defp dev_mode? do
    Application.get_env(:ethproofs_client, :dev, false) == true
  end

  defp zisk_action_label(:prove), do: "prove"
  defp zisk_action_label(:execute), do: "execute"

  defp zisk_args(:prove, elf_path, input_path, output_dir_path) do
    ["prove", "-e", elf_path, "-i", input_path, "-o", output_dir_path, "-a", "-u"]
  end

  defp zisk_args(:execute, elf_path, input_path, _output_dir_path) do
    ["execute", "-e", elf_path, "-i", input_path, "-u"]
  end

  # --- API Reporting Functions ---

  defp report_queued(block_number) do
    case EthProofsClient.Rpc.queued_proof(block_number) do
      {:ok, _proof_id} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to report queued status for block #{block_number}: #{reason}")
    end
  end

  defp report_proving(block_number) do
    case EthProofsClient.Rpc.proving_proof(block_number) do
      {:ok, _proof_id} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to report proving status for block #{block_number}: #{reason}")
    end
  end

  defp report_proved(block_number, proof_data) do
    case EthProofsClient.Rpc.proved_proof(
           block_number,
           proof_data.time,
           proof_data.cycles,
           proof_data.proof,
           proof_data.verifier_id
         ) do
      {:ok, _proof_id} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to report proved status for block #{block_number}: #{reason}")
    end
  end
end
