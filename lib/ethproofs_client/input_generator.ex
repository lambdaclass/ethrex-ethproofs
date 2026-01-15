defmodule EthProofsClient.InputGenerator do
  @moduledoc """
  GenServer that monitors the Ethereum chain and generates ZK proof inputs.

  ## State Machine

  The generator operates as a state machine with two states:
  - `:idle` - No generation in progress, ready to process next item
  - `{:generating, block_number, task_ref}` - Currently generating input for a block

  Tasks are spawned via `Task.Supervisor.async_nolink` which provides:
  - Proper supervision under EthProofsClient.TaskSupervisor
  - No link to the GenServer (crashes don't propagate)
  - Monitor-based completion/crash detection via {:DOWN, ...} messages
  """

  use Rustler, otp_app: :ethproofs_client, crate: "ethrex_ethproofs_input_generator"
  use GenServer
  require Logger

  alias EthProofsClient.BlockMetadata
  alias EthProofsClient.Notifications
  alias EthProofsClient.Prover

  @block_fetch_interval 2_000

  defstruct [
    :status,
    queue: :queue.new(),
    queued_blocks: MapSet.new(),
    processed_blocks: MapSet.new()
  ]

  # --- Public API ---

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Enqueue a block for input generation. Duplicates are automatically ignored.
  """
  def generate(block_number) do
    GenServer.cast(__MODULE__, {:generate, block_number})
  end

  @doc """
  Get the current status of the generator for debugging/monitoring.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # --- Callbacks ---

  @impl true
  def init(_state) do
    BlockMetadata.init_table()
    schedule_fetch()
    {:ok, %__MODULE__{status: :idle}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status_info = %{
      status: sanitize_status(state.status),
      queue_length: :queue.len(state.queue),
      queued_blocks: MapSet.to_list(state.queued_blocks),
      processed_count: MapSet.size(state.processed_blocks)
    }

    {:reply, status_info, state}
  end

  @impl true
  def handle_cast({:generate, block_number}, state) do
    cond do
      MapSet.member?(state.queued_blocks, block_number) ->
        Logger.debug("Block #{block_number} already queued for generation, skipping")
        {:noreply, state}

      MapSet.member?(state.processed_blocks, block_number) ->
        Logger.debug("Block #{block_number} already processed, skipping")
        {:noreply, state}

      currently_generating?(state, block_number) ->
        Logger.debug("Block #{block_number} already generating, skipping")
        {:noreply, state}

      true ->
        new_state = enqueue(state, block_number)
        {:noreply, maybe_start_next(new_state)}
    end
  end

  # Task completed successfully - result is sent as {ref, result}
  @impl true
  def handle_info({ref, result}, %{status: {:generating, block_number, ref}} = state)
      when is_reference(ref) do
    # Flush the :DOWN message since we handled completion
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, input_path} ->
        Logger.info("Generated input for block #{block_number}: #{input_path}")
        Prover.prove(block_number, input_path)

      {:error, reason} ->
        Logger.error("Failed to generate input for block #{block_number}: #{inspect(reason)}")
        Notifications.input_generation_failed(block_number, reason)
    end

    new_state = %{
      state
      | status: :idle,
        processed_blocks: MapSet.put(state.processed_blocks, block_number)
    }

    {:noreply, maybe_start_next(new_state)}
  end

  # Task crashed - we receive {:DOWN, ref, :process, pid, reason}
  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{status: {:generating, block_number, ref}} = state
      ) do
    Logger.error("Generation task crashed for block #{block_number}: #{inspect(reason)}")

    # Don't mark as processed so it can be retried if requested again
    new_state = %{state | status: :idle}
    {:noreply, maybe_start_next(new_state)}
  end

  # Periodic block fetching
  @impl true
  def handle_info(:fetch_latest_block_number, state) do
    case EthProofsClient.EthRpc.get_latest_block_info() do
      {:ok, {block_number, block_timestamp}} ->
        handle_new_block(block_number, block_timestamp, state)

      {:error, reason} ->
        Logger.error("Failed to fetch latest block: #{inspect(reason)}")
    end

    schedule_fetch()
    {:noreply, state}
  end

  # Ignore messages from unknown/old task refs
  @impl true
  def handle_info({ref, _result}, state) when is_reference(ref) do
    Logger.debug("Ignoring result from unknown task ref: #{inspect(ref)}")
    # Flush any associated DOWN message
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) when is_reference(ref) do
    Logger.debug("Ignoring DOWN from unknown task ref: #{inspect(ref)}")
    {:noreply, state}
  end

  # --- Private Functions ---

  defp currently_generating?(%{status: {:generating, block_number, _ref}}, block_number), do: true
  defp currently_generating?(_state, _block_number), do: false

  defp enqueue(state, block_number) do
    Logger.info("Enqueued block #{block_number} for input generation")

    %{
      state
      | queue: :queue.in(block_number, state.queue),
        queued_blocks: MapSet.put(state.queued_blocks, block_number)
    }
  end

  defp maybe_start_next(%{status: :idle, queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, block_number}, new_queue} ->
        Logger.info("Starting input generation for block #{block_number}")

        # async_nolink spawns a supervised task that doesn't link to this process.
        # We still get {ref, result} on success and {:DOWN, ...} on crash.
        task =
          Task.Supervisor.async_nolink(
            EthProofsClient.TaskSupervisor,
            fn -> do_generate_input(block_number) end
          )

        %{
          state
          | status: {:generating, block_number, task.ref},
            queue: new_queue,
            queued_blocks: MapSet.delete(state.queued_blocks, block_number)
        }

      {:empty, _queue} ->
        Logger.debug("Generation queue is empty, generator is idle")
        state
    end
  end

  # Already generating, do nothing
  defp maybe_start_next(state), do: state

  defp do_generate_input(block_number) do
    with {:ok, block_json_bytes} <- fetch_block(block_number),
         :ok <- store_block_metadata(block_number, block_json_bytes),
         {:ok, witness_json_bytes} <- fetch_witness(block_number),
         {:ok, input_path} <- build_input(block_json_bytes, witness_json_bytes) do
      {:ok, input_path}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_new_block(block_number, block_timestamp, state) do
    cond do
      rem(block_number, 100) != 0 ->
        blocks_remaining = 100 - rem(block_number, 100)
        next_multiple = block_number + blocks_remaining
        # Account for time elapsed since block was produced
        elapsed = System.system_time(:second) - block_timestamp
        estimated_wait = max(0, blocks_remaining * 12 - elapsed)

        Logger.debug(
          "Latest block: #{block_number}. Next multiple of 100: #{next_multiple} (est. #{estimated_wait}s)"
        )

      MapSet.member?(state.processed_blocks, block_number) ->
        Logger.debug("Block #{block_number} already processed, skipping")

      MapSet.member?(state.queued_blocks, block_number) ->
        Logger.debug("Block #{block_number} already queued, skipping")

      currently_generating?(state, block_number) ->
        Logger.debug("Block #{block_number} already generating, skipping")

      File.exists?(Integer.to_string(block_number) <> ".bin") ->
        Logger.debug("Block #{block_number} input file exists, skipping")

      true ->
        Logger.info("Block #{block_number} is a multiple of 100, queueing for generation")
        GenServer.cast(__MODULE__, {:generate, block_number})
    end
  end

  defp schedule_fetch do
    Process.send_after(self(), :fetch_latest_block_number, @block_fetch_interval)
  end

  defp fetch_block(block_number) do
    case EthProofsClient.EthRpc.get_block_by_number(block_number, true, raw: true) do
      {:ok, block_json_bytes} -> {:ok, block_json_bytes}
      {:error, reason} -> {:error, {:rpc_get_block_by_number, reason}}
    end
  end

  defp store_block_metadata(block_number, block_json_bytes) do
    case BlockMetadata.put_from_json(block_number, block_json_bytes) do
      :ok -> :ok
      :error -> {:error, {:block_metadata, :invalid_block_data}}
    end
  end

  defp fetch_witness(block_number) do
    case EthProofsClient.EthRpc.debug_execution_witness(block_number, raw: true) do
      {:ok, witness_json_bytes} -> {:ok, witness_json_bytes}
      {:error, reason} -> {:error, {:rpc_debug_execution_witness, reason}}
    end
  end

  defp build_input(block_json_bytes, witness_json_bytes) do
    case generate_input(block_json_bytes, witness_json_bytes) do
      {:ok, input_path} -> {:ok, input_path}
      {:error, reason} -> {:error, {:input_generation, reason}}
    end
  end

  defp sanitize_status(:idle), do: :idle
  defp sanitize_status({:generating, block_number, _ref}), do: {:generating, block_number}

  # NIF stub - replaced at runtime by Rustler
  defp generate_input(_rpc_block_bytes, _rpc_execution_witness_bytes),
    do: :erlang.nif_error(:nif_not_loaded)
end
