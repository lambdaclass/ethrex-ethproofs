defmodule EthProofsClient.NotificationsTest do
  use ExUnit.Case, async: false

  alias EthProofsClient.BlockMetadata
  alias EthProofsClient.Notifications
  alias EthProofsClient.Notifications.Slack

  setup do
    Slack.clear_webhooks()
    BlockMetadata.init_table()
    BlockMetadata.clear()
    :ok
  end

  describe "enabled?/0" do
    test "returns false when no webhooks are set" do
      Slack.set_webhook(:success, nil)
      Slack.set_webhook(:alerts, nil)
      refute Notifications.enabled?()
    end

    test "returns false when webhooks are empty strings" do
      Slack.set_webhook(:success, "")
      Slack.set_webhook(:alerts, "")
      refute Notifications.enabled?()
    end

    test "returns false when ethproofs vars are missing even with webhooks" do
      Slack.set_webhook(:success, "https://hooks.slack.com/services/T/B/X")
      Slack.set_webhook(:alerts, "https://hooks.slack.com/services/T/B/Y")

      if Application.get_env(:ethproofs_client, :ethproofs_api_key) == nil do
        refute Notifications.enabled?()
      end
    end
  end

  describe "notification functions don't crash when disabled" do
    test "input_generation_failed returns :ok when disabled" do
      Slack.set_webhook(:success, nil)
      Slack.set_webhook(:alerts, nil)
      assert :ok = Notifications.input_generation_failed(100, "some error")
    end

    test "proof_generation_failed returns :ok when disabled" do
      Slack.set_webhook(:success, nil)
      Slack.set_webhook(:alerts, nil)
      assert :ok = Notifications.proof_generation_failed(100, {:port_exit, :killed})
    end

    test "proof_data_failed returns :ok when disabled" do
      Slack.set_webhook(:success, nil)
      Slack.set_webhook(:alerts, nil)
      assert :ok = Notifications.proof_data_failed(100, :enoent)
    end

    test "ethproofs_request_failed returns :ok when disabled" do
      Slack.set_webhook(:success, nil)
      Slack.set_webhook(:alerts, nil)
      assert :ok = Notifications.ethproofs_request_failed(100, "proved", "HTTP 500")
    end

    test "proof_submitted returns :ok when disabled" do
      Slack.set_webhook(:success, nil)
      Slack.set_webhook(:alerts, nil)
      assert :ok = Notifications.proof_submitted(100, 45_300)
    end
  end
end
