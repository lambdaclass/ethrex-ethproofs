defmodule EthProofsClient.Helpers do
  @moduledoc """
  Shared utility functions for the EthProofs client.
  """

  @doc """
  Truncates a string to the specified limit, appending "..." if truncated.
  """
  def truncate(text, limit) when is_binary(text) and is_integer(limit) do
    if String.length(text) > limit do
      String.slice(text, 0, limit) <> "..."
    else
      text
    end
  end

  @doc """
  Formats a unix timestamp (milliseconds) in the local timezone.
  """
  def format_timestamp_ms(ms) when is_integer(ms) do
    ms
    |> DateTime.from_unix!(:millisecond)
    |> format_local_datetime()
    |> code_value()
  end

  def format_timestamp_ms(_), do: nil

  @doc """
  Formats a duration in milliseconds as a short string.
  """
  def format_duration_ms(ms) when is_integer(ms) and ms >= 0 do
    seconds = div(ms, 1000)
    minutes = div(seconds, 60)
    hours = div(minutes, 60)
    seconds_rem = rem(seconds, 60)
    minutes_rem = rem(minutes, 60)

    formatted =
      cond do
        hours > 0 -> "#{hours}h #{minutes_rem}m"
        minutes > 0 -> "#{minutes}m #{seconds_rem}s"
        true -> "#{seconds}s"
      end

    code_value(formatted)
  end

  def format_duration_ms(_), do: nil

  @doc """
  Wraps a value in backticks for code display.
  """
  def code_value(value) when is_integer(value), do: "`#{value}`"
  def code_value(value) when is_binary(value), do: "`#{value}`"
  def code_value(value), do: "`#{inspect(value)}`"

  @doc """
  Normalizes a reason value into a readable string.
  """
  def format_reason({:rpc_get_block_by_number, reason}) do
    "RPC eth_getBlockByNumber failed: #{format_reason(reason)}"
  end

  def format_reason({:rpc_debug_execution_witness, reason}) do
    "RPC debug_executionWitness failed: #{format_reason(reason)}"
  end

  def format_reason({:block_metadata, :invalid_block_data}) do
    "Block metadata parse failed (gasUsed/transactions missing or invalid)"
  end

  def format_reason({:input_generation, reason}) do
    "Input generator failed: #{format_reason(reason)}"
  end

  def format_reason(:timeout) do
    "timeout (request did not respond before client timeout)"
  end

  def format_reason(reason) when is_binary(reason), do: reason
  def format_reason(reason), do: inspect(reason)

  @doc """
  Computes a non-negative duration in milliseconds between two timestamps.
  """
  def duration_ms(nil, _), do: nil
  def duration_ms(_, nil), do: nil

  def duration_ms(start_ms, end_ms) when is_integer(start_ms) and is_integer(end_ms) do
    max(end_ms - start_ms, 0)
  end

  def duration_ms(_, _), do: nil

  @doc """
  Formats a DateTime in the local timezone using ISO8601 format.
  """
  def format_local_datetime(%DateTime{} = datetime) do
    # Get local UTC offset in seconds from the system
    offset_seconds = local_utc_offset_seconds()
    local = DateTime.add(datetime, offset_seconds, :second)
    naive = DateTime.to_naive(local)
    {microseconds, _precision} = naive.microsecond
    millis = div(microseconds, 1000)
    naive = %{naive | microsecond: {millis * 1000, 3}}
    NaiveDateTime.to_iso8601(naive) <> format_offset(offset_seconds)
  end

  defp local_utc_offset_seconds do
    # Get current local time and UTC time, calculate difference
    now_utc = DateTime.utc_now()
    utc_erl = now_utc |> DateTime.to_naive() |> NaiveDateTime.to_erl()
    now_local = :calendar.universal_time_to_local_time(utc_erl)
    local_seconds = :calendar.datetime_to_gregorian_seconds(now_local)
    utc_seconds = :calendar.datetime_to_gregorian_seconds(utc_erl)
    local_seconds - utc_seconds
  end

  defp format_offset(offset_seconds) when is_integer(offset_seconds) do
    sign = if offset_seconds >= 0, do: "+", else: "-"
    abs_offset = abs(offset_seconds)
    hours = div(abs_offset, 3600)
    minutes = div(rem(abs_offset, 3600), 60)

    "#{sign}#{String.pad_leading(Integer.to_string(hours), 2, "0")}:#{String.pad_leading(Integer.to_string(minutes), 2, "0")}"
  end
end
