use Mix.Config

config :tenbew_gw, ecto_repos: [TenbewGw.Repo]

config :tenbew_gw, TenbewGw.Endpoint, ip: {127,0,0,1}
config :tenbew_gw, TenbewGw.Endpoint, port: 4000

config :tenbew_gw, base_api: "api/v1"

case Mix.env() do
  :dev ->
    config :tenbew_gw, redirect_url: "http://localhost:4000/" # Development

  :test ->
    config :tenbew_gw, redirect_url: "http://localhost:4000/" # Testing

  :prod ->
    config :tenbew_gw, redirect_url: "http://doi.cmobile.co.za/" # Production (PRD)

  _ ->
    config :tenbew_gw, redirect_url: "http://doi-test.cmobile.co.za/" # Pre-production (PPD)
end

# config :tenbew_gw, redirect_url: System.get_env("REDIRECT_URL")

config :tenbew_gw, doi_api_url: "http://localhost:3000/api/v1"

config :tenbew_gw, error_loggers: [:screen, :file_logger]

# config :logger, :console, metadata: [:request_id]

config :logger, utc_log: true

config :logger,
  backends: [{LoggerFileBackend, :info},
             {LoggerFileBackend, :error}]

config :logger, :info,
  metadata: [:request_id],
  path: "log/info.log",
  format: "$date UTC $time [$metadata] [$level] $message\n",
  level: :info

config :logger, :error,
  metadata: [:request_id],
  path: "log/error.log",
  format: "$date UTC $time [$metadata] [$level] $message\n",
  level: :error


import_config "#{Mix.env()}.exs"
