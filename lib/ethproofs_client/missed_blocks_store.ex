defmodule EthProofsClient.MissedBlocksStore do
  @moduledoc """
  GenServer that maintains an ordered list of missed/failed blocks with their metadata.

  Data is persisted to SQLite and loaded on startup. The in-memory cache provides
  fast reads while the database ensures durability across restarts.

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

  import Ecto.Query

  alias EthProofsClient.Blocks.MissedBlock
  alias EthProofsClient.Repo

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
    state = load_from_database()
    Logger.info("MissedBlocksStore initialized with #{state.total_count} blocks from database")
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
  def handle_call({:missed?, block_number}, _from, state) do
    {:reply, MapSet.member?(state.block_set, block_number), state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    Repo.delete_all(MissedBlock)

    new_state = %__MODULE__{}
    broadcast_update(new_state)
    {:reply, :ok, new_state}
  end

  # --- Private Functions ---

  defp do_add_block(block_number, metadata, state) do
    failed_at = Map.get(metadata, :failed_at, DateTime.utc_now())
    stage = Map.get(metadata, :stage, :unknown)
    reason = Map.get(metadata, :reason, "Unknown error")

    case persist_block(block_number, failed_at, stage, reason) do
      {:ok, _} ->
        new_state = update_state_with_block(state, block_number, failed_at, stage, reason)
        broadcast_update(new_state)
        Logger.warning("Missed block #{block_number} at stage #{stage}: #{reason}")
        {:reply, :ok, new_state}

      {:error, changeset} ->
        Logger.error("Failed to persist missed block #{block_number}: #{inspect(changeset.errors)}")
        {:reply, {:error, changeset.errors}, state}
    end
  end

  defp update_state_with_block(state, block_number, failed_at, stage, reason) do
    block = %{
      block_number: block_number,
      failed_at: failed_at,
      stage: stage,
      reason: reason
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
    total_count = Repo.aggregate(MissedBlock, :count)

    # Load last N blocks ordered by failed_at desc
    blocks =
      MissedBlock
      |> order_by([b], desc: b.failed_at)
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
      Logger.warning("Failed to load missed blocks from database: #{inspect(e)}")
      %__MODULE__{}
  end

  defp persist_block(block_number, failed_at, stage, reason) do
    %MissedBlock{}
    |> MissedBlock.changeset(%{
      block_number: block_number,
      failed_at: failed_at,
      stage: stage,
      reason: reason
    })
    |> Repo.insert()
  end

  defp schema_to_map(%MissedBlock{} = block) do
    %{
      block_number: block.block_number,
      failed_at: block.failed_at,
      stage: block.stage,
      reason: block.reason
    }
  end

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
