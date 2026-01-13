import Config

# Dev configuration - uses environment variables from shell

config :ethproofs_client, EthProofsClientWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_that_is_at_least_64_bytes_long_for_development_only",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:ethproofs_client, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:ethproofs_client, ~w(--watch)]}
  ]

# Watch static and templates for browser reloading.
config :ethproofs_client, EthProofsClientWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/ethproofs_client_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Enable dev routes for dashboard and mailbox
config :phoenix, :plug_init_mode, :runtime
