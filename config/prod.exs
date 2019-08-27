use Mix.Config

config :tenbew_gw, TenbewGw.Endpoint,
  port: String.to_integer(System.get_env("PORT") || "4444")

config :tenbew_gw, TenbewGw.Repo,
  adapter: Ecto.Adapters.MySQL,
  database: "tenbew_prod",
  username: "root",
  password: "",
  hostname: "localhost"
