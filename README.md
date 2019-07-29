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



  git remote add origin git@bitbucket.org:brandonleetruter/tenbew_gw.git

  git push -u origin master



iex -S mix

alias Util.WebRequest

> WebRequest.test()

16:56:18.250 [info]  URL "http://localhost:4000/api/v1/get_subscription?msisdn=0712363482" BODY ""

16:56:18.253 [debug] GET /api/v1/get_subscription

16:56:18.253 [info]  get_subscription/2

16:56:18.266 [debug] QUERY OK source="subscriptions" db=0.3ms queue=0.4ms
SELECT s0.`id`, s0.`msisdn`, s0.`status`, s0.`services`, s0.`validated`, s0.`inserted_at`, s0.`updated_at` FROM `subscriptions` AS s0 WHERE (s0.`msisdn` = ?) ["0712363482"]
No Subscription found, so creating it

16:56:18.267 [info]  create_subscription/1 :: "0712363482"

16:56:18.489 [debug] QUERY OK db=168.9ms queue=0.4ms
INSERT INTO `subscriptions` (`msisdn`,`status`,`inserted_at`,`updated_at`,`id`) VALUES (?,?,?,?,?) ["0712363482", "pending", ~N[2019-07-29 14:56:18], ~N[2019-07-29 14:56:18], <<1, 211, 123, 164, 149, 175, 73, 214, 148, 194, 205, 73, 9, 211, 152, 117>>]

16:56:18.492 [info]  Subscription created successfully: %TenbewGw.Model.Subscription{__meta__: #Ecto.Schema.Metadata<:loaded, "subscriptions">, id: "01d37ba4-95af-49d6-94c2-cd4909d39875", inserted_at: ~N[2019-07-29 14:56:18], msisdn: "0712363482", services: nil, status: "pending", updated_at: ~N[2019-07-29 14:56:18], validated: nil}

16:56:18.493 [debug] Sent 200 in 240ms

16:56:18.493 [info]  ref: #Reference<0.209680231.2801532929.74678>

16:56:18.494 [info]  headers at loop: [{"cache-control", "max-age=0, private, must-revalidate"}, {"content-length", "77"}, {"content-type", "application/json; charset=utf-8"}, {"date", "Mon, 29 Jul 2019 14:56:17 GMT"}, {"server", "Cowboy"}]

16:56:18.494 [info]  ref: #Reference<0.209680231.2801532929.74678>

16:56:18.494 [info]  ref: #Reference<0.209680231.2801532929.74678>

16:56:18.494 [info]  hackney: status: 200 "{\"text\":\"MSISDN 0712363482 not found\",\"response_type\":\"subscription created\"}"
%{
  "response_type" => "subscription created",
  "text" => "MSISDN 0712363482 not found"
}


> WebRequest.test2()

17:03:24.326 [debug] QUERY OK source="subscriptions" db=0.5ms
SELECT s0.`id`, s0.`msisdn`, s0.`status`, s0.`services`, s0.`validated`, s0.`inserted_at`, s0.`updated_at` FROM `subscriptions` AS s0 []

17:03:24.326 [info]  URL "http://localhost:4000/api/v1/add_subscriber" BODY %{"msisdn" => "0712363482"}

17:03:24.330 [debug] POST /api/v1/add_subscriber

17:03:24.330 [info]  add_subscriber/2

17:03:24.332 [debug] QUERY OK source="subscriptions" db=1.5ms
SELECT s0.`id`, s0.`msisdn`, s0.`status`, s0.`services`, s0.`validated`, s0.`inserted_at`, s0.`updated_at` FROM `subscriptions` AS s0 WHERE (s0.`msisdn` = ?) ["0712363482"]

17:03:24.332 [debug] Sent 200 in 2ms

17:03:24.333 [info]  ref: #Reference<0.209680231.2801532929.75683>

17:03:24.333 [info]  headers at loop: [{"cache-control", "max-age=0, private, must-revalidate"}, {"content-length", "95"}, {"content-type", "application/json; charset=utf-8"}, {"date", "Mon, 29 Jul 2019 15:03:23 GMT"}, {"server", "Cowboy"}]

17:03:24.333 [info]  ref: #Reference<0.209680231.2801532929.75683>

17:03:24.333 [info]  ref: #Reference<0.209680231.2801532929.75683>

17:03:24.333 [info]  hackney: status: 200 "{\"text\":\"Subscription for MSISDN 0712363482 already exists\",\"response_type\":\"creation stopped\"}"
%{
  "response_type" => "creation stopped",
  "text" => "Subscription for MSISDN 0712363482 already exists"
}


> WebRequest.test3()

17:06:24.874 [info]  URL "http://localhost:4000/api/v1/add_subscriber" BODY %{"unknown" => "1231"}

17:06:24.878 [debug] POST /api/v1/add_subscriber

17:06:24.878 [info]  add_subscriber/2

17:06:24.878 [debug] Sent 200 in 199µs

17:06:24.879 [info]  ref: #Reference<0.209680231.2801532931.80066>

17:06:24.879 [info]  headers at loop: [{"cache-control", "max-age=0, private, must-revalidate"}, {"content-length", "63"}, {"content-type", "application/json; charset=utf-8"}, {"date", "Mon, 29 Jul 2019 15:06:24 GMT"}, {"server", "Cowboy"}]

17:06:24.879 [info]  ref: #Reference<0.209680231.2801532931.80066>

17:06:24.879 [info]  ref: #Reference<0.209680231.2801532931.80066>

17:06:24.879 [info]  hackney: status: 200 "{\"text\":\"MSISDN is required\",\"response_type\":\"creation failed\"}"
%{"response_type" => "creation failed", "text" => "MSISDN is required"}

> WebRequest.test4()

17:05:27.728 [info]  URL "http://localhost:4000/api/v1/add_subscriber" BODY %{"msisdn" => "0723321527"}

17:05:27.731 [debug] POST /api/v1/add_subscriber

17:05:27.731 [info]  add_subscriber/2

17:05:27.736 [debug] QUERY OK source="subscriptions" db=1.0ms
SELECT s0.`id`, s0.`msisdn`, s0.`status`, s0.`services`, s0.`validated`, s0.`inserted_at`, s0.`updated_at` FROM `subscriptions` AS s0 WHERE (s0.`msisdn` = ?) ["0723321527"]

17:05:27.736 [info]  create_subscription/1 :: "0723321527"

17:05:27.900 [debug] QUERY OK db=162.7ms queue=0.4ms
INSERT INTO `subscriptions` (`msisdn`,`status`,`inserted_at`,`updated_at`,`id`) VALUES (?,?,?,?,?) ["0723321527", "pending", ~N[2019-07-29 15:05:27], ~N[2019-07-29 15:05:27], <<53, 8, 87, 184, 248, 5, 79, 8, 175, 138, 104, 80, 38, 143, 195, 197>>]

17:05:27.900 [info]  Subscription created successfully: %TenbewGw.Model.Subscription{__meta__: #Ecto.Schema.Metadata<:loaded, "subscriptions">, id: "350857b8-f805-4f08-af8a-6850268fc3c5", inserted_at: ~N[2019-07-29 15:05:27], msisdn: "0723321527", services: nil, status: "pending", updated_at: ~N[2019-07-29 15:05:27], validated: nil}

17:05:27.902 [debug] QUERY OK source="subscriptions" db=1.1ms
SELECT s0.`id`, s0.`msisdn`, s0.`status`, s0.`services`, s0.`validated`, s0.`inserted_at`, s0.`updated_at` FROM `subscriptions` AS s0 WHERE (s0.`msisdn` = ?) ["0723321527"]

17:05:27.902 [debug] Sent 200 in 170ms

17:05:27.902 [info]  ref: #Reference<0.209680231.2801532932.75211>

17:05:27.903 [info]  headers at loop: [{"cache-control", "max-age=0, private, must-revalidate"}, {"content-length", "132"}, {"content-type", "application/json; charset=utf-8"}, {"date", "Mon, 29 Jul 2019 15:05:27 GMT"}, {"server", "Cowboy"}]

17:05:27.903 [info]  ref: #Reference<0.209680231.2801532932.75211>

17:05:27.903 [info]  ref: #Reference<0.209680231.2801532932.75211>

17:05:27.903 [info]  hackney: status: 200 "{\"text\":\"Created subscription with MSISDN 0723321527, ref: 350857b8-f805-4f08-af8a-6850268fc3c5\",\"response_type\":\"creation success\"}"
%{
  "response_type" => "creation success",
  "text" => "Created subscription with MSISDN 0723321527, ref: 350857b8-f805-4f08-af8a-6850268fc3c5"
}




ELIXIR APP

1. Setup

$ mix new tenbew_gw --sup
$ mix do deps.get, deps.compile, compile

2. Create

$ touch lib/tenbew_gw/endoint.ex lib/tenbew_gw/router.ex
$ touch config/dev.exs config/prod.exs config/test.exs

3. Start

$ mix run --no-halt

Server starts on: http://localhost:4000/

API calls can then be made to :
  - api/v1/
  - /


curl "http://localhost:4000/" -H 'Content-Type: application/json'

curl "http://localhost:4000/get_subscription?msisdn=0753246218" -H 'Content-Type: application/json'

  {"text":"MSISDN 0753246218 found, status is: pending","response_type":"subscription retrieved"}

curl "http://localhost:4000/api/v1/get_subscription?msisdn=0753246218" -H 'Content-Type: application/json'



curl -XPOST -d "name=test" http://localhost:4000/add_subscriber


╰─○ curl --request GET \
  --url 'http://localhost:4000/' \                
  --header 'Content-Type: application/json'                 

  {"text":"welcome to our gateway :)","response_type":"default"}


curl --request GET \
  --url 'http://localhost:4000/get_subscription?msisdn=0753246218' \
  --header 'Content-Type: application/json'

  {"text":"MSISDN 0753246218 not found","response_type":"subscription created"}

╰─○ curl --request GET \
  --url 'http://localhost:4000/get_subscription?msisdn=0753246218' \
  --header 'Content-Type: application/json'

  {"text":"MSISDN 0753246218 found, status is: pending","response_type":"subscription retrieved"}

╰─○ curl --request POST \
  --url 'http://localhost:4000/api/v1/add_subscriber' \             
  --header 'Content-Type: application/json; charset=utf-8' \
  --data $'{ "msisdn": "0724244444" }'

  {"text":"Subscription for MSISDN 0724244444 already exists","response_type":"creation stopped"}

╰─○ curl --request POST \
  --url 'http://localhost:4000/api/v1/add_subscriber' \
  --header 'Content-Type: application/json; charset=utf-8' \
  --data $'{ "msisdn": "0724244223" }'

  {"text":"Created subscription with MSISDN 0724244223, ref: 0bd326f5-a452-4bbf-8034-a3c87568beff","response_type":"creation success"}

curl --request POST \
  --url 'http://localhost:4000/api/v1/add_subscriber' \
  --header 'Content-Type: application/json; charset=utf-8' \
  --data $'{ "msisdn": "0724244223" }'

  {"text":"Subscription for MSISDN 0724244223 already exists","response_type":"creation stopped"}



  > iex -S mix

  iex(1)> import Ecto.Query
  nil
  iex(2)> F1History.Repo.one from race in F1History.Race, limit: 1






iex -S mix

{:ok, pid} = MyXQL.start_link(username: "root", database: "tenbew")
MyXQL.query!(pid, "INSERT INTO subscriptions (id, msisdn, status) VALUES (1, '0723456437', 'pending')")

curl http://localhost:4000/hello_bot?msisdn=0723456437

%TenbewGw.Model.Subscription{
  __meta__: #Ecto.Schema.Metadata<:loaded, "subscriptions">,
  id: "b2a208da-2305-4bdc-999a-74bf93da8157",
  inserted_at: ~N[2019-07-26 13:31:47],
  msisdn: "0723246218",
  services: nil,
  status: "pending",
  updated_at: ~N[2019-07-26 13:31:47],
  validated: nil
}


curl -XPOST -d "name=test" http://localhost:4000/add_subscriber

curl -XPOST -d "name=test" http://localhost:4000/add_subscriber




curl --request GET \
  --url 'http://localhost:4000/get_subscription?msisdn=0723246622' \
  --header 'Content-Type: application/json'

  {"text":"MSISDN 0723246622 not found","response_type":"subscription created"}


curl --request GET \
  --url 'http://localhost:4000/get_subscription?msisdn=0723246218' \
  --header 'Content-Type: application/json'

  {"text":"MSISDN 0723246218 exists, status is: pending","response_type":"subscription retrieved"}


  curl -XPOST -d "name=test" http://localhost:4000/add_subscriber


curl --request POST \
  --url 'http://localhost:4000/add_subscriber' \
  --header 'Content-Type: application/json; charset=utf-8' \
  --data $'{ "msisdn": "0723246218" }'

curl http://localhost:4000/hello_bot
curl http://localhost:4000/add_subscriber


4. Database

mysql -uroot -p -A
create database tenbew

add dependencies
  $ mix do deps.get, compile

create database
  $ mix ecto.create

add migration
  $ mix ecto.gen.migration create_subscriptions

run migration
  $ mix ecto.migrate

add schema
  - create schema file under model/
  - add changesets & helpers

use schema
  - call schema helpers in endpoint







iex -S mix


{:ok, pid} = MyXQL.start_link(username: "root")

MyXQL.query!(pid, "CREATE DATABASE IF NOT EXISTS tenbew")

  %MyXQL.Result{
    columns: nil,
    connection_id: 87,
    last_insert_id: 0,
    num_rows: 1,
    num_warnings: 0,
    rows: nil
  }



{:ok, pid} = MyXQL.start_link(username: "root", database: "tenbew")

MyXQL.query!(pid, "CREATE TABLE subscriptions (id serial, msisdn text, status text, services text)")

  %MyXQL.Result{
    columns: nil,
    connection_id: 113,
    last_insert_id: 0,
    num_rows: 0,
    num_warnings: 0,
    rows: nil
  }


MyXQL.query!(pid, "INSERT INTO subscriptions VALUES (1, '0723456437', 'pending', 'none')")

  %MyXQL.Result{
    columns: nil,
    connection_id: 113,
    last_insert_id: 1,
    num_rows: 1,
    num_warnings: 0,
    rows: nil
  }  


MyXQL.query(pid, "SELECT * FROM subscriptions")

  {:ok,
   %MyXQL.Result{
     columns: ["id", "msisdn", "status", "services"],
     connection_id: 113,
     last_insert_id: nil,
     num_rows: 1,
     num_warnings: 0,
     rows: [[1, "0723456437", "pending", "none"]]
   }}






$ mix do deps.get, compile

$ mix ecto.drop

$ mix ecto.create

$ mix ecto.gen.migration create_subscriptions

$ mix ecto.migrate

{:ok, pid} = MyXQL.start_link(username: "root", database: "tenbew")
MyXQL.query!(pid, "INSERT INTO subscriptions VALUES (1, '0723456437', 'pending', 'none')")






{:ok, p} = Mariaex.start_link(username: "root", database: "tenbew")

Mariaex.query(p, "CREATE TABLE subscriptions (id serial, msisdn text, status text, services_subscribed text, date_subscribed date)")

Mariaex.query(p, "INSERT INTO subscriptions VALUES (1, '0723456437', 'pending', 'none', '01-24-2019')")


mix do deps.get, compile


query = Mariaex.prepare!(conn, "CREATE TABLE posts (id serial, title text)")
Mariaex.execute(conn, query, [])

Mariaex.query(pid, "INSERT INTO posts (title) VALUES ('my title')")



Subscriptions

This database consists of
MSISDN,
the status of subscription (pending, active, cancelled),
date of subscription, and
services subscribed


iex(1)> {:ok, p} = Mariaex.start_link(username: "ecto", database: "ecto_test")
{:ok, #PID<0.108.0>}

iex(2)> Mariaex.query(p, "CREATE TABLE test1 (id serial, title text)")
{:ok, %Mariaex.Result{columns: [], command: :create, num_rows: 0, rows: []}}

iex(3)> Mariaex.query(p, "INSERT INTO test1 VALUES(1, 'test')")
{:ok, %Mariaex.Result{columns: [], command: :insert, num_rows: 1, rows: []}}

iex(4)> Mariaex.query(p, "INSERT INTO test1 VALUES(2, 'test2')")
{:ok, %Mariaex.Result{columns: [], command: :insert, num_rows: 1, rows: []}}

iex(5)> Mariaex.query(p, "SELECT id, title FROM test1")
{:ok,
 %Mariaex.Result{columns: ["id", "title"], command: :select, num_rows: 2,
  rows: [[1, "test"], [2, "test2"]}}



  $ mix do deps.get, compile

  $ mix ecto.create

  $ mix ecto.gen.migration create_subscriptions

  $ mix ecto.migrate




Or if using MySQL:

  config :mariaex, :json_library, YourLibraryOfChoice

If changing the JSON library, remember to recompile the adapter afterwards by cleaning the current build:

  mix deps.clean --build postgrex




We are developing a subscriber management module for a content provider known as QQ from China. The way we have configured it is that they make their calls to their server and then we (Tenbew) generate the subsequent downstream logic. This document is only for the Tenbew-QQ link. I will generate a separate document for the downstream logic.




iex(1)> alias ApiExample.Repo
iex(2)> alias ApiExample.User
iex(3)> Repo.insert(%User{name: "Joe", email: "joe@domain.com", password: "secret", stooge: "moe"})
iex(4)> Repo.insert(%User{name: "Jane", email: "jane@domain.com", password: "donttell", stooge: "larry"})

You can then use Ecto functions to query the database.
iex(5)> Repo.all(User)
iex(6)> Repo.get(User, 2)




# lib/poison_encoder.ex
defimpl Poison.Encoder, for: Any do
  def encode(%{__struct__: _} = struct, options) do
    map = struct
          |> Map.from_struct
          |> sanitize_map
          |> Poison.Encoder.Map.encode(options)
  end

  defp sanitize_map(map) do
    Map.drop(map, [:__meta__, :__struct__])
  end
end
