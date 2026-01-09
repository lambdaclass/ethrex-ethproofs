defmodule EthProofsClient.InputGenerator do
  use Rustler, otp_app: :ethproofs_client, crate: "ethrex_ethproofs_input_generator"
  use GenServer
  require Logger

  alias EthProofsClient.Prover

  @block_fetch_interval 2_000

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def generate(block_number) do
    GenServer.cast(__MODULE__, {:generate, block_number})
  end

  @impl true
  def init(_state) do
    Process.send_after(self(), :fetch_latest_block_number, @block_fetch_interval)

    # Track queued/generating blocks so we don't accidentally prove the same block twice.
    {:ok, %{queue: :queue.new(), generating: false, in_flight: MapSet.new()}}
  end

  @impl true
  def handle_cast({:generate, block_number}, state) do
    if MapSet.member?(state.in_flight, block_number) do
      Logger.info("Block #{block_number} already queued or generating")
      {:noreply, state}
    else
      new_queue = :queue.in(block_number, state.queue)
      in_flight = MapSet.put(state.in_flight, block_number)

      if state.generating do
        Logger.info("Input generation already in progress, enqueued block number #{block_number}")

        {:noreply, %{state | queue: new_queue, in_flight: in_flight}}
      else
        send(self(), :generate_next)

        {:noreply, %{state | queue: new_queue, generating: true, in_flight: in_flight}}
      end
    end
  end

  @impl true
  def handle_info(:generate_next, %{queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, block_number}, new_queue} ->
        Logger.info("Generating input for block number: #{block_number}")

        Task.start(fn ->
          try do
            {:ok, block_json_bytes} =
              EthProofsClient.EthRpc.get_block_by_number(block_number, true, raw: true)

            {:ok, witness_json_bytes} =
              EthProofsClient.EthRpc.debug_execution_witness(block_number, raw: true)

            case generate_input(block_json_bytes, witness_json_bytes) do
              {:ok, input_path} ->
                Prover.prove(block_number, input_path)

              {:error, reason} ->
                Logger.error("NIF error: #{reason}")
            end

            send(__MODULE__, {:generation_done, block_number})
          rescue
            e ->
              Logger.error("Failed to generate input for block #{block_number}: #{inspect(e)}")

              send(__MODULE__, {:generation_done, block_number})
          end
        end)

        {:noreply, %{state | queue: new_queue, generating: true}}

      {:empty, _queue} ->
        Logger.debug("Input generation queue is empty, stopping generation")

        {:noreply, %{state | generating: false}}
    end
  end

  @impl true
  def handle_info({:generation_done, block_number}, state) do
    state = %{state | in_flight: MapSet.delete(state.in_flight, block_number)}

    # Generation completed, check for next item
    if :queue.is_empty(state.queue) do
      {:noreply, %{state | generating: false}}
    else
      send(self(), :generate_next)

      {:noreply, %{state | generating: true}}
    end
  end

  @impl true
  def handle_info(:fetch_latest_block_number, state) do
    case EthProofsClient.EthRpc.get_latest_block_number() do
      {:ok, block_number} ->
        cond do
          rem(block_number, 100) != 0 ->
            next_multiple_of_100 = block_number + (100 - rem(block_number, 100))

            estimated_wait = (next_multiple_of_100 - block_number) * 12

            Logger.debug(
              "Latest block number: #{block_number}. Estimated wait time until next multiple of 100 (#{next_multiple_of_100}): #{estimated_wait} seconds"
            )

          File.exists?(Integer.to_string(block_number) <> ".bin") ->
            Logger.debug("Block #{block_number} already processed, skipping")

          true ->
            Logger.info("Block #{block_number} is a multiple of 100, generating input")

            GenServer.cast(__MODULE__, {:generate, block_number})
        end

      {:error, reason} ->
        Logger.error("Failed to fetch latest block number: #{reason}")
    end

    Process.send_after(self(), :fetch_latest_block_number, @block_fetch_interval)

    {:noreply, state}
  end

  defp generate_input(_rpc_block_bytes, _rpc_execution_witness_bytes),
    do: :erlang.nif_error(:nif_not_loaded)
end
