defmodule EthProofsClient.ProvedBlocksStoreTest do
  use ExUnit.Case, async: false

  alias EthProofsClient.Blocks.ProvedBlock
  alias EthProofsClient.ProvedBlocksStore
  alias EthProofsClient.Repo

  # These tests verify the ProvedBlocksStore behavior including database persistence.
  # Tests are not async because they share the database.

  setup do
    # Clear the database before each test
    Repo.delete_all(ProvedBlock)

    # Clear the in-memory store
    ProvedBlocksStore.clear()

    :ok
  end

  describe "init/1" do
    test "initializes with empty state when database is empty" do
      # Clear and restart to test init
      Repo.delete_all(ProvedBlock)

      {:ok, state} = ProvedBlocksStore.init([])

      assert state.blocks == []
      assert state.total_count == 0
      assert MapSet.size(state.block_set) == 0
    end

    test "loads existing blocks from database on init" do
      # Insert blocks directly into database
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        Repo.insert(%ProvedBlock{
          block_number: 100,
          proved_at: now,
          proving_duration_seconds: 3600,
          input_generation_duration_seconds: 120
        })

      {:ok, _} =
        Repo.insert(%ProvedBlock{
          block_number: 200,
          proved_at: DateTime.add(now, 60, :second),
          proving_duration_seconds: 3500,
          input_generation_duration_seconds: 100
        })

      {:ok, state} = ProvedBlocksStore.init([])

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
          Repo.insert(%ProvedBlock{
            block_number: i,
            proved_at: DateTime.add(now, i, :second),
            proving_duration_seconds: 100,
            input_generation_duration_seconds: 10
          })
      end

      {:ok, state} = ProvedBlocksStore.init([])

      # Should load only 100 blocks (the most recent ones)
      assert length(state.blocks) == 100
      assert MapSet.size(state.block_set) == 100

      # Total count should reflect all blocks in DB
      assert state.total_count == 105

      # Most recent blocks should be loaded (blocks 6-105)
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
        ProvedBlocksStore.add_block(100, %{
          proved_at: now,
          proving_duration_seconds: 3600,
          input_generation_duration_seconds: 120
        })

      assert result == :ok

      # Verify in-memory state
      blocks = ProvedBlocksStore.list_blocks()
      assert length(blocks) == 1
      assert hd(blocks).block_number == 100

      # Verify database persistence
      db_blocks = Repo.all(ProvedBlock)
      assert length(db_blocks) == 1
      assert hd(db_blocks).block_number == 100
      assert hd(db_blocks).proving_duration_seconds == 3600
    end

    test "returns :duplicate for already added block" do
      ProvedBlocksStore.add_block(100, %{proved_at: DateTime.utc_now()})

      result = ProvedBlocksStore.add_block(100, %{proved_at: DateTime.utc_now()})

      assert result == :duplicate

      # Should still only have one block
      assert ProvedBlocksStore.count() == 1
      assert Repo.aggregate(ProvedBlock, :count) == 1
    end

    test "uses current time if proved_at not provided" do
      before = DateTime.utc_now()
      ProvedBlocksStore.add_block(100, %{})
      after_time = DateTime.utc_now()

      [block] = ProvedBlocksStore.list_blocks()

      assert DateTime.compare(block.proved_at, before) in [:gt, :eq]
      assert DateTime.compare(block.proved_at, after_time) in [:lt, :eq]
    end

    test "handles nil metadata values" do
      ProvedBlocksStore.add_block(100, %{
        proved_at: DateTime.utc_now(),
        proving_duration_seconds: nil,
        input_generation_duration_seconds: nil
      })

      [block] = ProvedBlocksStore.list_blocks()
      assert block.proving_duration_seconds == nil
      assert block.input_generation_duration_seconds == nil
    end

    test "maintains order with most recent first" do
      now = DateTime.utc_now()

      ProvedBlocksStore.add_block(100, %{proved_at: now})
      ProvedBlocksStore.add_block(200, %{proved_at: DateTime.add(now, 60, :second)})
      ProvedBlocksStore.add_block(300, %{proved_at: DateTime.add(now, 120, :second)})

      blocks = ProvedBlocksStore.list_blocks()
      block_numbers = Enum.map(blocks, & &1.block_number)

      # Most recent (300) should be first
      assert block_numbers == [300, 200, 100]
    end

    test "increments total count on each add" do
      assert ProvedBlocksStore.count() == 0

      ProvedBlocksStore.add_block(100, %{proved_at: DateTime.utc_now()})
      assert ProvedBlocksStore.count() == 1

      ProvedBlocksStore.add_block(200, %{proved_at: DateTime.utc_now()})
      assert ProvedBlocksStore.count() == 2

      ProvedBlocksStore.add_block(300, %{proved_at: DateTime.utc_now()})
      assert ProvedBlocksStore.count() == 3
    end
  end

  describe "list_blocks/0" do
    test "returns empty list when no blocks" do
      assert ProvedBlocksStore.list_blocks() == []
    end

    test "returns blocks in memory cache" do
      ProvedBlocksStore.add_block(100, %{proved_at: DateTime.utc_now()})
      ProvedBlocksStore.add_block(200, %{proved_at: DateTime.utc_now()})

      blocks = ProvedBlocksStore.list_blocks()
      assert length(blocks) == 2
    end
  end

  describe "count/0" do
    test "returns 0 when no blocks" do
      assert ProvedBlocksStore.count() == 0
    end

    test "returns total count including all blocks ever added" do
      now = DateTime.utc_now()

      for i <- 1..150 do
        ProvedBlocksStore.add_block(i, %{proved_at: DateTime.add(now, i, :second)})
      end

      # Count should be 150 even though only 100 are in memory
      assert ProvedBlocksStore.count() == 150
    end
  end

  describe "proved?/1" do
    test "returns false for block not in cache" do
      refute ProvedBlocksStore.proved?(100)
    end

    test "returns true for block in cache" do
      ProvedBlocksStore.add_block(100, %{proved_at: DateTime.utc_now()})

      assert ProvedBlocksStore.proved?(100)
    end

    test "returns false for block not in cache even if in database" do
      # This tests the in-memory cache behavior
      now = DateTime.utc_now()

      # Add 105 blocks to push block 1 out of the cache
      for i <- 1..105 do
        ProvedBlocksStore.add_block(i, %{proved_at: DateTime.add(now, i, :second)})
      end

      # Block 1 is in the database but not in the in-memory cache
      assert Repo.get_by(ProvedBlock, block_number: 1) != nil

      # proved? only checks the cache (MapSet of recent blocks)
      refute ProvedBlocksStore.proved?(1)
      assert ProvedBlocksStore.proved?(105)
    end
  end

  describe "clear/0" do
    test "clears in-memory state" do
      ProvedBlocksStore.add_block(100, %{proved_at: DateTime.utc_now()})
      ProvedBlocksStore.add_block(200, %{proved_at: DateTime.utc_now()})

      ProvedBlocksStore.clear()

      assert ProvedBlocksStore.list_blocks() == []
      assert ProvedBlocksStore.count() == 0
    end

    test "clears database" do
      ProvedBlocksStore.add_block(100, %{proved_at: DateTime.utc_now()})

      ProvedBlocksStore.clear()

      assert Repo.aggregate(ProvedBlock, :count) == 0
    end
  end

  describe "in-memory cache trimming" do
    test "trims blocks when exceeding max_blocks" do
      now = DateTime.utc_now()

      # Add 105 blocks
      for i <- 1..105 do
        ProvedBlocksStore.add_block(i, %{proved_at: DateTime.add(now, i, :second)})
      end

      blocks = ProvedBlocksStore.list_blocks()

      # Should only have 100 blocks in memory
      assert length(blocks) == 100

      # Most recent blocks should be retained
      block_numbers = Enum.map(blocks, & &1.block_number)
      assert 105 in block_numbers
      assert 6 in block_numbers
      refute 5 in block_numbers
    end

    test "block_set is trimmed along with blocks list" do
      now = DateTime.utc_now()

      for i <- 1..105 do
        ProvedBlocksStore.add_block(i, %{proved_at: DateTime.add(now, i, :second)})
      end

      # Old blocks should not be in the set
      refute ProvedBlocksStore.proved?(1)
      refute ProvedBlocksStore.proved?(5)

      # Recent blocks should be in the set
      assert ProvedBlocksStore.proved?(6)
      assert ProvedBlocksStore.proved?(105)
    end
  end

  describe "database persistence" do
    test "init/1 loads data that was previously persisted" do
      # This test verifies that init/1 correctly loads data from the database.
      # The init/1 tests above already cover this, but this provides an
      # additional integration-style verification.

      now = DateTime.utc_now()

      # Add blocks through the store (which persists to DB)
      ProvedBlocksStore.add_block(100, %{proved_at: now, proving_duration_seconds: 3600})
      ProvedBlocksStore.add_block(200, %{proved_at: DateTime.add(now, 60, :second)})

      # Verify blocks are in the database
      assert Repo.aggregate(ProvedBlock, :count) == 2

      # Verify that calling init/1 directly would load the same data
      {:ok, state} = ProvedBlocksStore.init([])

      assert length(state.blocks) == 2
      block_numbers = Enum.map(state.blocks, & &1.block_number)
      assert 100 in block_numbers
      assert 200 in block_numbers

      # Verify metadata was preserved in DB
      block_100 = Enum.find(state.blocks, &(&1.block_number == 100))
      assert block_100.proving_duration_seconds == 3600
    end
  end

  describe "concurrent access" do
    test "handles concurrent add_block calls" do
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            ProvedBlocksStore.add_block(i, %{proved_at: DateTime.utc_now()})
          end)
        end

      results = Task.await_many(tasks)

      # All should succeed (no duplicates in this test)
      assert Enum.all?(results, &(&1 == :ok))

      # All blocks should be added
      assert ProvedBlocksStore.count() == 50
      assert Repo.aggregate(ProvedBlock, :count) == 50
    end

    test "handles concurrent duplicate attempts" do
      # First add the block
      ProvedBlocksStore.add_block(100, %{proved_at: DateTime.utc_now()})

      # Try to add it concurrently multiple times
      tasks =
        for _i <- 1..10 do
          Task.async(fn ->
            ProvedBlocksStore.add_block(100, %{proved_at: DateTime.utc_now()})
          end)
        end

      results = Task.await_many(tasks)

      # All should return :duplicate
      assert Enum.all?(results, &(&1 == :duplicate))

      # Should still only have one block
      assert ProvedBlocksStore.count() == 1
    end
  end

  describe "edge cases" do
    test "handles very large block numbers" do
      large_block = 999_999_999

      ProvedBlocksStore.add_block(large_block, %{proved_at: DateTime.utc_now()})

      assert ProvedBlocksStore.proved?(large_block)
      assert ProvedBlocksStore.count() == 1
    end

    test "handles zero block number" do
      ProvedBlocksStore.add_block(0, %{proved_at: DateTime.utc_now()})

      assert ProvedBlocksStore.proved?(0)
    end

    test "handles empty metadata" do
      ProvedBlocksStore.add_block(100, %{})

      [block] = ProvedBlocksStore.list_blocks()
      assert block.block_number == 100
      assert block.proved_at != nil
    end

    test "preserves all metadata fields" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      ProvedBlocksStore.add_block(100, %{
        proved_at: now,
        proving_duration_seconds: 7200,
        input_generation_duration_seconds: 300
      })

      [block] = ProvedBlocksStore.list_blocks()

      assert block.block_number == 100
      assert block.proved_at == now
      assert block.proving_duration_seconds == 7200
      assert block.input_generation_duration_seconds == 300
    end
  end
end
