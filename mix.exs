defmodule Cantastic.MixProject do
  use Mix.Project

  def project do
    [
      app: :cantastic,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      description: "An Elixir library to interact with CAN/Bus via lib_socket_can",
      deps: deps(),
      package: package(),
      name: "Cantastic",
      docs: [
        extras: ["README.md", "LICENCE.txt"],
        main: "Cantastic"
      ],
      source_url: "https://github.com/Spin42/cantastic",
      homepage_url: "https://github.com/Spin42/cantastic",
      preferred_cli_env: [espec: :test]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Cantastic.Application, []}
    ]
  end

  defp deps do
    [
      {:yaml_elixir, "~> 2.9"},
      {:jason, "~> 1.2"},
      {:decimal, "~> 2.1.1"},
      {:espec, "~> 1.9.2", only: :test},
      {:faker, "~> 0.18", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package() do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Spin42/cantastic"}
    ]
  end
end
