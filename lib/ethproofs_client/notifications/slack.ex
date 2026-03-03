defmodule EthProofsClient.Notifications.Slack do
  @moduledoc false
  require Logger

  use Tesla

  alias EthProofsClient.Helpers

  plug(Tesla.Middleware.Headers, [{"content-type", "application/json"}])

  @channels [:success, :alerts]

  # Send Block Kit payload or plain text to the given channel
  def notify(payload, channel) when is_map(payload), do: send_payload(payload, channel)

  def notify(message, channel) when is_binary(message),
    do: send_payload(%{text: message}, channel)

  # Runtime-updatable webhook URLs (usable from IEx)
  def set_webhook(channel, url) when channel in @channels do
    :persistent_term.put(webhook_key(channel), url)
  end

  # Returns current webhook URL for a channel. Lazy-loads from app config on first call.
  def get_webhook(channel) when channel in @channels do
    key = webhook_key(channel)

    case :persistent_term.get(key, :not_set) do
      :not_set ->
        url = Application.get_env(:ethproofs_client, config_key(channel))
        :persistent_term.put(key, url)
        url

      url ->
        url
    end
  end

  # Returns true if at least one webhook is configured
  def any_webhook_configured? do
    Enum.any?(@channels, &webhook_present?/1)
  end

  def webhook_present?(channel) do
    url = get_webhook(channel)
    url != nil and url != ""
  end

  # Test helper
  def clear_webhooks do
    Enum.each(@channels, fn channel ->
      try do
        :persistent_term.erase(webhook_key(channel))
      rescue
        ArgumentError -> :ok
      end
    end)
  end

  defp webhook_key(channel), do: {__MODULE__, :webhook, channel}

  defp config_key(:success), do: :slack_webhook_success
  defp config_key(:alerts), do: :slack_webhook_alerts

  defp send_payload(payload, channel) do
    webhook = get_webhook(channel)

    if is_nil(webhook) or webhook == "" do
      Logger.debug("Slack #{channel} webhook not configured; skipping notification")
      {:error, :missing_webhook}
    else
      summary = payload_summary(payload)
      Logger.debug("Posting Slack notification (#{channel}): #{summary}")
      body = Jason.encode!(payload)

      case post(webhook, body) do
        {:ok, rsp} ->
          handle_response(rsp)

        {:error, reason} ->
          Logger.error("Slack notification failed (#{channel}): #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp handle_response(%{status: 200}) do
    Logger.debug("Slack notification delivered")
    :ok
  end

  defp handle_response(%{status: status, body: body}) do
    Logger.error("Slack webhook error: HTTP #{status}: #{body}")
    {:error, :http_error}
  end

  defp payload_summary(%{text: text}) when is_binary(text), do: Helpers.truncate(text, 200)

  defp payload_summary(%{blocks: blocks}) when is_list(blocks) do
    Enum.find_value(blocks, "blocks", fn
      %{type: "header", text: %{text: text}} when is_binary(text) -> Helpers.truncate(text, 200)
      _ -> nil
    end)
  end

  defp payload_summary(_payload), do: "payload"
end
