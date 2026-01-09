defmodule EthProofsClient.Notifications do
  @moduledoc false

  alias EthProofsClient.Notifications.Slack

  def block_execution_result(block_number, result) when result in [:ok, :error] do
    {event, message} =
      case result do
        :ok -> {:block_executed, "Block #{block_number} executed successfully"}
        :error -> {:block_execution_failed, "Block #{block_number} failed"}
      end

    notify(event, %{
      block_number: block_number,
      status: result,
      message: message
    })
  end

  def block_proving_result(block_number, result) when result in [:ok, :error] do
    {event, message} =
      case result do
        :ok -> {:block_proved, "Block #{block_number} proved successfully"}
        :error -> {:block_proving_failed, "Block #{block_number} proof failed"}
      end

    notify(event, %{
      block_number: block_number,
      status: result,
      message: message
    })
  end

  def notify(event, payload) do
    if slack_enabled?() do
      Task.start(fn -> Slack.notify(event, payload) end)
    end

    :ok
  end

  def slack_enabled? do
    case Application.get_env(:ethproofs_client, :slack_webhook) do
      nil -> false
      "" -> false
      _ -> true
    end
  end
end
