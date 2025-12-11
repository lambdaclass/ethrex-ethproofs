defmodule EthProofsClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :ethproofs_client,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      rustlers: [ethrex_ethproofs_input_generator: []]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {EthProofsClient.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:cowboy, "~> 2.9"},
      {:plug, "~> 1.14"},
      {:jason, "~> 1.4"},
      {:rustler, "~> 0.37.1"},
      {:tesla, "~> 1.4"}
    ]
  end
end
