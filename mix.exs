defmodule ReverseProxyPlug.MixProject do
  use Mix.Project

  @source_url "https://github.com/tallarium/reverse_proxy_plug"
  @version "3.0.2"

  def project do
    [
      app: :reverse_proxy_plug,
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [plt_add_apps: [:httpoison, :tesla]]
    ]
  end

  defp package do
    [
      description:
        "An Elixir reverse proxy Plug with HTTP/2, chunked transfer and path " <>
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
        "compile --warnings-as-errors --force",
        "coveralls.html"
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
      {:req, "~> 0.3.0 or ~> 0.4.0 or ~> 0.5.0", optional: true},
      {:finch, "~> 0.18", optional: true},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_test_watch, "~> 1.1", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.6"},
      {:httpoison, "~> 1.2 or ~> 2.0", optional: true},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:hammox, "~> 0.7", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:tesla, "~> 1.4", optional: true},
      {:bypass, "~> 2.1.0", optional: true, only: :test},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
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
