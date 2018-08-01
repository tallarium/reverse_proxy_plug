defmodule ReverseProxyPlug.MixProject do
  use Mix.Project

  def project do
    [
      app: :reverse_proxy_plug,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.6"},
      {:cowboy, "~> 2.4"},
      {:httpoison, "~> 1.2"},
      {:credo, "~> 0.5", only: [:dev, :test]}
    ]
  end
end
