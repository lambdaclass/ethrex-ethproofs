defmodule EthProofsClient.ProverTest do
  use ExUnit.Case, async: true

  alias EthProofsClient.Prover

  # These tests verify the state machine logic by directly manipulating state
  # and calling handle_* functions that don't trigger external side effects.
  # Tests that would trigger RPC calls are skipped or use state inspection.

  describe "init/1" do
    test "initializes with idle state and empty queue" do
      {:ok, state} = Prover.init(%{elf: "/path/to/elf"})

      assert state.status == :idle
      assert state.elf == "/path/to/elf"
      assert :queue.is_empty(state.queue)
      assert MapSet.size(state.queued_blocks) == 0
    end
  end

  describe "deduplication logic" do
    test "block in queued_blocks is detected" do
      state = new_state() |> enqueue_block(100)

      assert MapSet.member?(state.queued_blocks, 100)
      refute MapSet.member?(state.queued_blocks, 200)
    end

    test "currently proving block is detected" do
      state = new_state() |> set_proving(100)

      assert currently_proving?(state, 100)
      refute currently_proving?(state, 200)
    end

    test "queued_blocks matches queue contents" do
      state =
        new_state()
        |> enqueue_block(100)
        |> enqueue_block(200)
        |> enqueue_block(300)

      assert MapSet.size(state.queued_blocks) == 3
      assert :queue.len(state.queue) == 3
    end
  end

  describe "handle_cast {:prove} - deduplication branches" do
    test "skips block already in queue" do
      state =
        new_state()
        |> set_proving(200)
        |> enqueue_block(100)

      {:noreply, new_state} =
        Prover.handle_cast({:prove, 100, "/path/to/100.bin", nil}, state)

      # Queue length should remain 1 (not added again)
      assert :queue.len(new_state.queue) == 1
      assert MapSet.size(new_state.queued_blocks) == 1
    end

    test "skips block currently being proved" do
      state = new_state() |> set_proving(100)

      {:noreply, new_state} =
        Prover.handle_cast({:prove, 100, "/path/to/100.bin", nil}, state)

      # Queue should remain empty
      assert :queue.is_empty(new_state.queue)
      # Still proving, not queued
      assert match?({:proving, 100, _}, new_state.status)
    end
  end

  describe "handle_info - port message handling" do
    test "ignores exit_status from unknown port" do
      current_port = make_mock_port()
      unknown_port = make_mock_port()
      state = new_state() |> set_proving_with_port(100, current_port)

      {:noreply, new_state} =
        Prover.handle_info({unknown_port, {:exit_status, 0}}, state)

      # State should remain unchanged - still proving
      assert match?({:proving, 100, ^current_port}, new_state.status)
    end

    test "ignores EXIT from unknown port" do
      current_port = make_mock_port()
      old_port = make_mock_port()
      state = new_state() |> set_proving_with_port(100, current_port)

      {:noreply, new_state} =
        Prover.handle_info({:EXIT, old_port, :normal}, state)

      # State should remain unchanged
      assert match?({:proving, 100, ^current_port}, new_state.status)
    end

    test "ignores data from unknown port" do
      current_port = make_mock_port()
      unknown_port = make_mock_port()
      state = new_state() |> set_proving_with_port(100, current_port)

      {:noreply, new_state} =
        Prover.handle_info({unknown_port, {:data, "output"}}, state)

      assert new_state == state
    end

    test "handles data from current port without state change" do
      port = make_mock_port()
      state = new_state() |> set_proving_with_port(100, port)

      {:noreply, new_state} =
        Prover.handle_info({port, {:data, "some output"}}, state)

      # State unchanged, just logged
      assert new_state == state
    end

    test "EXIT from current port transitions to idle" do
      port = make_mock_port()
      state = new_state() |> set_proving_with_port(100, port)

      {:noreply, new_state} =
        Prover.handle_info({:EXIT, port, :killed}, state)

      # Should transition to idle
      assert new_state.status == :idle
    end
  end

  describe "handle_call :status" do
    test "returns status when idle" do
      state = new_state()

      {:reply, status, ^state} = Prover.handle_call(:status, self(), state)

      assert status.status == :idle
      assert status.queue_length == 0
      assert status.queued_blocks == []
    end

    test "returns status when proving with queued blocks" do
      state =
        new_state()
        |> set_proving(100)
        |> enqueue_block(200)
        |> enqueue_block(300)

      {:reply, status, ^state} = Prover.handle_call(:status, self(), state)

      assert status.status == {:proving, 100}
      assert status.queue_length == 2
      assert 200 in status.queued_blocks
      assert 300 in status.queued_blocks
    end
  end

  describe "state transitions" do
    test "idle state has no port" do
      state = new_state()

      assert state.status == :idle
    end

    test "proving state contains block number and port" do
      port = make_mock_port()
      state = new_state() |> set_proving_with_port(100, port)

      assert match?({:proving, 100, ^port}, state.status)
    end

    test "queue operations maintain FIFO order" do
      state =
        new_state()
        |> enqueue_block(100)
        |> enqueue_block(200)
        |> enqueue_block(300)

      {{:value, {first, _, _}}, rest} = :queue.out(state.queue)
      {{:value, {second, _, _}}, rest} = :queue.out(rest)
      {{:value, {third, _, _}}, _} = :queue.out(rest)

      assert first == 100
      assert second == 200
      assert third == 300
    end
  end

  # --- Test Helpers ---

  defp new_state do
    %Prover{
      status: :idle,
      elf: "/test/elf",
      queue: :queue.new(),
      queued_blocks: MapSet.new(),
      proving_since: nil,
      current_input_gen_duration: nil
    }
  end

  defp set_proving(state, block_number) do
    port = make_mock_port()
    %{state | status: {:proving, block_number, port}}
  end

  defp set_proving_with_port(state, block_number, port) do
    %{state | status: {:proving, block_number, port}}
  end

  defp enqueue_block(state, block_number) do
    %{
      state
      | queue: :queue.in({block_number, "/path/to/#{block_number}.bin", nil}, state.queue),
        queued_blocks: MapSet.put(state.queued_blocks, block_number)
    }
  end

  defp currently_proving?(%{status: {:proving, block_number, _}}, block_number), do: true
  defp currently_proving?(_, _), do: false

  # Create a mock port reference for testing
  defp make_mock_port do
    Port.open({:spawn, "cat"}, [:binary])
  end
end
