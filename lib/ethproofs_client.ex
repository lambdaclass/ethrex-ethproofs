defmodule EthProofsClient.Application do
  @moduledoc """
  Application supervisor for EthProofsClient.

  ## Supervision Tree

  ```
  EthProofsClient.Supervisor (strategy: :rest_for_one)
  ├── EthProofsClient.TaskSupervisor (Task.Supervisor)
  ├── EthProofsClient.Prover (GenServer)
  ├── EthProofsClient.InputGenerator (GenServer)
  └── Bandit (HTTP server for health endpoints)
  ```

  Uses `:rest_for_one` strategy so that if TaskSupervisor crashes,
  the dependent GenServers are also restarted.
  """

  use Application
  require Logger

  @doc """
  Returns true if the application is running in DEV mode.
  In DEV mode, cargo-zisk runs `execute` instead of `prove` and EthProofs API calls are skipped.
  """
  def dev_mode? do
    Application.get_env(:ethproofs_client, :dev, false) == true
  end

  alias EthProofsClient.HealthRouter
  alias EthProofsClient.InputGenerator
  alias EthProofsClient.Prover

  @default_health_port 4000

  def start(_type, _args) do
    elf_path =
      Application.get_env(:ethproofs_client, :elf_path) ||
        raise "ELF_PATH environment variable must be set"

    if not dev_mode?() do
      ensure_ethproofs_env!()
    end

    health_port = get_health_port()

    children = [
      # TaskSupervisor must start first - InputGenerator depends on it
      {Task.Supervisor, name: EthProofsClient.TaskSupervisor},
      {Prover, elf_path},
      {InputGenerator, []},
      # Health endpoint HTTP server
      {Plug.Cowboy, scheme: :http, plug: HealthRouter, options: [port: health_port]}
    ]

    Logger.info("Starting health endpoint on http://0.0.0.0:#{health_port}/health")

    # :rest_for_one ensures that if TaskSupervisor crashes,
    # Prover and InputGenerator are restarted too
    opts = [strategy: :rest_for_one, name: EthProofsClient.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp get_health_port do
    case System.get_env("HEALTH_PORT") do
      nil -> @default_health_port
      port_str -> String.to_integer(port_str)
    end
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
