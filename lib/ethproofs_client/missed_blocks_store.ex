defmodule EthProofsClient.MissedBlocksStore do
  @moduledoc """
  GenServer that maintains an ordered list of missed/failed blocks with their metadata.

  A block is considered "missed" when it fails at any stage of the pipeline:
  - Input generation failure (RPC errors, NIF errors, task crashes)
  - Proving failure (cargo-zisk errors, port crashes)

  ## Usage

      # Add a missed block
      MissedBlocksStore.add_block(12345, %{
        failed_at: DateTime.utc_now(),
        stage: :input_generation,
        reason: "RPC timeout"
      })

      # Get all missed blocks
      MissedBlocksStore.list_blocks()

      # Subscribe to updates
      Phoenix.PubSub.subscribe(EthProofsClient.PubSub, "missed_blocks")
  """

  use GenServer
  require Logger

  @max_blocks 100
  @pubsub_topic "missed_blocks"

  defstruct blocks: [], block_set: MapSet.new(), total_count: 0

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add a missed block with its metadata.
  Returns :ok if added, :duplicate if block was already recorded.

  ## Metadata fields
  - `:failed_at` - DateTime when the failure occurred (defaults to now)
  - `:stage` - Which stage failed: `:input_generation` or `:proving`
  - `:reason` - String describing the failure reason
  """
  def add_block(block_number, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:add_block, block_number, metadata})
  end

  @doc """
  Returns the list of missed blocks, most recent first.
  """
  def list_blocks do
    GenServer.call(__MODULE__, :list_blocks)
  end

  @doc """
  Returns the count of missed blocks.
  """
  def count do
    GenServer.call(__MODULE__, :count)
  end

  @doc """
  Check if a block has been recorded as missed.
  """
  def missed?(block_number) do
    GenServer.call(__MODULE__, {:missed?, block_number})
  end

  @doc """
  Clear all missed blocks. Mainly for testing.
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # --- Callbacks ---

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:add_block, block_number, metadata}, _from, state) do
    if MapSet.member?(state.block_set, block_number) do
      {:reply, :duplicate, state}
    else
      block = %{
        block_number: block_number,
        failed_at: Map.get(metadata, :failed_at, DateTime.utc_now()),
        stage: Map.get(metadata, :stage, :unknown),
        reason: Map.get(metadata, :reason, "Unknown error")
      }

      # Add to front, trim if necessary
      new_blocks = [block | state.blocks] |> Enum.take(@max_blocks)
      new_block_set = MapSet.put(state.block_set, block_number)

      # Trim the set if we exceeded max_blocks
      new_block_set =
        if length(state.blocks) >= @max_blocks do
          oldest = List.last(state.blocks)
          MapSet.delete(new_block_set, oldest.block_number)
        else
          new_block_set
        end

      new_state = %{state | blocks: new_blocks, block_set: new_block_set, total_count: state.total_count + 1}

      # Broadcast the update
      broadcast_update(new_state)

      Logger.warning("Missed block #{block_number} at stage #{block.stage}: #{block.reason}")
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:list_blocks, _from, state) do
    {:reply, state.blocks, state}
  end

  @impl true
  def handle_call(:count, _from, state) do
    {:reply, state.total_count, state}
  end

  @impl true
  def handle_call({:missed?, block_number}, _from, state) do
    {:reply, MapSet.member?(state.block_set, block_number), state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    new_state = %__MODULE__{}
    broadcast_update(new_state)
    {:reply, :ok, new_state}
  end

  # --- Private Functions ---

  defp broadcast_update(state) do
    Phoenix.PubSub.broadcast(
      EthProofsClient.PubSub,
      @pubsub_topic,
      {:missed_blocks_updated, state.blocks}
    )
  rescue
    # PubSub might not be started during tests
    ArgumentError -> :ok
  end
end
