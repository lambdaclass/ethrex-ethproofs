import Config

config :ethproofs_client,
  eth_rpc_url: System.get_env("ETH_RPC_URL"),
  elf_path: System.get_env("ELF_PATH")
