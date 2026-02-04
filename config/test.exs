import Config

# Test configuration - provide dummy values so the application can start
config :ethproofs_client,
  eth_rpc_url: "http://localhost:8545",
  elf_path: "/tmp/test.elf",
  ethproofs_rpc_url: nil,
  ethproofs_api_key: nil,
  ethproofs_cluster_id: nil

# Phoenix test configuration
config :ethproofs_client, EthProofsClientWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_that_is_at_least_64_bytes_long_for_testing_purposes",
  server: false
