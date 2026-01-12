defmodule EthProofsClient.Application do
  @moduledoc """
  Application supervisor for EthProofsClient.

  ## Supervision Tree

  ```
  EthProofsClient.Supervisor (strategy: :rest_for_one)
  ├── EthProofsClient.TaskSupervisor (Task.Supervisor)
  ├── EthProofsClient.Prover (GenServer)
  └── EthProofsClient.InputGenerator (GenServer)
  ```

  Uses `:rest_for_one` strategy so that if TaskSupervisor crashes,
  the dependent GenServers are also restarted.
  """

  use Application

  alias EthProofsClient.Prover
  alias EthProofsClient.InputGenerator

  def start(_type, _args) do
    elf_path =
      Application.get_env(:ethproofs_client, :elf_path) ||
        raise "ELF_PATH environment variable must be set"

    children = [
      # TaskSupervisor must start first - InputGenerator depends on it
      {Task.Supervisor, name: EthProofsClient.TaskSupervisor},
      {Prover, elf_path},
      {InputGenerator, []}
    ]

    # :rest_for_one ensures that if TaskSupervisor crashes,
    # Prover and InputGenerator are restarted too
    opts = [strategy: :rest_for_one, name: EthProofsClient.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
