defmodule EthProofsClient.MissedBlocksStoreTest do
  use ExUnit.Case, async: false

  alias EthProofsClient.Blocks.MissedBlock
  alias EthProofsClient.MissedBlocksStore
  alias EthProofsClient.Repo

  # These tests verify the MissedBlocksStore behavior including database persistence.
  # Tests are not async because they share the database.

  setup do
    # Clear the database before each test
    Repo.delete_all(MissedBlock)

    # Clear the in-memory store
    MissedBlocksStore.clear()

    :ok
  end

  describe "init/1" do
    test "initializes with empty state when database is empty" do
      Repo.delete_all(MissedBlock)

      {:ok, state} = MissedBlocksStore.init([])

      assert state.blocks == []
      assert state.total_count == 0
      assert MapSet.size(state.block_set) == 0
    end

    test "loads existing blocks from database on init" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        Repo.insert(%MissedBlock{
          block_number: 100,
          failed_at: now,
          stage: :input_generation,
          reason: "RPC timeout"
        })

      {:ok, _} =
        Repo.insert(%MissedBlock{
          block_number: 200,
          failed_at: DateTime.add(now, 60, :second),
          stage: :proving,
          reason: "Prover crashed"
        })

      {:ok, state} = MissedBlocksStore.init([])

      assert state.total_count == 2
      assert length(state.blocks) == 2
      assert MapSet.member?(state.block_set, 100)
      assert MapSet.member?(state.block_set, 200)

      # Most recent first
      [first | _] = state.blocks
      assert first.block_number == 200
    end

    test "loads at most max_blocks from database" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Insert 105 blocks (more than @max_blocks = 100)
      for i <- 1..105 do
        {:ok, _} =
          Repo.insert(%MissedBlock{
            block_number: i,
            failed_at: DateTime.add(now, i, :second),
            stage: :proving,
            reason: "Test error"
          })
      end

      {:ok, state} = MissedBlocksStore.init([])

      assert length(state.blocks) == 100
      assert MapSet.size(state.block_set) == 100
      assert state.total_count == 105

      block_numbers = Enum.map(state.blocks, & &1.block_number)
      assert 105 in block_numbers
      assert 6 in block_numbers
      refute 5 in block_numbers
    end
  end

  describe "add_block/2" do
    test "adds a block and persists to database" do
      now = DateTime.utc_now()

      result =
        MissedBlocksStore.add_block(100, %{
          failed_at: now,
          stage: :input_generation,
          reason: "NIF error"
        })

      assert result == :ok

      # Verify in-memory state
      blocks = MissedBlocksStore.list_blocks()
      assert length(blocks) == 1
      assert hd(blocks).block_number == 100
      assert hd(blocks).stage == :input_generation
      assert hd(blocks).reason == "NIF error"

      # Verify database persistence
      db_blocks = Repo.all(MissedBlock)
      assert length(db_blocks) == 1
      assert hd(db_blocks).block_number == 100
      assert hd(db_blocks).stage == :input_generation
    end

    test "returns :duplicate for already added block" do
      MissedBlocksStore.add_block(100, %{
        failed_at: DateTime.utc_now(),
        stage: :proving,
        reason: "Error"
      })

      result =
        MissedBlocksStore.add_block(100, %{
          failed_at: DateTime.utc_now(),
          stage: :input_generation,
          reason: "Different error"
        })

      assert result == :duplicate
      assert MissedBlocksStore.count() == 1
      assert Repo.aggregate(MissedBlock, :count) == 1
    end

    test "uses default values for missing metadata" do
      before = DateTime.utc_now()
      MissedBlocksStore.add_block(100, %{})
      after_time = DateTime.utc_now()

      [block] = MissedBlocksStore.list_blocks()

      assert DateTime.compare(block.failed_at, before) in [:gt, :eq]
      assert DateTime.compare(block.failed_at, after_time) in [:lt, :eq]
      assert block.stage == :unknown
      assert block.reason == "Unknown error"
    end

    test "handles all stage values" do
      now = DateTime.utc_now()

      MissedBlocksStore.add_block(100, %{failed_at: now, stage: :input_generation})
      MissedBlocksStore.add_block(200, %{failed_at: now, stage: :proving})
      MissedBlocksStore.add_block(300, %{failed_at: now, stage: :unknown})

      blocks = MissedBlocksStore.list_blocks()
      stages = Enum.map(blocks, & &1.stage)

      assert :input_generation in stages
      assert :proving in stages
      assert :unknown in stages
    end

    test "maintains order with most recent first" do
      now = DateTime.utc_now()

      MissedBlocksStore.add_block(100, %{failed_at: now})
      MissedBlocksStore.add_block(200, %{failed_at: DateTime.add(now, 60, :second)})
      MissedBlocksStore.add_block(300, %{failed_at: DateTime.add(now, 120, :second)})

      blocks = MissedBlocksStore.list_blocks()
      block_numbers = Enum.map(blocks, & &1.block_number)

      assert block_numbers == [300, 200, 100]
    end

    test "increments total count on each add" do
      assert MissedBlocksStore.count() == 0

      MissedBlocksStore.add_block(100, %{failed_at: DateTime.utc_now()})
      assert MissedBlocksStore.count() == 1

      MissedBlocksStore.add_block(200, %{failed_at: DateTime.utc_now()})
      assert MissedBlocksStore.count() == 2

      MissedBlocksStore.add_block(300, %{failed_at: DateTime.utc_now()})
      assert MissedBlocksStore.count() == 3
    end
  end

  describe "list_blocks/0" do
    test "returns empty list when no blocks" do
      assert MissedBlocksStore.list_blocks() == []
    end

    test "returns blocks in memory cache" do
      MissedBlocksStore.add_block(100, %{failed_at: DateTime.utc_now()})
      MissedBlocksStore.add_block(200, %{failed_at: DateTime.utc_now()})

      blocks = MissedBlocksStore.list_blocks()
      assert length(blocks) == 2
    end
  end

  describe "count/0" do
    test "returns 0 when no blocks" do
      assert MissedBlocksStore.count() == 0
    end

    test "returns total count including all blocks ever added" do
      now = DateTime.utc_now()

      for i <- 1..150 do
        MissedBlocksStore.add_block(i, %{failed_at: DateTime.add(now, i, :second)})
      end

      assert MissedBlocksStore.count() == 150
    end
  end

  describe "missed?/1" do
    test "returns false for block not in cache" do
      refute MissedBlocksStore.missed?(100)
    end

    test "returns true for block in cache" do
      MissedBlocksStore.add_block(100, %{failed_at: DateTime.utc_now()})

      assert MissedBlocksStore.missed?(100)
    end

    test "returns false for block not in cache even if in database" do
      now = DateTime.utc_now()

      for i <- 1..105 do
        MissedBlocksStore.add_block(i, %{failed_at: DateTime.add(now, i, :second)})
      end

      assert Repo.get_by(MissedBlock, block_number: 1) != nil
      refute MissedBlocksStore.missed?(1)
      assert MissedBlocksStore.missed?(105)
    end
  end

  describe "clear/0" do
    test "clears in-memory state" do
      MissedBlocksStore.add_block(100, %{failed_at: DateTime.utc_now()})
      MissedBlocksStore.add_block(200, %{failed_at: DateTime.utc_now()})

      MissedBlocksStore.clear()

      assert MissedBlocksStore.list_blocks() == []
      assert MissedBlocksStore.count() == 0
    end

    test "clears database" do
      MissedBlocksStore.add_block(100, %{failed_at: DateTime.utc_now()})

      MissedBlocksStore.clear()

      assert Repo.aggregate(MissedBlock, :count) == 0
    end
  end

  describe "in-memory cache trimming" do
    test "trims blocks when exceeding max_blocks" do
      now = DateTime.utc_now()

      for i <- 1..105 do
        MissedBlocksStore.add_block(i, %{failed_at: DateTime.add(now, i, :second)})
      end

      blocks = MissedBlocksStore.list_blocks()

      assert length(blocks) == 100

      block_numbers = Enum.map(blocks, & &1.block_number)
      assert 105 in block_numbers
      assert 6 in block_numbers
      refute 5 in block_numbers
    end

    test "block_set is trimmed along with blocks list" do
      now = DateTime.utc_now()

      for i <- 1..105 do
        MissedBlocksStore.add_block(i, %{failed_at: DateTime.add(now, i, :second)})
      end

      refute MissedBlocksStore.missed?(1)
      refute MissedBlocksStore.missed?(5)
      assert MissedBlocksStore.missed?(6)
      assert MissedBlocksStore.missed?(105)
    end
  end

  describe "database persistence" do
    test "init/1 loads data that was previously persisted" do
      now = DateTime.utc_now()

      # Add blocks through the store (which persists to DB)
      MissedBlocksStore.add_block(100, %{
        failed_at: now,
        stage: :proving,
        reason: "Prover timeout"
      })

      MissedBlocksStore.add_block(200, %{
        failed_at: DateTime.add(now, 60, :second),
        stage: :input_generation,
        reason: "RPC error"
      })

      # Verify blocks are in the database
      assert Repo.aggregate(MissedBlock, :count) == 2

      # Verify that calling init/1 directly would load the same data
      {:ok, state} = MissedBlocksStore.init([])

      assert length(state.blocks) == 2
      block_numbers = Enum.map(state.blocks, & &1.block_number)
      assert 100 in block_numbers
      assert 200 in block_numbers

      # Verify metadata was preserved in DB
      block_100 = Enum.find(state.blocks, &(&1.block_number == 100))
      assert block_100.stage == :proving
      assert block_100.reason == "Prover timeout"
    end
  end

  describe "concurrent access" do
    test "handles concurrent add_block calls" do
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            MissedBlocksStore.add_block(i, %{
              failed_at: DateTime.utc_now(),
              stage: :proving,
              reason: "Error #{i}"
            })
          end)
        end

      results = Task.await_many(tasks)

      assert Enum.all?(results, &(&1 == :ok))
      assert MissedBlocksStore.count() == 50
      assert Repo.aggregate(MissedBlock, :count) == 50
    end

    test "handles concurrent duplicate attempts" do
      MissedBlocksStore.add_block(100, %{failed_at: DateTime.utc_now()})

      tasks =
        for _i <- 1..10 do
          Task.async(fn ->
            MissedBlocksStore.add_block(100, %{failed_at: DateTime.utc_now()})
          end)
        end

      results = Task.await_many(tasks)

      assert Enum.all?(results, &(&1 == :duplicate))
      assert MissedBlocksStore.count() == 1
    end
  end

  describe "edge cases" do
    test "handles very large block numbers" do
      large_block = 999_999_999

      MissedBlocksStore.add_block(large_block, %{failed_at: DateTime.utc_now()})

      assert MissedBlocksStore.missed?(large_block)
      assert MissedBlocksStore.count() == 1
    end

    test "handles zero block number" do
      MissedBlocksStore.add_block(0, %{failed_at: DateTime.utc_now()})

      assert MissedBlocksStore.missed?(0)
    end

    test "handles long reason strings" do
      long_reason = String.duplicate("Error details. ", 100)

      MissedBlocksStore.add_block(100, %{
        failed_at: DateTime.utc_now(),
        reason: long_reason
      })

      [block] = MissedBlocksStore.list_blocks()
      assert block.reason == long_reason
    end

    test "preserves all metadata fields" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      MissedBlocksStore.add_block(100, %{
        failed_at: now,
        stage: :proving,
        reason: "Prover crashed with OOM"
      })

      [block] = MissedBlocksStore.list_blocks()

      assert block.block_number == 100
      assert block.failed_at == now
      assert block.stage == :proving
      assert block.reason == "Prover crashed with OOM"
    end
  end

  describe "interaction between stage and reason" do
    test "correctly stores input_generation failures" do
      MissedBlocksStore.add_block(100, %{
        failed_at: DateTime.utc_now(),
        stage: :input_generation,
        reason: "NIF panicked"
      })

      [block] = MissedBlocksStore.list_blocks()
      assert block.stage == :input_generation
      assert block.reason == "NIF panicked"
    end

    test "correctly stores proving failures" do
      MissedBlocksStore.add_block(100, %{
        failed_at: DateTime.utc_now(),
        stage: :proving,
        reason: "cargo-zisk error: out of memory"
      })

      [block] = MissedBlocksStore.list_blocks()
      assert block.stage == :proving
      assert block.reason == "cargo-zisk error: out of memory"
    end
  end
end
