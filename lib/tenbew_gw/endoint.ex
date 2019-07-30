defmodule ValidationError do
  @moduledoc false
  defexception [:message, :status]
end

defmodule AuthorizationError do
  @moduledoc false
  defexception [:message]
end

defmodule ApiError do
  @moduledoc false
  defexception [:message]
end



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
            "/add_subscription" -> {__MODULE__, :add_subscription, ["general"]}
            "/api/foo" -> {__MODULE__, :local_foo, nil}
            _ -> nil
          end

        "POST" ->
          case route do
            "/addsub" -> {__MODULE__, :addsub, ["general"]}
            "/subscribe" -> {__MODULE__, :subscribe, ["general"]}
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


  # def handle_errors(conn, status, message) do
  #   msg = Poison.encode!(%{error: "#{message}"})
  #   send_resp(conn, status, msg)
  # end

  def handle_errors(%{status: status} = conn, %{kind: _kind, reason: _reason, stack: _stack}),
    do: send_resp(conn, status, "Something went wrong")

  # def error(conn, error, error_number \\ 403), do: send_resp(conn, error_number, error)

  # def render_error(%{status: status} = conn, %{kind: _kind, reason: _reason, stack: _stack}) do
  #   message = error_message(status)
  #   err_msg = Poison.encode!(%{error: message})
  #   "render_error/1, code: #{status}, message: #{inspect(message)}" |> color_info(:red)
  #   send_resp(conn, status, "#{err_msg}")
  # end


  # STEP 1 - Receive add subscriber request
  def validate_parameters(map) when is_map(map) do
    # The request will originate from the Cell C QQ portal for a new subscriber. QQ will call addSub function with the MSISDN and other parameters that will determine the request routing
    keys = ~w(waspTID serviceID msisdn mn)

    Enum.all?(keys, fn x -> Map.get(map, x) != nil end)
  end

  def validate_parameters(_) , do: false
  # def validate_parameters(_, _) , do: false

  # STEP 2 - Conduct basic MSISDN Validation
  def validate_msisdn_format(msisdn) do
    # The basic validation required here is to determine that the MSISDN is 11 digits long starting with 27, only numeric
    true
  rescue e ->
    "validate_msisdn_format/1 exception : #{inspect e}" |> color_info(:red)
    false
  end


  # STEP 3 - Check if the MSISDN is already Subscribed
  def validate_msisdn_existance(msisdn) do
    # This processes queries Tenbew database to see if the MSISDN is registered in the subscriber database and listed as either pending or active
    true
  rescue e ->
    "validate_msisdn_existance/1 exception : #{inspect e}" |> color_info(:red)
    false
  end


  # STEP 4 - Call up Cell C DOI Service
  def call_cell_c(map) do
    # The DOI service (double opt in) is a legal requirement. It allows the subscriber to confirm that they have indeed made the decision to subscriber. When this function is called, the subscriber is sent an SMS by Cell C to confirm the request.
    # If the MSISDN is valid, Cell C returns a message that the subscriber is pending. Otherwise may reject the request because the subscriber is either not a Cell C subscriber or other reasons.


  rescue e ->
    "call_cell_c/1 exception : #{inspect e}" |> color_info(:red)
  end


  # STEP 5 - Update Database, send code 200 to QQ
  def update_subscription_details(map) do
    # The subscription database gets updated to say that the sub has paid for the day

  rescue e ->
    "update_subscription_details/1 exception : #{inspect e}" |> color_info(:red)
  end



  def addsub(conn, opts) do
    # 1. Add Subscriber - This happens when a subscriber through QQ portal ask to subscribe for service(s). QQ portal calls Tenbew gateway for downstream processing
    # if is_nil(opts), do: raise AuthorizationError, message: "Authorization error"
    "POST /addsub" |> color_info(:yellow)
    map = req_query_params(conn)

    valid? =
      if validate_parameters(map) do
        msisdn = Map.get(map, "msisdn", "")
        if validate_msisdn_format(msisdn), do: true, else: raise ValidationError, message: "invalid msisdn, incorrect format", status: 501
        if validate_msisdn_existance(msisdn), do: true, else: raise ValidationError, message: "invalid msisdn, already subscribed", status: 502
      else
        map = req_body_map(conn)

        if validate_parameters(map) do
          msisdn = map |> Map.get("msisdn")

          if validate_msisdn_format(msisdn) do
            if validate_msisdn_existance(msisdn) do
              true
            else
              raise ValidationError, message: "invalid msisdn, already subscribed", status: 502
            end
          else
            raise ValidationError, message: "invalid msisdn, incorrect format", status: 501
          end
        else
          raise ValidationError, message: "invalid params, missing details", status: 500
        end
      end

    if valid? do
      serialized_map = %{
        "msisdn" => Map.get(map, "msisdn", ""),
        "waspTID" => Map.get(map, "waspTID", ""),
        "serviceID" => Map.get(map, "serviceID", ""),
        "mn" => Map.get(map, "mn", "")
      } |> Jason.encode!

      response = call_cell_c(serialized_map)

      if response["status"] == "pending" do
        update_subscription_details(response)

        conn
        |> put_resp_content_type(@content_type)
        |> send_resp(200, response)
      else
        raise ApiError, message: response["error"]
      end
    else
      raise ValidationError, message: "invalid msisdn", status: 502
      # render_error(conn, 501)
    end

  rescue
    # e in AuthorizationError ->
    #   "Authorization Error: #{e.message}" |> color_info(:red)
    #   error(conn, e.message)
    e in ValidationError ->
      "Validation Error: #{e.message}" |> color_info(:red)
       status = e.status
       message = e.message
       r_json(~m(status message)s)
    e in ApiError ->
      "API Error: #{e.message}" |> color_info(:red)
      status = 501
      message = e.message
      r_json(~m(status message)s)
    e ->
      "Exception raised: #{inspect(e)}" |> color_info(:red)
      # render_error(conn, 500)
      status = 500
      message = "error occured"
      r_json(~m(status message)s)
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


  def error_message(code) do
    case code do
      500 -> "general error"
      501 -> "invalid MSISDN"
      502 -> "MSISDN Already Subscribed"
    end
  end

  defp error_message do
    Poison.encode!(%{
      response_type: "error",
      text: "requested endpoint not available"
    })
  end

  # def subscribe(conn, _opts) do
  #   "POST /subscribe" |> color_info(:yellow)
  #   map = req_body_map(conn)
  #   msisdn = Map.get(map, "msisdn", "")
  #   # response = call_qq_api(:create, msisdn)
  #
  #   conn
  #   |> put_resp_content_type(@content_type)
  #   |> send_resp(200, Poison.encode!(%{"error": "error"}))
  # end


end
