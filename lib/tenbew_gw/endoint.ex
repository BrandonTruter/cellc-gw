defmodule TenbewGw.Endpoint do
  use Plug.Router
  use Plug.Debugger
  use Plug.ErrorHandler
  import Plug.Conn
  import Util.Log
  import Util.WebRequest
  import ShortMaps

  alias TenbewGw.Router
  alias Plug.{Adapters.Cowboy2, HTML}
  alias TenbewGw.{Repo, Model.Subscription}

  require Logger

  plug(Plug.Logger, log: :debug)
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["application/json", "application/octet-stream"],
    json_decoder: Poison # Jason
  )

  plug(:dispatch)

  @content_type "application/json"

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(_opts) do
    with {:ok, [port: port] = config} <- config() do
      Logger.info("Starting server at http://localhost:#{port}/")
      Plug.Cowboy.http(__MODULE__, [], config)
    end
  end


  defmacro r_json(j) do
    quote do
      encoded =
        case Poison.encode(unquote(j)) do
          {:ok, value} ->
            value

          val ->
            "#{inspect(val)}" |> color_info(:yellow)
            "Problem encoding json" |> color_info(:lightred)
            %{} |> Poison.encode!()
        end

      status = 200

      conn
      |> var!()
      |> put_resp_content_type("application/json")
      |> send_resp(status, encoded)
    end
  end

  get "/" do
    "/" |> color_info(:lightblue)
    message = "welcome to gateway"
    response_type = "default"
    r_json(~m(message response_type))
  end

  get "/home" do
    "/home" |> color_info(:lightblue)
    text = "welcome to our gateway :)"
    response_type = "default"
    r_json(~m(text response_type))
  end

  # forward("/home", to: Router)

  match _ do
    rp = conn.request_path
    base_api = Application.get_env(:tenbew_gw, :base_api)

    route =
      case String.split(rp, base_api) do
        [val] -> val
        [_, val] -> val
        _ -> ""
      end

    route_match =
      case conn.method do
        "GET" ->
          case route do
            "/get_subscription" -> {__MODULE__, :get_subscription, ["general"]}
            "/api/foo" -> {__MODULE__, :local_foo, nil}
            _ -> nil
          end

        "POST" ->
          case route do
            # "/add_subscriber" -> {__MODULE__, :add_subscriber, nil}
            "/add_subscriber" -> {__MODULE__, :add_subscriber, ["general"]}
            _ -> nil
          end

        _ ->
          nil
      end

    if is_nil(route_match) do
      "NOT FOUND" |> color_info(:red)
      # conn
      # |> put_resp_header("location", redirect_url())
      # |> put_resp_content_type("text/html")
      # |> send_resp(302, redirect_body())
      conn
      |> put_resp_content_type(@content_type)
      |> send_resp(404, error_message())
    else
      {module, func, auth} = route_match

      apply(module, func, [conn, nil])
    end
  end

  def local_foo(conn, _opts) do
    ~m(var1 var2) = req_query_params(conn)
    r_json(~m(var1 var2))
  rescue
    e ->
      "#{inspect(e)}" |> color_info(:red)
      error(conn, "must use var1 and var2")
  end


  def get_subscription(conn, _opts) do
    "get_subscription/2" |> color_info(:lightblue)
    params = req_query_params(conn)

    if params["msisdn"] do
      msisdn = Map.get(params, "msisdn", "")

      if Subscription.exists?(msisdn) do
        status = Subscription.get_status(msisdn)
        response_message = %{
          response_type: "subscription retrieved",
          text: "MSISDN #{msisdn} found, status is: #{status}"
        }
      else
        response_message = %{
          response_type: "subscription created", text: "MSISDN #{msisdn} not found"
        }
        IO.puts "No Subscription found, so creating it"
        create_subscription(msisdn)
      end

      encoded = Poison.encode!(response_message)
    else
      encoded = Poison.encode!(%{
        response_type: "subscription",
        text: "no params to search"
      })
    end

    conn
    |> put_resp_content_type(@content_type)
    |> send_resp(200, encoded)
  end

  defp create_subscription(msisdn) do
    "create_subscription/1 :: #{inspect(msisdn)}" |> color_info(:yellow)
    attrs = %{ msisdn: "#{msisdn}", status: "pending" }

    case Subscription.create_subscription(attrs) do
      {:ok, subscription} ->
        "Subscription created successfully: #{inspect(subscription)}" |> color_info(:green)

      {:error, error} ->
        "Error creating subscription: #{inspect(error)}" |> color_info(:red)

      _ -> "Error creating subscription" |> color_info(:red)
    end
  rescue e ->
    "create_subscription/1 exception: #{inspect e}" |> color_info(:red)
  end

  def add_subscriber(conn, _opts) do
    "add_subscriber/2" |> color_info(:yellow)
    map = req_body_map(conn)
    response_message = %{
      response_type: "creation started",
      text: "adding subscriber"
    }
    msisdn = Map.get(map, "msisdn", "")

    if msisdn == "" do
      response_message = %{
        response_type: "creation failed", text: "MSISDN is required"
      }
    else
      if Subscription.exists?(msisdn) do
        response_message = %{
          response_type: "creation stopped",
          text: "Subscription for MSISDN #{msisdn} already exists"
        }
      else
        create_subscription(msisdn)
        subscription = Subscription.get_by_msisdn(msisdn)
        response_message =
          if is_nil(subscription) do
            %{
              response_type: "creation failed",
              text: "Error subscribing MSISDN #{msisdn} in DB"
            }
          else
            %{
              response_type: "creation success",
              text: "Created subscription with MSISDN #{msisdn}, ref: #{subscription.id}"
            }
          end
      end
    end

    conn
    |> put_resp_content_type(@content_type)
    |> send_resp(200, Poison.encode!(response_message))
  end

  def req_body_map(conn) do
    case Plug.Conn.read_body(conn, length: 1_000_000) do
      {:ok, value, c} ->
        if value == "" do
          "value empty from read_body" |> color_info(:yellow)
          c.body_params
          # %{}
        else
          case Poison.decode(value) do
            {:ok, val} ->
              val

            value ->
              "Poison decode is #{inspect(value)}" |> color_info(:yellow)
              %{}
          end
        end

      _ ->
        %{}
    end
  end

  def req_query_params(conn) do
    cn = Plug.Conn.fetch_query_params(conn)
    cn.params
  end

  defp redirect_body do
    ~S(<html><body>You are being <a href=")
    |> Kernel.<>(HTML.html_escape(redirect_url()))
    |> Kernel.<>(~S(">redirected</a>.</body></html>))
  end

  defp config, do: Application.fetch_env(:tenbew_gw, __MODULE__)
  defp redirect_url, do: Application.get_env(:tenbew_gw, :redirect_url)

  def handle_errors(%{status: status} = conn, %{kind: _kind, reason: _reason, stack: _stack}),
    do: send_resp(conn, status, "Something went wrong")

  def error(conn, error, error_number \\ 403) do
    send_resp(conn, error_number, error)
  end

  defp error_message do
    Poison.encode!(%{
      response_type: "error",
      text: "requested endpoint not available"
    })
  end

  # def function_name do
  #   |> Map.merge(pp_credentials())
  #   |> URI.encode_query()
  #
  #   base_url = get_from_env_or_config(:pp_base_url)
  #   base_url <> "v1/checkouts/#{checkout_id}/#{value}?" <> cred_to_querystring()
  # end
  #
  # def pp_credentials() do
  #   %{
  #     "authentication.entityId": get_from_env_or_config(:pp_entity_id),
  #     "authentication.password": get_from_env_or_config(:pp_password),
  #     "authentication.userId": get_from_env_or_config(:pp_user_id)
  #   }
  # end
  #
  # def cred_to_querystring() do
  #   #map = pp_credentials() |> URI.encode_query
  #   pp_credentials() |> URI.encode_query
  #   #Enum.map(Map.keys(map), fn x -> Atom.to_string(x) <> "=#{Map.get(map, x)}" end) |> Enum.join("&")
  # end


  # def call_qq_api do
  #
  #
  #   response =
  #     case WebRequest.request(url_by_type(type, checkout_id), method_by_type(type), headers_by_type(type), body, timeout) do
  #       {200, response} -> response
  #       val ->
  #         emsg = "Response from peach (bad) was #{inspect val}"
  #         emsg |> color_info(:red)
  #         generate_ticket(:peach_request_error, emsg, map)
  #         raise PaymentError, message: {checkout_id, "Payment Processor response was invalid"}
  #     end
  #
  # end

  # def call_rain_pg_old(checkout, map) do
  #   timeout = 60
  #   url = "http://localhost:9999/fake"  # Endpoint Url of rain_pg, use a mock in the meantime
  #   method = "POST"
  #   headers = []
  #   details = map["details"]
  #   body =
  #     %{
  #       id_number: details["user_id_no"],
  #       bank_acc_no: details["bank_acc_no"],
  #       branch_code: details["branch_code"],
  #       account_holder: details["account_holder"],
  #       request_reference: Ecto.UUID.generate()
  #     }
  #   DebitOrderCheckout.set_history_message(checkout, "Pending Validation")
  #   {what, response} =
  #     case WebRequest.request(url, method, headers, body, timeout) do
  #       {200, response} -> {:ok, response}
  #       {status, response} ->
  #         emsg = "Response from rain_pg (bad).  Status: #{status}.  Message: #{inspect response}"
  #         emsg |> color_info(:red)
  #         response =
  #           case response do
  #             "request timeout" -> "No response from RAIN PG"
  #             _ -> response
  #           end
  #         {:bad, "invalid - #{response}"}
  #       _val ->
  #         {:bad, "invalid – No response from RAIN PG"}
  #     end
  #   message = "validated"
  #   if what == :ok do
  #     m =
  #       case response.status do
  #         "validated" -> message
  #         _ -> response.message
  #       end
  #     update_request_and_response_at_debit_order_checkout(checkout, body, response, m)
  #   else
  #     update_request_and_response_at_debit_order_checkout(checkout, body, %{}, response)
  #   end
  #   :ok
  # rescue
  #   e -> "call_rain_pg/2 error : #{inspect e}" |> color_info(:red)
  # end

end
