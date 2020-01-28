use Mix.Config

config :tenbew_gw, TenbewGw.Endpoint, port: 4000
config :tenbew_gw, ecto_repos: [TenbewGw.Repo]
config :tenbew_gw, base_api: "api/v1"

case Mix.env() do
  :dev -> config :tenbew_gw, redirect_url: "http://localhost:4000/"

  :test -> config :tenbew_gw, redirect_url: "http://localhost:4000/"

  :prod -> config :tenbew_gw, redirect_url: "http://doi.cmobile.co.za/"

  _ -> config :tenbew_gw, redirect_url: "http://doi-test.cmobile.co.za/"
end

config :tenbew_gw, msg_gw_id: "5"
config :tenbew_gw, msg_gw_url: "https://msg-gw.tenbew.net/cellc/SendSMS.php"
config :tenbew_gw, doi_api_url: "http://localhost:3000/api/v1"
config :tenbew_gw, cellc_fqdn: "https://cellc.tenbew.net"
config :tenbew_gw, error_loggers: [:screen, :file_logger]
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

# config :tenbew_gw, TenbewGw.Repo,
#   adapter: Ecto.Adapters.MySQL,
#   database: "tenbew",
#   username: "root",
#   password: "",
#   hostname: "localhost"

config :tenbew_gw, :charges,
  code: "DOI005",
  value: "5"

import_config "#{Mix.env()}.exs"
