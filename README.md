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

### Dependencies

  * Make sure you have `Elixir` installed. You need to grab two libs:
    - Erlang >= 19.3
    - Elixir >= 1.6.4

### Getting Started

  * Clone the project with `git clone git@bitbucket.org:brandonleetruter/tenbew_gw.git`
  * Install and compile dependencies with `mix do deps.get, deps.compile, compile`
  * Create and migrate database with `mix ecto.create && mix ecto.migrate`
  * Start Server with `mix run --no-halt`

  Now we can response to API requests on [`localhost:4000`](http://localhost:4000)


## API Usage

 - Following contains general example of API requests demonstrated via CURL:

 - API calls can also be called under the `api/v1/` namespace


### Primary Endpoints
These are for external usage to be called from QQ, consisting of 3 API endpoints:

1. AddSub
2. ChargeSub
3. CancelSub

#### REQUEST

**AddSub**

⇒ GET `/api/v1/AddSub?waspTID=QQChina&serviceID=00&msisdn=27124247212&mn=CellC_ZA`

```bash
$ curl "http://156.38.208.218:4000/AddSub?waspTID=QQChina&serviceID=00&msisdn=27124247212&mn=CellC_ZA" -H 'Content-Type: application/json'
```

**ChargeSub**

⇒ GET `/api/v1/ChargeSub?waspTID=QQChina&serviceID=00&msisdn=27124247212&mn=CellC_ZA`

```bash
$ curl "http://156.38.208.218:4000/ChargeSub?waspTID=QQChina&serviceID=00&msisdn=27124242247&mn=CellC_ZA" -H 'Content-Type: application/json'
```

**CancelSub**

⇒ GET `/api/v1/CancelSub?waspTID=QQChina&serviceID=00&msisdn=27124247212&mn=CellC_ZA`

```bash
$ curl "http://156.38.208.218:4000/CancelSub?waspTID=QQChina&serviceID=00&msisdn=27124242247&mn=CellC_ZA" -H 'Content-Type: application/json'
```

#### RESPONSE

* `Parameter` Validations

```
{
  "status": 500, "message": "invalid params, missing details"
}
```

2. MSISDN `Format` Validations

```
{
  "status": 501, "message": "invalid msisdn, incorrect format"
}
```

3. MSISDN `Existence` & `Status` Validations

```
{
  "status": 502, "message": "invalid msisdn, already subscribed"
}
```

### Secondary Endpoints
These are mostly used for internal testing purposes, to create and retrieve following data:

1. Subscriptions
2. Payments

#### SUBSCRIPTIONS

⇒ POST `/api/v1/add_subscription`

**Success**

```bash
$ curl --request POST \
  --url 'http://156.38.208.218:4000/api/v1/add_subscription' \
  --header 'Content-Type: application/json; charset=utf-8' \
  --data $'{ "msisdn": "27124244232", "status": "active" }'
```
Response:
```
  {
    {
      "subscription":{
        "success":{
          "status":"active","services":"testing","msisdn":"27124244232","is_validated":"No","id":"2f9d524a-67c8-41ac-ae25-6bfe7fe56658","date":"2019-08-28T16:26:48"
        }
      }
    }
  }
```

**Failure**

```bash
$ curl --request POST \
  --url 'http://156.38.208.218:4000/api/v1/add_subscription' \
  --header 'Content-Type: application/json; charset=utf-8' \
  --data $'{ "msisdn": "27124244232", "status": "active" }'
```
Response:
```
  {
    "subscription":{
      "error":"Subscription already exists"
    }
  }
```

⇒ GET `/api/v1/get_subscription`

**Success**

```bash
$ curl "http://156.38.208.218:4000/api/v1/get_subscription?msisdn=27124244232" -H 'Content-Type: application/json'
```
Response:
```
  {
    "subscription":{
      "success":"MSISDN 27124244232 found, status is: active"
    }
  }
```

**Failure**

```bash
$ curl "http://156.38.208.218:4000/api/v1/get_subscription?msisdn=27004242247" -H 'Content-Type: application/json'
```
Response:
```
  {
    "subscription":{
      "error":"MSISDN 27004242247 not found"
    }
  }
```

#### PAYMENTS

⇒ POST `/api/v1/add_payment`

**Success**

```bash
$ curl --request POST \
  --url 'http://156.38.208.218:4000/api/v1/add_payment' \
  --header 'Content-Type: application/json; charset=utf-8' \
  --data $'{ "msisdn": "27124240207", "amount": 400 }'
```
Response:
```
  {
    "payment":{
      "success":{
        "status":"paying","payment_date":"2019-08-28T16:33:47","mobile":"27124240207","is_paid":"No","id":"a3dba94c-d6c0-4a52-8a4a-542eafe3242a","amount":400
      }
    }
  }
```

**Failures**

```bash
$ curl -POST -H 'Content-Type: application/json' -d '{"number":"27124240207"}' http://156.38.208.218:4000/api/v1/add_payment
```
Response:
```
  {
    "payment":{
      "error":"msisdn is required"
    }
  }
```

```bash
$ curl -POST -H 'Content-Type: application/json' -d '{"msisdn":"271240207"}' http://156.38.208.218:4000/api/v1/add_payment
```
Response:
```
  {
    "payment":{
      "error":"no subscriber found"
    }
  }
```


⇒ GET `/api/v1/get_payment`

**Success**

```bash
$ curl "http://156.38.208.218:4000/get_payment?msisdn=27124200000" -H 'Content-Type: application/json'
```
Response:
```
  {
    "payment":{
      "success":{
        "status":"paying","payment_date":"2019-08-28T16:38:04","mobile":"27124200000","is_paid":"No","id":"40514000-cdc2-42ab-8ad1-d8d3c5134086","amount":0
      }
    }
  }
```

**Failure**

```bash
$ curl "http://156.38.208.218:4000/get_payment?msisdn=27124242247" -H 'Content-Type: application/json'
```
Response:
```
  {
    "payment":{
      "error":"no payment found"
    }
  }
```


### Other Endpoints
These are other endpoints, either for redirection or to handle unknown requests:

**GET /**

```shell
$ curl "http://156.38.208.218:4000/" -H 'Content-Type: application/json'
```
Response:
```
  <html><body>You are being <a href="http://156.38.208.218:4000/">redirected</a>.</body></html>
```

**GET /api/v1**

```shell
$ curl "http://156.38.208.218:4000/api/v1" -H 'Content-Type: application/json'
```
Response:
```
  {"type":"default","message":"welcome to tenbew gateway"}
```
**GET /anything_else**
●

```shell
$ curl "http://156.38.208.218:4000/anything_else" -H 'Content-Type: application/json'
```
Response:
```
  {"type":"error","message":"requested endpoint not available"}
```
