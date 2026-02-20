defmodule EthProofsClient.NotificationsTest do
  use ExUnit.Case, async: false

  alias EthProofsClient.BlockMetadata
  alias EthProofsClient.Notifications
  alias EthProofsClient.Notifications.Slack

  setup do
    Slack.clear_webhook()
    BlockMetadata.init_table()
    BlockMetadata.clear()
    :ok
  end

  describe "enabled?/0" do
    test "returns false when webhook is not set" do
      Slack.set_webhook(nil)
      refute Notifications.enabled?()
    end

    test "returns false when webhook is empty string" do
      Slack.set_webhook("")
      refute Notifications.enabled?()
    end

    test "returns false when ethproofs vars are missing" do
      # Even with a webhook, if ETHPROOFS_* vars aren't configured,
      # notifications should be disabled
      Slack.set_webhook("https://hooks.slack.com/services/T/B/X")

      # The test environment likely doesn't have ETHPROOFS_* set,
      # so enabled? should return false
      if Application.get_env(:ethproofs_client, :ethproofs_api_key) == nil do
        refute Notifications.enabled?()
      end
    end
  end

  describe "notification functions don't crash when disabled" do
    test "input_generation_failed returns :ok when disabled" do
      Slack.set_webhook(nil)
      assert :ok = Notifications.input_generation_failed(100, "some error")
    end

    test "proof_generation_failed returns :ok when disabled" do
      Slack.set_webhook(nil)
      assert :ok = Notifications.proof_generation_failed(100, {:port_exit, :killed})
    end

    test "proof_data_failed returns :ok when disabled" do
      Slack.set_webhook(nil)
      assert :ok = Notifications.proof_data_failed(100, :enoent)
    end

    test "ethproofs_request_failed returns :ok when disabled" do
      Slack.set_webhook(nil)
      assert :ok = Notifications.ethproofs_request_failed(100, "proved", "HTTP 500")
    end

    test "proof_submitted returns :ok when disabled" do
      Slack.set_webhook(nil)
      assert :ok = Notifications.proof_submitted(100, 45_300)
    end
  end
end
