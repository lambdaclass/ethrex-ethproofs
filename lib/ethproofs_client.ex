defmodule EthProofsClient.Application do
  @moduledoc """
  Application supervisor for EthProofsClient.

  ## Supervision Tree

  ```
  EthProofsClient.Supervisor (strategy: :rest_for_one)
  ├── Phoenix.PubSub (for real-time updates)
  ├── EthProofsClient.TaskSupervisor (Task.Supervisor)
  ├── EthProofsClient.ProvedBlocksStore (GenServer)
  ├── EthProofsClient.MissedBlocksStore (GenServer)
  ├── EthProofsClient.Prover (GenServer)
  ├── EthProofsClient.InputGenerator (GenServer)
  └── EthProofsClientWeb.Endpoint (Phoenix web server)
  ```

  Uses `:rest_for_one` strategy so that if TaskSupervisor crashes,
  the dependent GenServers are also restarted.
  """

  use Application
  require Logger

  alias EthProofsClient.InputGenerator
  alias EthProofsClient.MissedBlocksStore
  alias EthProofsClient.ProvedBlocksStore
  alias EthProofsClient.Prover

  def start(_type, _args) do
    elf_path =
      Application.get_env(:ethproofs_client, :elf_path) ||
        raise "ELF_PATH environment variable must be set"

    dev_mode = Application.get_env(:ethproofs_client, :dev, false) == true

    if not dev_mode do
      ensure_ethproofs_env!()
    end

    children = [
      # PubSub for real-time updates
      {Phoenix.PubSub, name: EthProofsClient.PubSub},
      # TaskSupervisor must start before InputGenerator depends on it
      {Task.Supervisor, name: EthProofsClient.TaskSupervisor},
      # ProvedBlocksStore tracks proved blocks
      ProvedBlocksStore,
      # MissedBlocksStore tracks failed blocks
      MissedBlocksStore,
      # Core GenServers
      {Prover, elf_path},
      {InputGenerator, []},
      # Phoenix web endpoint
      EthProofsClientWeb.Endpoint
    ]

    # :rest_for_one ensures that if TaskSupervisor crashes,
    # Prover and InputGenerator are restarted too
    opts = [strategy: :rest_for_one, name: EthProofsClient.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Returns the configured endpoint URL for the web interface.
  """
  def config_change(changed, _new, removed) do
    EthProofsClientWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp ensure_ethproofs_env! do
    missing =
      [
        {"ETHPROOFS_RPC_URL", Application.get_env(:ethproofs_client, :ethproofs_rpc_url)},
        {"ETHPROOFS_API_KEY", Application.get_env(:ethproofs_client, :ethproofs_api_key)},
        {"ETHPROOFS_CLUSTER_ID", Application.get_env(:ethproofs_client, :ethproofs_cluster_id)}
      ]
      |> Enum.filter(fn {_, value} -> is_nil(value) or value == "" end)
      |> Enum.map(&elem(&1, 0))

    if missing != [] do
      raise "Missing required env var(s): #{Enum.join(missing, ", ")}. Set DEV=true to disable EthProofs API calls."
    end
  end
end
