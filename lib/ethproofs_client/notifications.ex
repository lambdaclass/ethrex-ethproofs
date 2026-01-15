defmodule EthProofsClient.Notifications do
  @moduledoc false

  require Logger

  alias EthProofsClient.BlockMetadata
  alias EthProofsClient.Helpers
  alias EthProofsClient.Notifications.Slack
  alias EthProofsClient.Rpc
  alias EthProofsClient.SystemInfo

  def input_generation_failed(block_number, reason) do
    notify_event(
      "Block #{block_number} input generation failed.",
      block_number,
      step: "input generation",
      reason: reason,
      status: :failure
    )
  end

  def proof_generation_failed(block_number, reason) do
    notify_event(
      "Block #{block_number} proof generation failed.",
      block_number,
      step: "proof generation",
      reason: reason,
      status: :failure
    )
  end

  def proof_data_failed(block_number, reason) do
    notify_event(
      "Block #{block_number} proof data read failed.",
      block_number,
      step: "proof data read",
      reason: reason,
      status: :failure
    )
  end

  def ethproofs_request_failed(block_number, endpoint, reason) do
    notify_event(
      "Block #{block_number} EthProofs #{endpoint} request failed.",
      block_number,
      step: "ethproofs #{endpoint} request",
      reason: reason,
      status: :failure
    )
  end

  def proof_submitted(block_number, proving_time_ms) do
    notify_event(
      "Block #{block_number} proved and submitted to EthProofs.",
      block_number,
      proving_time_ms: proving_time_ms,
      status: :success
    )
  end

  def rpc_down(url, down_since_ms, reason) do
    notify(
      fn ->
        fields =
          []
          |> add_field("RPC URL", code_value(url))
          |> maybe_add_field("Down since", format_timestamp_ms(down_since_ms))
          |> maybe_add_field("Last error", reason && code_value(format_reason(reason)))

        headline = ":x: ETH RPC down: #{url}"
        %{blocks: build_message_blocks(headline, fields)}
      end,
      "rpc_down url=#{url}"
    )
  end

  def rpc_recovered(url, down_since_ms, recovered_at_ms) do
    notify(
      fn ->
        fields =
          []
          |> add_field("RPC URL", code_value(url))
          |> maybe_add_field("Down since", format_timestamp_ms(down_since_ms))
          |> maybe_add_field("Recovered at", format_timestamp_ms(recovered_at_ms))
          |> maybe_add_field(
            "Downtime",
            format_duration_ms(duration_ms(down_since_ms, recovered_at_ms))
          )

        headline = ":white_check_mark: ETH RPC recovered: #{url}"
        %{blocks: build_message_blocks(headline, fields)}
      end,
      "rpc_recovered url=#{url}"
    )
  end

  defp notify_event(message, block_number, opts) do
    context = notification_context(block_number, opts)

    notify(
      fn ->
        fields =
          []
          |> maybe_add_field("Step", opts[:step] && code_value(opts[:step]))
          |> maybe_add_field("Reason", opts[:reason] && code_value(format_reason(opts[:reason])))
          |> maybe_add_field("Proving time", format_proving_time(opts[:proving_time_ms]))
          |> add_block_fields(block_number)
          |> add_system_fields()

        headline = build_headline(message, opts[:status])
        %{blocks: build_message_blocks(headline, fields)}
      end,
      context
    )
  end

  defp build_headline(message, status) do
    emoji =
      case status do
        :success -> ":white_check_mark:"
        :failure -> ":warning:"
        _ -> nil
      end

    prefix = if emoji, do: emoji <> " ", else: ""
    prefix <> message
  end

  defp add_block_fields(fields, block_number) do
    {gas_used, tx_count} =
      case BlockMetadata.get(block_number) do
        {:ok, %{gas_used: gas_used, tx_count: tx_count}} ->
          {Integer.to_string(gas_used), Integer.to_string(tx_count)}

        _ ->
          {"unknown", "unknown"}
      end

    fields
    |> add_field("Gas used", code_value(gas_used))
    |> add_field("Tx count", code_value(tx_count))
  end

  defp add_system_fields(fields) do
    info = SystemInfo.get()

    fields
    |> add_field("GPU", code_value(info.gpu || "unknown"))
    |> add_field("CPU", code_value(info.cpu || "unknown"))
    |> add_field("RAM", code_value(info.ram || "unknown"))
    |> add_field("Branch & Commit", format_branch_commit(info))
  end

  defp add_field(fields, label, value), do: fields ++ [{label, value}]
  defp maybe_add_field(fields, _label, nil), do: fields
  defp maybe_add_field(fields, label, value), do: add_field(fields, label, value)

  defp format_proving_time(nil), do: nil

  defp format_proving_time(ms) when is_integer(ms) do
    seconds = Float.round(ms / 1000, 2)
    code_value("#{seconds}s")
  end

  defp format_proving_time(_), do: nil

  defp format_timestamp_ms(ms) when is_integer(ms) do
    ms
    |> DateTime.from_unix!(:millisecond)
    |> Helpers.format_local_datetime()
    |> code_value()
  end

  defp format_timestamp_ms(_), do: nil

  defp format_duration_ms(ms) when is_integer(ms) and ms >= 0 do
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

  defp format_duration_ms(_), do: nil

  defp format_branch_commit(%{branch: branch, commit: commit}) do
    branch = branch || "unknown"
    commit = commit || "unknown"
    "#{code_value(branch)} (#{code_value(commit)})"
  end

  defp build_message_blocks(headline, fields) do
    blocks = [
      %{
        type: "header",
        text: %{type: "plain_text", text: headline, emoji: true}
      }
    ]

    case Enum.map_join(fields, "\n", fn {label, value} -> "*#{label}:* #{value}" end) do
      "" -> blocks
      text -> blocks ++ [%{type: "section", text: %{type: "mrkdwn", text: text}}]
    end
  end

  defp notify(build_fun, context) when is_function(build_fun, 0) do
    case notification_status() do
      :enabled ->
        payload = build_fun.()
        summary = notification_summary(payload)
        Logger.debug("Queueing Slack notification#{format_context(context)}: #{summary}")

        Task.start(fn -> Slack.notify(payload) end)

      {:disabled, reason} ->
        Logger.debug("Skipping Slack notification#{format_context(context)}: #{reason}")
    end

    :ok
  end

  defp notification_context(block_number, opts) do
    status = opts[:status] && "status=#{opts[:status]}"
    step = opts[:step] && "step=#{opts[:step]}"

    ["block #{block_number}", status, step]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp notification_summary(payload) do
    case extract_header_text(payload) do
      nil -> inspect(payload, limit: 6, printable_limit: 200)
      text -> Helpers.truncate(text, 200)
    end
  end

  defp extract_header_text(%{blocks: blocks}) when is_list(blocks) do
    Enum.find_value(blocks, fn
      %{type: "header", text: %{text: text}} when is_binary(text) -> text
      _ -> nil
    end)
  end

  defp extract_header_text(_payload), do: nil

  defp format_context(""), do: ""
  defp format_context(context), do: " (" <> context <> ")"

  defp notification_status do
    if enabled?() do
      :enabled
    else
      {:disabled, disabled_reason()}
    end
  end

  defp disabled_reason do
    reasons =
      [
        unless(slack_enabled?(), do: "slack_webhook missing"),
        case missing_config_keys() do
          [] -> nil
          keys -> "ethproofs config missing: #{Enum.join(keys, ", ")}"
        end
      ]
      |> Enum.reject(&is_nil/1)

    case reasons do
      [] -> "notifications disabled"
      _ -> Enum.join(reasons, "; ")
    end
  end

  defp missing_config_keys do
    []
    |> maybe_add_missing("ethproofs_api_key", Rpc.ethproofs_api_key())
    |> maybe_add_missing("ethproofs_cluster_id", Rpc.ethproofs_cluster_id())
    |> maybe_add_missing("ethproofs_rpc_url", Rpc.ethproofs_rpc_url())
  end

  defp maybe_add_missing(keys, _label, value) when not is_nil(value) and value != "", do: keys
  defp maybe_add_missing(keys, label, _value), do: keys ++ [label]

  defp enabled? do
    slack_enabled?() and ethproofs_configured?()
  end

  defp slack_enabled? do
    not blank?(Application.get_env(:ethproofs_client, :slack_webhook))
  end

  defp ethproofs_configured? do
    not blank?(Rpc.ethproofs_api_key()) and
      not blank?(Rpc.ethproofs_cluster_id()) and
      not blank?(Rpc.ethproofs_rpc_url())
  end

  defp blank?(value), do: is_nil(value) or value == ""

  defp code_value(value) when is_integer(value), do: "`#{value}`"
  defp code_value(value) when is_binary(value), do: "`#{value}`"
  defp code_value(value), do: "`#{inspect(value)}`"

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp duration_ms(nil, _), do: nil
  defp duration_ms(_, nil), do: nil

  defp duration_ms(start_ms, end_ms) when is_integer(start_ms) and is_integer(end_ms) do
    max(end_ms - start_ms, 0)
  end

  defp duration_ms(_, _), do: nil
end
