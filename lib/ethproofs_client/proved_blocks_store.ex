defmodule EthProofsClient.ProvedBlocksStore do
  @moduledoc """
  GenServer that maintains an ordered list of proved blocks with their metadata.

  Data is persisted to SQLite and loaded on startup. The in-memory cache provides
  fast reads while the database ensures durability across restarts.

  This store is designed to:
  - Keep the last N proved blocks in memory (loaded from DB on init)
  - Persist all blocks to SQLite for durability
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

  import Ecto.Query

  alias EthProofsClient.Blocks.ProvedBlock
  alias EthProofsClient.Repo

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
    state = load_from_database()
    Logger.info("ProvedBlocksStore initialized with #{state.total_count} blocks from database")
    {:ok, state}
  end

  @impl true
  def handle_call({:add_block, block_number, metadata}, _from, state) do
    if MapSet.member?(state.block_set, block_number) do
      {:reply, :duplicate, state}
    else
      do_add_block(block_number, metadata, state)
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
    Repo.delete_all(ProvedBlock)

    new_state = %__MODULE__{}
    broadcast_update(new_state)
    {:reply, :ok, new_state}
  end

  # --- Private Functions ---

  defp do_add_block(block_number, metadata, state) do
    proved_at = Map.get(metadata, :proved_at, DateTime.utc_now())

    case persist_block(block_number, metadata, proved_at) do
      {:ok, _} ->
        new_state = update_state_with_block(state, block_number, metadata, proved_at)
        broadcast_update(new_state)
        Logger.info("Added proved block #{block_number}")
        {:reply, :ok, new_state}

      {:error, changeset} ->
        Logger.error("Failed to persist proved block #{block_number}: #{inspect(changeset.errors)}")
        {:reply, {:error, changeset.errors}, state}
    end
  end

  defp update_state_with_block(state, block_number, metadata, proved_at) do
    block = %{
      block_number: block_number,
      proved_at: proved_at,
      proving_duration_seconds: Map.get(metadata, :proving_duration_seconds),
      input_generation_duration_seconds: Map.get(metadata, :input_generation_duration_seconds)
    }

    new_blocks = [block | state.blocks] |> Enum.take(@max_blocks)
    new_block_set = MapSet.put(state.block_set, block_number)
    new_block_set = trim_block_set(state.blocks, new_block_set)

    %{
      state
      | blocks: new_blocks,
        block_set: new_block_set,
        total_count: state.total_count + 1
    }
  end

  defp trim_block_set(blocks, block_set) when length(blocks) >= @max_blocks do
    oldest = List.last(blocks)
    MapSet.delete(block_set, oldest.block_number)
  end

  defp trim_block_set(_blocks, block_set), do: block_set

  defp load_from_database do
    # Get total count
    total_count = Repo.aggregate(ProvedBlock, :count)

    # Load last N blocks ordered by proved_at desc
    blocks =
      ProvedBlock
      |> order_by([b], desc: b.proved_at)
      |> limit(@max_blocks)
      |> Repo.all()
      |> Enum.map(&schema_to_map/1)

    # Build the set from loaded blocks
    block_set = blocks |> Enum.map(& &1.block_number) |> MapSet.new()

    %__MODULE__{
      blocks: blocks,
      block_set: block_set,
      total_count: total_count
    }
  rescue
    e ->
      Logger.warning("Failed to load proved blocks from database: #{inspect(e)}")
      %__MODULE__{}
  end

  defp persist_block(block_number, metadata, proved_at) do
    %ProvedBlock{}
    |> ProvedBlock.changeset(%{
      block_number: block_number,
      proved_at: proved_at,
      proving_duration_seconds: Map.get(metadata, :proving_duration_seconds),
      input_generation_duration_seconds: Map.get(metadata, :input_generation_duration_seconds)
    })
    |> Repo.insert()
  end

  defp schema_to_map(%ProvedBlock{} = block) do
    %{
      block_number: block.block_number,
      proved_at: block.proved_at,
      proving_duration_seconds: block.proving_duration_seconds,
      input_generation_duration_seconds: block.input_generation_duration_seconds
    }
  end

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
