defmodule ReverseProxyPlug.MixProject do
  use Mix.Project

  def project do
    [
      app: :reverse_proxy_plug,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      description: description(),
      package: package()
    ]
  end

  defp description do
    """
    An Elixir reverse proxy Plug with HTTP/2, chunked transfer and path
    proxying support.
    """
  end

  defp package do
    %{
      maintainers: ["Michał Szewczak"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/tallarium/reverse_proxy_plug"}
    }
  end

  defp elixirc_paths(:test), do: ["test/support", "lib"]
  defp elixirc_paths(_), do: ["lib"]

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
      {:credo, "~> 0.5", only: [:dev, :test]},
      {:mox, "~> 0.4", only: :test},
      {:ex_doc, "~> 0.18.0", only: :dev}
    ]
  end
end
