defmodule TenbewGw.MixProject do
  use Mix.Project

  def project do
    [
      app: :tenbew_gw,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TenbewGw.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.6"},
      {:cowboy, "~> 2.4"},
      {:poison, "~> 2.0"},
      {:plug_cowboy, "~> 2.0"},
      {:mariaex, "~> 0.8.2", override: true},
      {:ecto, github: "elixir-ecto/ecto", override: true},
      {:ecto_sql, github: "elixir-ecto/ecto_sql", override: true},
      {:myxql, "~> 0.2.0",  github: "elixir-ecto/myxql", override: true},
      {:db_connection, "~> 2.0",  github: "elixir-ecto/db_connection", override: true},
      {:jason, "~> 1.0"},
      {:hackney, github: "benoitc/hackney", override: true},
      {:short_maps, github: "whatyouhide/short_maps"}
    ]
  end
end
