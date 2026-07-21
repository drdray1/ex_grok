defmodule ExGrok.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/drdray1/ex_grok"

  def project do
    [
      app: :ex_grok,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description: "Elixir client for the xAI Grok API",
      package: package(),

      # Docs
      name: "ExGrok",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ExGrok.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.14"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "ExGrok",
      extras: ["README.md"],
      groups_for_modules: [
        "REST API": [
          ExGrok.Chat,
          ExGrok.Responses,
          ExGrok.Models,
          ExGrok.Images,
          ExGrok.Usage
        ],
        Authentication: [
          ExGrok.Auth
        ],
        Streaming: [
          ExGrok.Streaming
        ],
        Client: [
          ExGrok.Client
        ]
      ]
    ]
  end
end
