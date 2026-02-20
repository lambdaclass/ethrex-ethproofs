defmodule EthProofsClient.Notifications.Slack do
  @moduledoc false
  require Logger

  use Tesla

  alias EthProofsClient.Helpers

  plug(Tesla.Middleware.Headers, [{"content-type", "application/json"}])

  @webhook_key {__MODULE__, :webhook}

  # Send Block Kit payload or plain text to Slack
  def notify(payload) when is_map(payload), do: send_payload(payload)
  def notify(message) when is_binary(message), do: send_payload(%{text: message})

  # Runtime-updatable webhook URL (usable from IEx)
  def set_webhook(url) do
    :persistent_term.put(@webhook_key, url)
  end

  # Returns current webhook URL. Lazy-loads from app config on first call.
  def get_webhook do
    case :persistent_term.get(@webhook_key, :not_set) do
      :not_set ->
        url = Application.get_env(:ethproofs_client, :slack_webhook)
        :persistent_term.put(@webhook_key, url)
        url

      url ->
        url
    end
  end

  # Test helper
  def clear_webhook do
    :persistent_term.erase(@webhook_key)
  rescue
    ArgumentError -> :ok
  end

  defp send_payload(payload) do
    webhook = get_webhook()

    if is_nil(webhook) or webhook == "" do
      Logger.error("Slack webhook missing; dropping notification")
      {:error, :missing_webhook}
    else
      summary = payload_summary(payload)
      Logger.debug("Posting Slack notification: #{summary}")
      body = Jason.encode!(payload)

      case post(webhook, body) do
        {:ok, rsp} ->
          handle_response(rsp)

        {:error, reason} ->
          Logger.error("Slack notification failed: #{inspect(reason)}")
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
