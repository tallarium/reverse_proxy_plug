defmodule ReverseProxyPlug.MixProject do
  use Mix.Project

  @source_url "https://github.com/tallarium/reverse_proxy_plug"
  @version "1.3.2"

  def project do
    [
      app: :reverse_proxy_plug,
      version: @version,
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  defp package do
    [
      description: "An Elixir reverse proxy Plug with HTTP/2, chunked transfer and path " <>
        "proxying support.",
      maintainers: ["Michał Szewczak", "Sam Nipps", "Matt Whitworth"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/tallarium/reverse_proxy_plug"}
    ]
  end

  defp aliases do
    [
      ci: [
        "format --check-formatted",
        "credo --strict",
        "compile --warnings-as-errors --force"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["test/support", "lib"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.6"},
      {:cowboy, "~> 2.4"},
      {:httpoison, "~> 1.2"},
      {:credo, "~> 1.0", only: [:dev, :test]},
      {:mox, "~> 1.0", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      extras: [
        "DEVELOPING.md": [title: "Releasing"],
        "LICENSE.md": [title: "License"],
        "README.md": [title: "Overview"]
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end
end
