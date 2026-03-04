defmodule EthProofsClient.Helpers do
  @moduledoc """
  Shared utility functions for the EthProofs client.
  """

  @doc """
  Truncates text to the given character limit, appending "..." if truncated.
  """
  def truncate(text, limit) when is_binary(text) and is_integer(limit) and limit >= 0 do
    if String.length(text) > limit do
      String.slice(text, 0, limit) <> "..."
    else
      text
    end
  end

  @doc """
  Wraps a value in backticks for Slack inline code display.
  """
  def code_value(value) when is_integer(value), do: "`#{value}`"
  def code_value(value) when is_binary(value), do: "`#{value}`"
  def code_value(value), do: "`#{inspect(value)}`"

  @doc """
  Normalizes error reason tuples into human-readable strings.
  """
  def format_reason({:rpc_get_block_by_number, reason}),
    do: "RPC eth_getBlockByNumber failed: #{format_reason(reason)}"

  def format_reason({:rpc_debug_execution_witness, reason}),
    do: "RPC debug_executionWitness failed: #{format_reason(reason)}"

  def format_reason({:block_metadata, :invalid_block_data}),
    do: "Block metadata parse failed (gasUsed/transactions missing or invalid)"

  def format_reason({:input_generation, reason}),
    do: "Input generator failed: #{format_reason(reason)}"

  def format_reason({:port_exit, reason}),
    do: "cargo-zisk port died: #{format_reason(reason)}"

  def format_reason({:timeout, ms}) when is_integer(ms),
    do: "Proving timeout: exceeded #{div(ms, 1000)}s limit"

  def format_reason({:exit_status, status}) when is_integer(status),
    do: "Prover exited with status #{status}"

  def format_reason({:task_crash, reason}),
    do: "Task crashed: #{format_reason(reason)}"

  def format_reason(:timeout),
    do: "timeout (request did not respond before client timeout)"

  def format_reason(reason) when is_binary(reason), do: reason
  def format_reason(reason), do: inspect(reason)

  @doc """
  Formats a duration in milliseconds as a short human-readable string wrapped in `code_value/1`.

  Returns `nil` for `nil` or non-integer input.

  ## Examples

      iex> format_duration_ms(3_723_000)
      "`1h 2m`"

      iex> format_duration_ms(125_000)
      "`2m 5s`"

      iex> format_duration_ms(7_500)
      "`7s`"
  """
  def format_duration_ms(nil), do: nil

  def format_duration_ms(ms) when is_integer(ms) do
    total_seconds = div(ms, 1_000)
    hours = div(total_seconds, 3_600)
    minutes = div(rem(total_seconds, 3_600), 60)
    seconds = rem(total_seconds, 60)

    formatted =
      cond do
        hours > 0 -> "#{hours}h #{minutes}m"
        minutes > 0 -> "#{minutes}m #{seconds}s"
        true -> "#{seconds}s"
      end

    code_value(formatted)
  end

  def format_duration_ms(_), do: nil

  @doc """
  Formats a Unix timestamp in milliseconds to a local datetime string wrapped in `code_value/1`.

  Returns `nil` for `nil` input.
  """
  def format_timestamp_ms(nil), do: nil

  def format_timestamp_ms(ms) when is_integer(ms) do
    utc_dt = DateTime.from_unix!(ms, :millisecond)
    {{y, mo, d}, {h, mi, s}} = utc_dt |> DateTime.to_naive() |> NaiveDateTime.to_erl()

    # Get local UTC offset by comparing universal and local time
    {{ly, lmo, ld}, {lh, lmi, ls}} =
      :calendar.universal_time_to_local_time({{y, mo, d}, {h, mi, s}})

    offset_seconds =
      :calendar.datetime_to_gregorian_seconds({{ly, lmo, ld}, {lh, lmi, ls}}) -
        :calendar.datetime_to_gregorian_seconds({{y, mo, d}, {h, mi, s}})

    offset_hours = div(offset_seconds, 3_600)
    offset_minutes = div(abs(rem(offset_seconds, 3_600)), 60)

    sign = if offset_seconds >= 0, do: "+", else: "-"

    offset_suffix =
      "#{sign}#{String.pad_leading(Integer.to_string(abs(offset_hours)), 2, "0")}:#{String.pad_leading(Integer.to_string(offset_minutes), 2, "0")}"

    formatted =
      "#{ly}-#{pad(lmo)}-#{pad(ld)} #{pad(lh)}:#{pad(lmi)}:#{pad(ls)} #{offset_suffix}"

    code_value(formatted)
  end

  @doc """
  Computes the non-negative duration in milliseconds between two timestamps.

  Returns `nil` if either input is `nil`.
  """
  def duration_ms(nil, _end_ms), do: nil
  def duration_ms(_start_ms, nil), do: nil

  def duration_ms(start_ms, end_ms) when is_integer(start_ms) and is_integer(end_ms) do
    max(0, end_ms - start_ms)
  end

  # --- Private Helpers ---

  defp pad(int) when int < 10, do: "0#{int}"
  defp pad(int), do: Integer.to_string(int)
end
