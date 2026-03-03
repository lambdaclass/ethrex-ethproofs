defmodule EthProofsClient.HelpersTest do
  use ExUnit.Case, async: true

  alias EthProofsClient.Helpers

  describe "truncate/2" do
    test "returns text unchanged when within limit" do
      assert Helpers.truncate("hello", 10) == "hello"
    end

    test "truncates and appends ... when over limit" do
      assert Helpers.truncate("hello world", 5) == "hello..."
    end

    test "handles exact limit" do
      assert Helpers.truncate("hello", 5) == "hello"
    end

    test "handles zero limit" do
      assert Helpers.truncate("hello", 0) == "..."
    end
  end

  describe "code_value/1" do
    test "wraps string in backticks" do
      assert Helpers.code_value("hello") == "`hello`"
    end

    test "wraps integer in backticks" do
      assert Helpers.code_value(42) == "`42`"
    end

    test "wraps other terms via inspect" do
      assert Helpers.code_value(:atom) == "`:atom`"
    end
  end

  describe "format_reason/1" do
    test "formats port_exit tuple" do
      assert Helpers.format_reason({:port_exit, :killed}) == "cargo-zisk port died: :killed"
    end

    test "formats timeout tuple" do
      assert Helpers.format_reason({:timeout, 60_000}) == "Proving timeout: exceeded 60s limit"
    end

    test "formats task_crash tuple" do
      assert Helpers.format_reason({:task_crash, :killed}) == "Task crashed: :killed"
    end

    test "formats exit_status tuple" do
      assert Helpers.format_reason({:exit_status, 1}) == "Prover exited with status 1"
    end

    test "formats :timeout atom" do
      assert Helpers.format_reason(:timeout) ==
               "timeout (request did not respond before client timeout)"
    end

    test "passes strings through unchanged" do
      assert Helpers.format_reason("some error") == "some error"
    end

    test "inspects unknown terms" do
      assert Helpers.format_reason({:unknown, :stuff}) == "{:unknown, :stuff}"
    end
  end

  describe "format_duration_ms/1" do
    test "formats seconds only" do
      assert Helpers.format_duration_ms(7_500) == "`7s`"
    end

    test "formats minutes and seconds" do
      assert Helpers.format_duration_ms(125_000) == "`2m 5s`"
    end

    test "formats hours and minutes" do
      assert Helpers.format_duration_ms(3_723_000) == "`1h 2m`"
    end

    test "returns nil for nil" do
      assert Helpers.format_duration_ms(nil) == nil
    end

    test "returns nil for non-integer" do
      assert Helpers.format_duration_ms("not a number") == nil
    end
  end

  describe "duration_ms/2" do
    test "computes positive difference" do
      assert Helpers.duration_ms(1000, 5000) == 4000
    end

    test "returns 0 for negative difference" do
      assert Helpers.duration_ms(5000, 1000) == 0
    end

    test "returns nil when start is nil" do
      assert Helpers.duration_ms(nil, 1000) == nil
    end

    test "returns nil when end is nil" do
      assert Helpers.duration_ms(1000, nil) == nil
    end
  end
end
