import Config

# Suppress Tesla deprecation warnings (external dependency)
config :tesla, disable_deprecated_builder_warning: true

config :ethproofs_client,
  eth_rpc_url: System.get_env("ETH_RPC_URL"),
  elf_path: System.get_env("ELF_PATH"),
  ethproofs_rpc_url: System.get_env("ETHPROOFS_RPC_URL"),
  ethproofs_api_key: System.get_env("ETHPROOFS_API_KEY"),
  ethproofs_cluster_id: System.get_env("ETHPROOFS_CLUSTER_ID"),
  ecto_repos: [EthProofsClient.Repo]

# Database configuration
config :ethproofs_client, EthProofsClient.Repo,
  database: Path.expand("../ethproofs_client.db", __DIR__),
  pool_size: 5

# Phoenix endpoint configuration
config :ethproofs_client, EthProofsClientWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: EthProofsClientWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: EthProofsClient.PubSub,
  live_view: [signing_salt: "ethproofs_salt"]

# Configure esbuild
config :esbuild,
  version: "0.17.11",
  ethproofs_client: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind
config :tailwind,
  version: "3.4.0",
  ethproofs_client: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
