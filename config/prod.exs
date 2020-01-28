use Mix.Config

# config :tenbew_gw, TenbewGw.Endpoint,
#   port: String.to_integer(System.get_env("PORT") || "4000")

# config :tenbew_gw, TenbewGw.Repo,
#   adapter: Ecto.Adapters.MySQL,
#   database: "tenbew_prod",
#   username: "root",
#   password: "",
#   hostname: "localhost"

config :tenbew_gw, :charges,
  code: "TENB00500",
  value: "5"

config :tenbew_gw, TenbewGw.Repo,
  adapter: Ecto.Adapters.MySQL,
  database: "wotf_core",
  username: "wotf_core",
  password: "wotf_core2020"
