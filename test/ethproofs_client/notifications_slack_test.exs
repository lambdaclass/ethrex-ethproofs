defmodule EthProofsClient.Notifications.SlackTest do
  use ExUnit.Case, async: false

  alias EthProofsClient.Notifications.Slack

  setup do
    Slack.clear_webhooks()
    :ok
  end

  describe "set_webhook/2 and get_webhook/1" do
    test "stores and retrieves success webhook" do
      Slack.set_webhook(:success, "https://hooks.slack.com/services/success")
      assert Slack.get_webhook(:success) == "https://hooks.slack.com/services/success"
    end

    test "stores and retrieves alerts webhook" do
      Slack.set_webhook(:alerts, "https://hooks.slack.com/services/alerts")
      assert Slack.get_webhook(:alerts) == "https://hooks.slack.com/services/alerts"
    end

    test "channels are independent" do
      Slack.set_webhook(:success, "https://success.url")
      Slack.set_webhook(:alerts, "https://alerts.url")

      assert Slack.get_webhook(:success) == "https://success.url"
      assert Slack.get_webhook(:alerts) == "https://alerts.url"
    end

    test "allows updating webhook at runtime" do
      Slack.set_webhook(:success, "https://first.url")
      assert Slack.get_webhook(:success) == "https://first.url"

      Slack.set_webhook(:success, "https://second.url")
      assert Slack.get_webhook(:success) == "https://second.url"
    end

    test "can set webhook to nil" do
      Slack.set_webhook(:alerts, "https://hooks.slack.com/services/T/B/X")
      Slack.set_webhook(:alerts, nil)
      assert Slack.get_webhook(:alerts) == nil
    end
  end

  describe "any_webhook_configured?/0" do
    test "returns false when no webhooks set" do
      Slack.set_webhook(:success, nil)
      Slack.set_webhook(:alerts, nil)
      refute Slack.any_webhook_configured?()
    end

    test "returns true when only success webhook set" do
      Slack.set_webhook(:success, "https://hooks.slack.com/services/success")
      Slack.set_webhook(:alerts, nil)
      assert Slack.any_webhook_configured?()
    end

    test "returns true when only alerts webhook set" do
      Slack.set_webhook(:success, nil)
      Slack.set_webhook(:alerts, "https://hooks.slack.com/services/alerts")
      assert Slack.any_webhook_configured?()
    end
  end

  describe "webhook_present?/1" do
    test "returns false for nil webhook" do
      Slack.set_webhook(:success, nil)
      refute Slack.webhook_present?(:success)
    end

    test "returns false for empty string webhook" do
      Slack.set_webhook(:alerts, "")
      refute Slack.webhook_present?(:alerts)
    end

    test "returns true for configured webhook" do
      Slack.set_webhook(:success, "https://hooks.slack.com/services/T/B/X")
      assert Slack.webhook_present?(:success)
    end
  end

  describe "notify/2" do
    test "returns error when webhook is not configured" do
      Slack.set_webhook(:success, nil)
      assert {:error, :missing_webhook} = Slack.notify(%{text: "test"}, :success)
    end

    test "returns error when webhook is empty string" do
      Slack.set_webhook(:alerts, "")
      assert {:error, :missing_webhook} = Slack.notify(%{text: "test"}, :alerts)
    end
  end

  describe "clear_webhooks/0" do
    test "clears all cached webhooks" do
      Slack.set_webhook(:success, "https://success.url")
      Slack.set_webhook(:alerts, "https://alerts.url")
      Slack.clear_webhooks()

      # After clear, get_webhook will reload from app config
      config_success = Application.get_env(:ethproofs_client, :slack_webhook_success)
      config_alerts = Application.get_env(:ethproofs_client, :slack_webhook_alerts)
      assert Slack.get_webhook(:success) == config_success
      assert Slack.get_webhook(:alerts) == config_alerts
    end
  end
end
