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
    :elf,
    :proving_since,
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
    {:ok, %__MODULE__{status: :idle, elf: elf}}
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
        report_queued(block_number)
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
    Logger.info("cargo-zisk exited with status #{status} for block #{block_number}")

    # Unlink immediately to prevent receiving duplicate EXIT message
    Process.unlink(port)

    new_state = handle_proof_completion(state, block_number, status)
    {:noreply, maybe_start_next(new_state)}
  end

  # Handle abnormal port termination (only if exit_status wasn't received)
  @impl true
  def handle_info({:EXIT, port, reason}, %{status: {:proving, block_number, port}} = state) do
    Logger.warning(
      "Port died unexpectedly for block #{block_number}: #{inspect(reason)}. Continuing with next item."
    )

    MissedBlocksStore.add_block(block_number, %{
      stage: :proving,
      reason: "Prover crashed: #{format_error(reason)}"
    })

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
    Logger.info("Enqueued block #{block_number} for proving (input: #{input_path})")

    %{
      state
      | queue: :queue.in({block_number, input_path}, state.queue),
        queued_blocks: MapSet.put(state.queued_blocks, block_number)
    }
  end

  defp maybe_start_next(%{status: :idle, queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, {block_number, input_path}}, new_queue} ->
        port = start_prover(state.elf, block_number, input_path)
        Process.link(port)
        report_proving(block_number)

        Logger.info(
          "Started cargo-zisk prover for block #{block_number} (ELF: #{state.elf}, INPUT: #{input_path}, PORT: #{inspect(port)})"
        )

        # Broadcast status update
        broadcast_status_update({:proving, block_number})

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

  defp start_prover(elf, block_number, input_path) do
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

  defp handle_proof_completion(state, block_number, exit_status) do
    proving_duration = proving_duration(state)

    case read_proof_data(block_number) do
      {:ok, proof_data} ->
        Logger.info(
          "Proved block #{block_number} in #{proof_data.time / 1000} seconds using #{proof_data.cycles} cycles"
        )

        report_proved(block_number, proof_data)

        # Store in ProvedBlocksStore for dashboard
        EthProofsClient.ProvedBlocksStore.add_block(block_number, %{
          proved_at: DateTime.utc_now(),
          proving_duration_seconds: proving_duration
        })

      {:error, reason} ->
        Logger.error(
          "Failed to read proof data for block #{block_number} (exit_status: #{exit_status}): #{inspect(reason)}"
        )

        MissedBlocksStore.add_block(block_number, %{
          stage: :proving,
          reason: "Proving failed (exit_status: #{exit_status}): #{format_error(reason)}"
        })
    end

    # Broadcast status update
    broadcast_status_update(:idle)

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

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp proving_duration(%{proving_since: nil}), do: nil

  defp proving_duration(%{proving_since: since}) do
    DateTime.diff(DateTime.utc_now(), since, :second)
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
