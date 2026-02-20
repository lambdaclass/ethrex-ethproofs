defmodule EthProofsClient.Notifications do
  @moduledoc false
  require Logger

  alias EthProofsClient.BlockMetadata
  alias EthProofsClient.Helpers
  alias EthProofsClient.Notifications.Slack
  alias EthProofsClient.Rpc
  alias EthProofsClient.SystemInfo

  # --- Public API ---

  def enabled? do
    webhook = Slack.get_webhook()
    webhook != nil and webhook != "" and ethproofs_configured?()
  end

  def input_generation_failed(block_number, reason) do
    notify_event(
      ":warning: Block #{block_number} input generation failed.",
      block_number,
      failure_fields("input generation", reason)
    )
  end

  def proof_generation_failed(block_number, reason) do
    notify_event(
      ":warning: Block #{block_number} proof generation failed.",
      block_number,
      failure_fields("proof generation", reason)
    )
  end

  def proof_data_failed(block_number, reason) do
    notify_event(
      ":warning: Block #{block_number} proof data read failed.",
      block_number,
      failure_fields("proof data read", reason)
    )
  end

  def ethproofs_request_failed(block_number, endpoint, reason) do
    notify_event(
      ":warning: Block #{block_number} EthProofs API (#{endpoint}) failed.",
      block_number,
      failure_fields("EthProofs API (#{endpoint})", reason)
    )
  end

  def proof_submitted(block_number, proving_time_ms) do
    notify_event(
      ":white_check_mark: Block #{block_number} proved and submitted to EthProofs.",
      block_number,
      [{"Proving time", Helpers.format_duration_ms(proving_time_ms)}]
    )
  end

  # --- Private Functions ---

  defp notify_event(headline, block_number, event_fields) do
    if enabled?() do
      meta = block_metadata(block_number)
      sys = SystemInfo.get()
      fields = event_fields ++ block_fields(meta) ++ system_fields(sys)
      payload = %{blocks: build_message_blocks(headline, fields)}

      Task.Supervisor.start_child(EthProofsClient.TaskSupervisor, fn ->
        safe_deliver(payload, "block #{block_number}")
      end)

      :ok
    else
      Logger.debug(
        "Notifications disabled (#{disabled_reason()}), skipping for block #{block_number}"
      )

      :ok
    end
  end

  defp safe_deliver(payload, context) do
    Slack.notify(payload)
  rescue
    e ->
      Logger.error("Slack notification crashed (#{context}): #{inspect(e)}")
  catch
    kind, reason ->
      Logger.error("Slack notification failed (#{context}, #{kind}): #{inspect(reason)}")
  end

  defp disabled_reason do
    cond do
      is_nil(Slack.get_webhook()) or Slack.get_webhook() == "" ->
        "Slack webhook not configured"

      is_nil(Rpc.ethproofs_api_key()) ->
        "ETHPROOFS_API_KEY not set"

      is_nil(Rpc.ethproofs_cluster_id()) ->
        "ETHPROOFS_CLUSTER_ID not set"

      is_nil(Rpc.ethproofs_rpc_url()) ->
        "ETHPROOFS_RPC_URL not set"

      true ->
        nil
    end
  end

  # --- Field Builders ---

  defp failure_fields(step, reason) do
    [
      {"Step", Helpers.code_value(step)},
      {"Reason", Helpers.code_value(Helpers.format_reason(reason))}
    ]
  end

  defp block_fields(meta) do
    [
      {"Gas used", Helpers.code_value(Map.get(meta, :gas_used, "unknown"))},
      {"Tx count", Helpers.code_value(Map.get(meta, :tx_count, "unknown"))}
    ]
  end

  defp system_fields(sys) do
    branch = Map.get(sys, :branch, "unknown")
    commit = Map.get(sys, :commit, "unknown")

    [
      {"GPU", Helpers.code_value(Map.get(sys, :gpu) || "unknown")},
      {"CPU", Helpers.code_value(Map.get(sys, :cpu) || "unknown")},
      {"RAM", Helpers.code_value(Map.get(sys, :ram) || "unknown")},
      {"Branch & Commit", "#{Helpers.code_value(branch)} (#{Helpers.code_value(commit)})"}
    ]
  end

  # --- Message Builder ---

  defp build_message_blocks(headline, fields) do
    blocks = [
      %{type: "header", text: %{type: "plain_text", text: headline, emoji: true}}
    ]

    case Enum.map_join(fields, "\n", fn {label, value} -> "*#{label}:* #{value}" end) do
      "" -> blocks
      text -> blocks ++ [%{type: "section", text: %{type: "mrkdwn", text: text}}]
    end
  end

  defp block_metadata(block_number) do
    case BlockMetadata.get(block_number) do
      {:ok, data} -> data
      :error -> %{}
    end
  end

  defp ethproofs_configured? do
    Rpc.ethproofs_api_key() != nil and
      Rpc.ethproofs_cluster_id() != nil and
      Rpc.ethproofs_rpc_url() != nil
  end
end
