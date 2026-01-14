import Config

# Suppress Tesla deprecation warnings (external dependency)
config :tesla, disable_deprecated_builder_warning: true

dev_value = System.get_env("DEV", "false") |> String.downcase()
dev_mode = dev_value in ["1", "true", "yes", "y", "on"]

config :ethproofs_client,
  dev: dev_mode,
  eth_rpc_url: System.get_env("ETH_RPC_URL"),
  elf_path: System.get_env("ELF_PATH"),
  ethproofs_rpc_url: System.get_env("ETHPROOFS_RPC_URL"),
  ethproofs_api_key: System.get_env("ETHPROOFS_API_KEY"),
  ethproofs_cluster_id: System.get_env("ETHPROOFS_CLUSTER_ID"),
  slack_webhook: System.get_env("SLACK_WEBHOOK")

# Import environment specific config
import_config "#{config_env()}.exs"
