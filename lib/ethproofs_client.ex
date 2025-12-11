defmodule EthProofsClient.Application do
  use Application

  alias EthProofsClient.Prover
  alias EthProofsClient.InputGenerator

  def start(_type, _args) do
    elf_path =
      Application.get_env(:ethproofs_client, :elf_path) ||
        raise "ELF_PATH environment variable must be set"

    children = [
      {Prover, elf_path},
      {InputGenerator, []}
    ]

    opts = [strategy: :one_for_one, name: EthProofsClient.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
