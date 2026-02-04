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
    # Record application start time for uptime tracking
    :persistent_term.put(:ethproofs_client_started_at, DateTime.utc_now())

    elf_path =
      Application.get_env(:ethproofs_client, :elf_path) ||
        raise "ELF_PATH environment variable must be set"

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

  @doc """
  Returns the DateTime when the application started.
  """
  def started_at do
    case :persistent_term.get(:ethproofs_client_started_at, nil) do
      nil ->
        # Initialize if not set (can happen after code reload or unusual startup)
        now = DateTime.utc_now()
        :persistent_term.put(:ethproofs_client_started_at, now)
        now

      datetime ->
        datetime
    end
  end
end
