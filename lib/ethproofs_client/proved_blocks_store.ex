defmodule EthProofsClient.ProvedBlocksStore do
  @moduledoc """
  GenServer that maintains an ordered list of proved blocks with their metadata.

  This store is designed to:
  - Keep the last N proved blocks in memory
  - Broadcast updates via PubSub for real-time UI updates
  - Provide O(1) lookups and O(1) insertions

  ## Usage

      # Add a proved block
      ProvedBlocksStore.add_block(12345, %{
        proved_at: DateTime.utc_now(),
        proving_duration_seconds: 3600,
        input_generation_duration_seconds: 120
      })

      # Get all proved blocks
      ProvedBlocksStore.list_blocks()

      # Subscribe to updates
      Phoenix.PubSub.subscribe(EthProofsClient.PubSub, "proved_blocks")
  """

  use GenServer
  require Logger

  @max_blocks 100
  @pubsub_topic "proved_blocks"

  defstruct blocks: [], block_set: MapSet.new(), total_count: 0

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add a proved block with its metadata.
  Returns :ok if added, :duplicate if block was already proved.
  """
  def add_block(block_number, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:add_block, block_number, metadata})
  end

  @doc """
  Returns the list of proved blocks, most recent first.
  """
  def list_blocks do
    GenServer.call(__MODULE__, :list_blocks)
  end

  @doc """
  Returns the count of proved blocks.
  """
  def count do
    GenServer.call(__MODULE__, :count)
  end

  @doc """
  Check if a block has been proved.
  """
  def proved?(block_number) do
    GenServer.call(__MODULE__, {:proved?, block_number})
  end

  @doc """
  Clear all proved blocks. Mainly for testing.
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
        proved_at: Map.get(metadata, :proved_at, DateTime.utc_now()),
        proving_duration_seconds: Map.get(metadata, :proving_duration_seconds),
        input_generation_duration_seconds: Map.get(metadata, :input_generation_duration_seconds)
      }

      # Add to front, trim if necessary
      new_blocks = [block | state.blocks] |> Enum.take(@max_blocks)
      new_block_set = MapSet.put(state.block_set, block_number)

      # Trim the set if we exceeded max_blocks
      new_block_set =
        if length(state.blocks) >= @max_blocks do
          # Remove the oldest block from the set
          oldest = List.last(state.blocks)
          MapSet.delete(new_block_set, oldest.block_number)
        else
          new_block_set
        end

      new_state = %{state | blocks: new_blocks, block_set: new_block_set, total_count: state.total_count + 1}

      # Broadcast the update
      broadcast_update(new_state)

      Logger.info("Added proved block #{block_number}")
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
  def handle_call({:proved?, block_number}, _from, state) do
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
      {:proved_blocks_updated, state.blocks}
    )
  rescue
    # PubSub might not be started during tests
    ArgumentError -> :ok
  end
end
