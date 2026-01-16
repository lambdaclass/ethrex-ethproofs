defmodule EthProofsClient.Notifications.Slack do
  @moduledoc false
  require Logger

  use Tesla

  alias EthProofsClient.Helpers

  plug(Tesla.Middleware.Headers, [{"content-type", "application/json"}])

  def notify(payload) when is_map(payload), do: send_payload(payload)
  def notify(message) when is_binary(message), do: send_payload(%{text: message})

  defp send_payload(payload) do
    webhook = slack_webhook()

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

  defp slack_webhook do
    Application.get_env(:ethproofs_client, :slack_webhook)
  end

  defp handle_response(%{status: 200}) do
    Logger.debug("Slack notification delivered")
    :ok
  end

  defp handle_response(%{status: status, body: body}) do
    Logger.error("Slack webhook error: HTTP #{status}: #{body}")
    {:error, :http_error}
  end

  defp payload_summary(%{text: text}) when is_binary(text) do
    Helpers.truncate(text, 200)
  end

  defp payload_summary(%{blocks: blocks}) when is_list(blocks) do
    Enum.find_value(blocks, "blocks", fn
      %{type: "header", text: %{text: text}} when is_binary(text) -> Helpers.truncate(text, 200)
      _ -> nil
    end)
  end

  defp payload_summary(_payload), do: "payload"
end
