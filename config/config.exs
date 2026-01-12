import Config

config :ethproofs_client,
  eth_rpc_url: System.get_env("ETH_RPC_URL"),
  elf_path: System.get_env("ELF_PATH"),
  ethproofs_rpc_url: System.get_env("ETHPROOFS_RPC_URL"),
  ethproofs_api_key: System.get_env("ETHPROOFS_API_KEY"),
  ethproofs_cluster_id: System.get_env("ETHPROOFS_CLUSTER_ID")

# Import environment specific config
import_config "#{config_env()}.exs"
