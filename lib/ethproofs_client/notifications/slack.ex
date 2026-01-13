defmodule EthProofsClient.Notifications.Slack do
  @moduledoc false
  require Logger

  use Tesla

  plug(Tesla.Middleware.Headers, [{"content-type", "application/json"}])

  def notify(payload) when is_map(payload), do: send_payload(payload)
  def notify(message) when is_binary(message), do: send_payload(%{text: message})

  defp send_payload(payload) do
    webhook = slack_webhook()
    body = Jason.encode!(payload)

    case post(webhook, body) do
      {:ok, rsp} ->
        handle_response(rsp)

      {:error, reason} ->
        Logger.error("Slack notification failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp slack_webhook do
    Application.get_env(:ethproofs_client, :slack_webhook)
  end

  defp handle_response(%{status: 200}), do: :ok

  defp handle_response(%{status: status, body: body}) do
    Logger.error("Slack webhook error: HTTP #{status}: #{body}")
    {:error, :http_error}
  end
end
