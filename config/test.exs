import Config

# Test configuration - provide dummy values so the application can start
config :ethproofs_client,
  eth_rpc_url: "http://localhost:8545",
  elf_path: "/tmp/test.elf",
  ethproofs_rpc_url: nil,
  ethproofs_api_key: nil,
  ethproofs_cluster_id: nil
