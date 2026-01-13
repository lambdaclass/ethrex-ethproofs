defmodule EthProofsClient.Notifications do
  @moduledoc false

  alias EthProofsClient.Notifications.Slack
  alias EthProofsClient.Rpc

  def input_generation_failed(block_number, reason) do
    notify_failure(block_number, "input generation", reason)
  end

  def proof_generation_failed(block_number, reason) do
    notify_failure(block_number, "proof generation", reason)
  end

  def proof_data_failed(block_number, reason) do
    notify_failure(block_number, "proof data read", reason)
  end

  def ethproofs_request_failed(block_number, endpoint, reason) do
    notify_failure(block_number, "ethproofs #{endpoint} request", reason)
  end

  def proof_submitted(block_number, proving_time_ms) do
    seconds = Float.round(proving_time_ms / 1000, 2)
    message = "Block #{block_number} proved successfully in #{seconds}s and submitted to EthProofs."
    notify(message)
  end

  defp notify_failure(block_number, step, reason) do
    message = "Block #{block_number} failed during #{step}: #{format_reason(reason)}"
    notify(message)
  end

  defp notify(message) do
    if enabled?() do
      Task.start(fn -> Slack.notify(message) end)
    end

    :ok
  end

  defp enabled? do
    slack_enabled?() and ethproofs_configured?()
  end

  defp slack_enabled? do
    case Application.get_env(:ethproofs_client, :slack_webhook) do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  defp ethproofs_configured? do
    not blank?(Rpc.ethproofs_api_key()) and
      not blank?(Rpc.ethproofs_cluster_id()) and
      not blank?(Rpc.ethproofs_rpc_url())
  end

  defp blank?(value), do: is_nil(value) or value == ""

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
