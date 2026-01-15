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
