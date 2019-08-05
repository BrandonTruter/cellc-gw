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

## Getting Started

### Dependencies

  * Make sure you have `Elixir` installed. You need to grab two libs:
    - Erlang >= 19.3
    - Elixir >= 1.6.4

### Development

  * Clone the project with `git clone git@bitbucket.org:brandonleetruter/tenbew_gw.git`
  * Install and compile dependencies with `mix do deps.get, deps.compile, compile`
  * Create and migrate database with `mix ecto.create && mix ecto.migrate`
  * Start Server with `mix run --no-halt`

  Now we can response to API requests on [`localhost:4000`](http://localhost:4000)

### Usage

 - Following contains general example of API requests demonstrated via CURL:

 - API calls can also be called under the `api/v1/` namespace

#### Primary / Validation Endpoint

**addsub**

● GET /api/v1/addsub.php?waspTID=QQChina&serviceID=00&mn=CellC_ZA

```bash
$ curl --request GET \
       --url 'http://localhost:4000/addsub.php?waspTID=ABCD&serviceID=123&mn=CellC' \
       --header 'Content-Type: application/json'
```

1. Response: `Parameter` Validation

```
{
  "status": 500,
  "message": "invalid params, missing details"
}
```

2. Response: MSISDN `Format` Validation

```
{
  "status": 501,
  "message": "invalid msisdn, incorrect format"
}
```

3. Response: MSISDN `Existence` & `Status` Validation

```
{
  "status": 502,
  "message": "invalid msisdn, already subscribed"
}
```

#### Other Endpoints

**add_subscription**

● POST /api/v1/add_subscription

```shell
$ curl -POST -H 'Content-Type: application/json' -d '{"msisdn":"0724444444"}' http://localhost:4000/api/v1/add_subscription
```

```
{
  "type": "creation success",
  "message": "Created subscription with MSISDN 0724444444, ref: 2fc861a5-6f1f-4245-9aa8-d4c1c2d88a5c"
}
```

**get_subscription**

● GET /api/v1/get_subscription?msisdn=0724567890

```shell
$ curl "http://localhost:4000/get_subscription?msisdn=0724567890" -H 'Content-Type: application/json'
```

```
{
  "type": "retrieved subscription",
  "message": "MSISDN 0724567890 found, status is: pending"
}
```

**doi/subscriptions**

● POST /api/v1/add_subscription

```shell
$ curl "http://localhost:4000/doi/subscriptions" -H 'Content-Type: application/json'
```

```
[
  {"state":"active","service":"none","reference":"test","msisdn":"27124247232","message":"first subscription","id":1,"api_key":null},
  {"state":"pending","service":"none","reference":"test","msisdn":"27121117232","message":"second subscription","id":2,"api_key":"qa2esYpIiY3z8GuDjzJETgtt"}
]
```

**other**

● GET /

```shell
$ curl "http://localhost:4000/" -H 'Content-Type: application/json'
```

```
  <html><body>You are being <a href="http://localhost:4000/">redirected</a>.</body></html>
```

● GET /api/v1

```shell
$ curl "http://localhost:4000/api/v1" -H 'Content-Type: application/json'
```

```
  {"type":"default","message":"welcome to tenbew gateway"}
```

● GET /anything_else

```shell
$ curl "http://localhost:4000/anything_else" -H 'Content-Type: application/json'
```

```
  {"type":"error","message":"requested endpoint not available"}
```

### Tests

Only basic tests available, which simulate API endpoints above, see output and logs

```bash
  $ iex -S mix
```

```elixir
  alias Util.WebRequest

  WebRequest.test()

  WebRequest.test2()

  WebRequest.test3()

  WebRequest.test4()
```
