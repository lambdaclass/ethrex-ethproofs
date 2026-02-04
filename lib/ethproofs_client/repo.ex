defmodule EthProofsClient.Repo do
  use Ecto.Repo,
    otp_app: :ethproofs_client,
    adapter: Ecto.Adapters.SQLite3
end
