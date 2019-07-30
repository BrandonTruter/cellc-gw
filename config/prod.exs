use Mix.Config

config :tenbew_gw, TenbewGw.Endpoint,
  port: String.to_integer(System.get_env("PORT") || "4444")

# config :tenbew_gw, redirect_url: System.get_env("REDIRECT_URL")
