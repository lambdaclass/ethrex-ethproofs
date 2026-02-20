defmodule EthProofsClient.Notifications.SlackTest do
  use ExUnit.Case, async: false

  alias EthProofsClient.Notifications.Slack

  setup do
    Slack.clear_webhook()
    :ok
  end

  describe "set_webhook/1 and get_webhook/0" do
    test "stores and retrieves webhook URL" do
      Slack.set_webhook("https://hooks.slack.com/services/T/B/X")
      assert Slack.get_webhook() == "https://hooks.slack.com/services/T/B/X"
    end

    test "allows updating webhook at runtime" do
      Slack.set_webhook("https://first.url")
      assert Slack.get_webhook() == "https://first.url"

      Slack.set_webhook("https://second.url")
      assert Slack.get_webhook() == "https://second.url"
    end

    test "can set webhook to nil" do
      Slack.set_webhook("https://hooks.slack.com/services/T/B/X")
      Slack.set_webhook(nil)
      assert Slack.get_webhook() == nil
    end
  end

  describe "get_webhook/0 lazy loading" do
    test "loads from app config when not set" do
      # Clear any cached value
      Slack.clear_webhook()

      # The app config may or may not have slack_webhook set.
      # After first call, the value should be cached in persistent_term.
      config_value = Application.get_env(:ethproofs_client, :slack_webhook)
      assert Slack.get_webhook() == config_value
    end
  end

  describe "clear_webhook/0" do
    test "clears cached webhook" do
      Slack.set_webhook("https://hooks.slack.com/services/T/B/X")
      Slack.clear_webhook()

      # After clear, get_webhook will reload from app config
      config_value = Application.get_env(:ethproofs_client, :slack_webhook)
      assert Slack.get_webhook() == config_value
    end
  end

  describe "notify/1" do
    test "returns error when webhook is not configured" do
      Slack.set_webhook(nil)
      assert {:error, :missing_webhook} = Slack.notify(%{text: "test"})
    end

    test "returns error when webhook is empty string" do
      Slack.set_webhook("")
      assert {:error, :missing_webhook} = Slack.notify(%{text: "test"})
    end
  end
end
