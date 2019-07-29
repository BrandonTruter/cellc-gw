defmodule TenbewGw.Endpoint do
  use Plug.Router
  use Plug.Debugger
  use Plug.ErrorHandler
  import Plug.Conn
  import Util.Log

  alias TenbewGw.Router
  alias Plug.{Adapters.Cowboy2, HTML}
  alias TenbewGw.{Repo, Model.Subscription}

  require Logger

  plug(Plug.Logger, log: :debug)
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["application/json"],
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

  forward("/home", to: Router)

  # match _ do
  #   conn
  #   |> put_resp_header("location", redirect_url())
  #   |> put_resp_content_type("text/html")
  #   |> send_resp(302, redirect_body())
  # end

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
      conn
      |> put_resp_content_type(@content_type)
      |> send_resp(404, error_message())
      # |> send_resp(404, "NOT FOUND")
    else
      {module, func, auth} = route_match

      apply(module, func, [conn, nil])
    end
  end

  def get_subscription(conn, _opts) do
    "get_subscription/2" |> color_info(:yellow)
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
      {:ok, value, conn} -> conn.body_params
      _ -> %{}
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

  defp error_message do
    Poison.encode!(%{
      response_type: "error",
      text: "requested endpoint not available"
    })
  end

end
