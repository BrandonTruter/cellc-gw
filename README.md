# TenbewGw

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `tenbew_gw` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tenbew_gw, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/tenbew_gw](https://hexdocs.pm/tenbew_gw).

## Usage

1. Run Server

```bash
$ mix run --no-halt
```

This starts the server at: http://localhost:4000/

2. Call API

Example of GET request:

```shell
$ curl "http://localhost:4000/get_subscription?msisdn=0753246218" -H 'Content-Type: application/json'
```

Example of POST request:

```shell
$ curl --request POST \
  --url 'http://localhost:4000/api/v1/add_subscriber' \
  --header 'Content-Type: application/json; charset=utf-8' \
  --data $'{ "msisdn": "0724244223" }'
```

API calls can also be called under the `api/v1/` namespace
