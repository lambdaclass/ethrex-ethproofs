defmodule EthProofsClient.InputGeneratorTest do
  use ExUnit.Case, async: true

  alias EthProofsClient.InputGenerator

  # These tests verify the state machine logic by directly manipulating state
  # and calling handle_* functions that don't trigger external side effects.
  # Tests that would spawn tasks or call RPCs are tested via state inspection.

  describe "init/1" do
    test "initializes with idle state and empty queue" do
      # Note: init also schedules a timer, but we test state only
      {:ok, state} = InputGenerator.init(%{})

      assert state.status == :idle
      assert :queue.is_empty(state.queue)
      assert MapSet.size(state.queued_blocks) == 0
      assert MapSet.size(state.processed_blocks) == 0
    end
  end

  describe "deduplication logic" do
    test "block in queued_blocks is detected" do
      state = new_state() |> enqueue_block(100)

      assert MapSet.member?(state.queued_blocks, 100)
      refute MapSet.member?(state.queued_blocks, 200)
    end

    test "block in processed_blocks is detected" do
      state = new_state() |> mark_processed(100)

      assert MapSet.member?(state.processed_blocks, 100)
      refute MapSet.member?(state.processed_blocks, 200)
    end

    test "currently generating block is detected" do
      state = new_state() |> set_generating(100)

      assert currently_generating?(state, 100)
      refute currently_generating?(state, 200)
    end

    test "queued and processed blocks are disjoint" do
      state =
        new_state()
        |> enqueue_block(100)
        |> mark_processed(200)

      intersection = MapSet.intersection(state.queued_blocks, state.processed_blocks)
      assert MapSet.size(intersection) == 0
    end
  end

  describe "handle_cast {:generate} - deduplication branches" do
    test "skips block already in queue" do
      state =
        new_state()
        |> set_generating(200)
        |> enqueue_block(100)

      {:noreply, new_state} =
        InputGenerator.handle_cast({:generate, 100}, state)

      # Queue length should remain 1
      assert :queue.len(new_state.queue) == 1
    end

    test "skips block currently being generated" do
      state = new_state() |> set_generating(100)

      {:noreply, new_state} =
        InputGenerator.handle_cast({:generate, 100}, state)

      # Queue should remain empty
      assert :queue.is_empty(new_state.queue)
      assert match?({:generating, 100, _}, new_state.status)
    end

    test "skips block already processed" do
      state = new_state() |> mark_processed(100)

      {:noreply, new_state} =
        InputGenerator.handle_cast({:generate, 100}, state)

      # Should not be queued
      assert :queue.is_empty(new_state.queue)
      refute MapSet.member?(new_state.queued_blocks, 100)
    end
  end

  describe "handle_info {ref, result} - task completion" do
    test "transitions to idle on successful completion" do
      ref = make_ref()
      state = new_state() |> set_generating_with_ref(100, ref)

      {:noreply, new_state} =
        InputGenerator.handle_info({ref, {:ok, "/path/to/100.bin"}}, state)

      assert new_state.status == :idle
      assert MapSet.member?(new_state.processed_blocks, 100)
    end

    test "transitions to idle on error completion" do
      ref = make_ref()
      state = new_state() |> set_generating_with_ref(100, ref)

      {:noreply, new_state} =
        InputGenerator.handle_info({ref, {:error, "NIF error"}}, state)

      assert new_state.status == :idle
      # Still marked as processed (won't retry automatically)
      assert MapSet.member?(new_state.processed_blocks, 100)
    end

    test "ignores result from unknown ref" do
      current_ref = make_ref()
      unknown_ref = make_ref()
      state = new_state() |> set_generating_with_ref(100, current_ref)

      {:noreply, new_state} =
        InputGenerator.handle_info({unknown_ref, {:ok, "/path"}}, state)

      # State should remain unchanged
      assert match?({:generating, 100, ^current_ref}, new_state.status)
    end
  end

  describe "handle_info {:DOWN, ...} - task crash" do
    test "transitions to idle on task crash" do
      ref = make_ref()
      state = new_state() |> set_generating_with_ref(100, ref)

      {:noreply, new_state} =
        InputGenerator.handle_info({:DOWN, ref, :process, self(), :killed}, state)

      assert new_state.status == :idle
      # Block NOT marked as processed (allows retry)
      refute MapSet.member?(new_state.processed_blocks, 100)
    end

    test "ignores DOWN from unknown ref" do
      current_ref = make_ref()
      unknown_ref = make_ref()
      state = new_state() |> set_generating_with_ref(100, current_ref)

      {:noreply, new_state} =
        InputGenerator.handle_info({:DOWN, unknown_ref, :process, self(), :normal}, state)

      # State should remain unchanged
      assert match?({:generating, 100, ^current_ref}, new_state.status)
    end
  end

  describe "handle_call :status" do
    test "returns status when idle" do
      state = new_state()

      {:reply, status, ^state} = InputGenerator.handle_call(:status, self(), state)

      assert status.status == :idle
      assert status.queue_length == 0
      assert status.queued_blocks == []
      assert status.processed_count == 0
    end

    test "returns status when generating with queued and processed blocks" do
      state =
        new_state()
        |> set_generating(100)
        |> enqueue_block(200)
        |> enqueue_block(300)
        |> mark_processed(50)

      {:reply, status, ^state} = InputGenerator.handle_call(:status, self(), state)

      assert status.status == {:generating, 100}
      assert status.queue_length == 2
      assert 200 in status.queued_blocks
      assert 300 in status.queued_blocks
      assert status.processed_count == 1
    end
  end

  describe "state transitions" do
    test "idle state has no task ref" do
      state = new_state()

      assert state.status == :idle
    end

    test "generating state contains block number and ref" do
      ref = make_ref()
      state = new_state() |> set_generating_with_ref(100, ref)

      assert match?({:generating, 100, ^ref}, state.status)
    end

    test "queue operations maintain FIFO order" do
      state =
        new_state()
        |> enqueue_block(100)
        |> enqueue_block(200)
        |> enqueue_block(300)

      {{:value, first}, rest} = :queue.out(state.queue)
      {{:value, second}, rest} = :queue.out(rest)
      {{:value, third}, _} = :queue.out(rest)

      assert first == 100
      assert second == 200
      assert third == 300
    end
  end

  describe "crash recovery semantics" do
    test "successful completion marks block as processed" do
      ref = make_ref()
      state = new_state() |> set_generating_with_ref(100, ref)

      {:noreply, new_state} =
        InputGenerator.handle_info({ref, {:ok, "/path"}}, state)

      assert MapSet.member?(new_state.processed_blocks, 100)
    end

    test "crash does NOT mark block as processed (allows retry)" do
      ref = make_ref()
      state = new_state() |> set_generating_with_ref(100, ref)

      {:noreply, new_state} =
        InputGenerator.handle_info({:DOWN, ref, :process, self(), :killed}, state)

      refute MapSet.member?(new_state.processed_blocks, 100)
    end
  end

  # --- Test Helpers ---

  defp new_state do
    %InputGenerator{
      status: :idle,
      queue: :queue.new(),
      queued_blocks: MapSet.new(),
      processed_blocks: MapSet.new()
    }
  end

  defp set_generating(state, block_number) do
    ref = make_ref()
    %{state | status: {:generating, block_number, ref}}
  end

  defp set_generating_with_ref(state, block_number, ref) do
    %{state | status: {:generating, block_number, ref}}
  end

  defp enqueue_block(state, block_number) do
    %{
      state
      | queue: :queue.in(block_number, state.queue),
        queued_blocks: MapSet.put(state.queued_blocks, block_number)
    }
  end

  defp mark_processed(state, block_number) do
    %{state | processed_blocks: MapSet.put(state.processed_blocks, block_number)}
  end

  defp currently_generating?(%{status: {:generating, block_number, _}}, block_number), do: true
  defp currently_generating?(_, _), do: false
end
