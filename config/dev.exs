use Mix.Config

config :tenbew_gw, TenbewGw.Repo,
  adapter: Ecto.Adapters.MySQL,
  database: "tenbew",
  username: "root",
  password: "",
  hostname: "localhost"

config :tenbew_gw, :charges,
  code: "DOI005",
  value: "5"
