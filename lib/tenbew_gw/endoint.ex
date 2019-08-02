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
          {:ok, value} -> value
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

  get "/api/v1/" do
    "/" |> color_info(:lightblue)
    return_welcome_response(conn)
  end

  get "/home" do
    "/home" |> color_info(:lightblue)
    return_welcome_response(conn)
  end

  get "/" do
    "/" |> color_info(:lightblue)
    conn
    |> put_resp_header("location", redirect_url())
    |> put_resp_content_type("text/html")
    |> send_resp(302, redirect_body())
  end

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
            "/addsub.php" -> {__MODULE__, :addsub, ["general"]}
            "/get_subscription" -> {__MODULE__, :get_subscription, ["general"]}
            "/doi/subscriptions" -> {__MODULE__, :doi_subscriptions, ["general"]}
            _ -> nil
          end

        "POST" ->
          case route do
            "/add_subscription" -> {__MODULE__, :add_subscription, ["general"]}
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
      |> send_resp(404, not_found_message())
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
  defp doi_api_url, do: Application.get_env(:tenbew_gw, :doi_api_url)

  def handle_errors(%{status: status} = conn, %{kind: _kind, reason: _reason, stack: _stack}),
    do: send_resp(conn, status, "Something went wrong")

  def render_error(%{status: status} = conn) do
    message = error_message(status)
    err_msg = Poison.encode!(%{error: message})
    "render_error/1, code: #{status}, message: #{inspect(message)}" |> color_info(:red)
    send_resp(conn, status, "#{err_msg}")
  end

  def error(conn, error, error_number \\ 403), do: send_resp(conn, error_number, error)


  # STEP 1 - Receive add subscriber request
  def valid_parameters(map) when is_map(map) do
    # The request will originate from the Cell C QQ portal for a new subscriber.
    # QQ will call addSub function with the MSISDN and other parameters that will determine the request routing
    keys = ~w(waspTID serviceID msisdn mn)

    Enum.all?(keys, fn x -> Map.get(map, x) != nil end)
  end
  def valid_parameters(_, _) , do: false

  # STEP 2 - Conduct basic MSISDN Validation
  def valid_msisdn_format(msisdn) do
    # The basic validation required here is to determine that the MSISDN is 11 digits long starting with 27, only numeric
    case msisdn do
      val when val in [nil, ""] -> false

      val when is_number(val) ->
        val = val |> Integer.to_string()
        case Integer.parse(val) do
          {_, ""} -> true
          _  -> false
        end
        |> Kernel.and( String.starts_with?(val, "27") and String.length(val) == 11 )

      val when is_binary(val) ->
        case Integer.parse(msisdn) do
          {_, ""} -> true
          _  -> false
        end
        |> Kernel.and(
          String.starts_with?(val, "27") and String.length(val) == 11
        )
    end
  rescue e ->
    "valid_msisdn_format/1 exception : #{inspect e}" |> color_info(:red)
    false
  end

  # STEP 3 - Check if the MSISDN is already Subscribed
  def valid_msisdn_existance(msisdn) do
    # This processes queries Tenbew database to see if the MSISDN is registered in the subscriber database and listed as either pending or active
    if Subscription.exists?(msisdn) do
      case Subscription.get_status(msisdn) do
        "pending" -> true
        "active" -> false
        _ -> false
      end
    else
      true
    end
  rescue e ->
    "valid_msisdn_existance/1 exception : #{inspect e}" |> color_info(:red)
    false
  end

  # STEP 4 - Call up Cell C DOI Service
  def call_cell_c(map) do
    # The DOI service (double opt in) is a legal requirement. It allows the subscriber to confirm that they have indeed made the decision to subscriber.
    # When this function is called, the subscriber is sent an SMS by Cell C to confirm the request.
    # If the MSISDN is valid, Cell C returns a message that the subscriber is pending.
    # Otherwise may reject the request because the subscriber is either not a Cell C subscriber or other reasons.
    # payload = %{
    #   "msisdn" => Map.get(map, "msisdn", ""),
    #   "waspTID" => Map.get(map, "waspTID", ""),
    #   "serviceID" => Map.get(map, "serviceID", ""),
    #   "mn" => Map.get(map, "mn", "")
    # } |> Jason.encode!
    # headers = [ {"Authorization", "Token token=PsmmvKBqQDOaWwEsPpOCYMsy"} ]
    headers = [{"Content-Type", "application/json"}]
    endpoint = doi_api_url() <> "/subscriptions"
    msisdn = Map.get(map, "msisdn", "")
    params = %{
      "subscription" => %{
        "msisdn" => msisdn,
        "state" => "active",
        "service" => "gateway",
        "reference" => "testing api",
        "message" => "gateway subscription"
      }
    } # |> Jason.encode!

    response =
      case request(endpoint, :post, headers, params, 30) do
        {200, body} -> body
        _ -> "error"
      end
    "RESPONSE : #{inspect(response)}" |> color_info(:green)

    if is_binary(response) do
      %{
        "code" => 500,
        "response" => nil,
        "payload" => params,
        "status" => "pending",
        "error" => "#{response}",
        "message" => "failed to call DOI API"
      }
    else
      %{
        "code" => 200,
        "error" => nil,
        "payload" => params,
        "status" => "active",
        "response" => Poison.decode(response),
        "message" => "successfully called DOI API"
      }
    end
  rescue e ->
    "call_cell_c/1 exception : #{inspect e}" |> color_info(:red)
  end

  # STEP 5 - Update Database, send code 200 to QQ
  def update_subscription_details(msisdn, response) do
    # The subscription database gets updated to say that the sub has paid for the day
    subscription = Subscription.get_by_msisdn(msisdn)
    status = response["status"] || "pending"

    if is_nil(subscription) do
      create_subscription(msisdn, status)
    else
      update_subscription_status(subscription, status)
    end
  rescue e ->
    "update_subscription_details/2 exception : #{inspect e}" |> color_info(:red)
  end

  def addsub(conn, opts) do
    # 1. Add Subscriber - This happens when a subscriber through QQ portal ask to subscribe for service(s).
                        # QQ portal calls Tenbew gateway for downstream processing
    map = req_query_params(conn)
    msisdn = Map.get(map, "msisdn", "")
    "POST /addsub :: msisdn: #{msisdn}" |> color_info(:lightblue)

    # Step 1
    unless valid_parameters(map) do
      raise ValidationError, message: "invalid params, missing details", status: 500
    end
    # Step 2
    unless valid_msisdn_format(msisdn) do
      raise ValidationError, message: "invalid msisdn, incorrect format", status: 501
    end
    # Step 3
    unless valid_msisdn_existance(msisdn) do
      raise ValidationError, message: "invalid msisdn, already subscribed", status: 502
    end
    # Step 4
    doi_response = call_cell_c(map)
    # unless doi_response["status"] == "pending" do
    #   raise ApiError, message: response["message"] || ""
    # end
    is_success =
      if (doi_response["code"] == 200 and is_nil(doi_response["error"])), do: true, else: false

    # Step 5
    if is_success do
      "Successfull response, updating subscriber" |> color_info(:lightblue)
      update_subscription_details(msisdn, doi_response)
    end

    status = if is_success, do: 200, else: doi_response["code"]

    message = if is_success, do: "subscribed successfully", else: doi_response["message"]

    r_json(~m(status message)s)
  rescue
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
      "Exception: #{inspect(e)}" |> color_info(:red)
      status = 500
      message = "error occured"
      r_json(~m(status message)s)
  end

  def doi_subscriptions(conn, _opts) do
    endpoint = "#{doi_api_url()}/subscriptions"
    headers = [{"Content-Type", "application/json"}]
    # {:ok, status, _, client_ref} = :hackney.request(:get, endpoint, headers, "", [])
    # {:ok, body} = :hackney.body(client_ref)
    # {:ok, api_response} = Poison.decode(body)
    response =
      case request(endpoint, :get, headers, "", 20) do
        {200, body} -> body
        _ -> "error"
      end
    "RESPONSE : #{inspect(response)}" |> color_info(:green)

    encoded_response =
      if is_binary(response) do
        %{error: "failed to call DOI API"}
      else
        Poison.encode!(response)
      end

    conn
    |> put_resp_content_type(@content_type)
    |> send_resp(200, encoded_response)
  end

  defp create_subscription(msisdn, status \\ "pending") do
    "create_subscription/1 :: #{inspect(msisdn)}" |> color_info(:yellow)
    attrs = %{msisdn: "#{msisdn}", status: status || "pending"}

    case Subscription.create_subscription(attrs) do
      {:ok, subscription} ->
        "Subscription created successfully: #{inspect(subscription)}" |> color_info(:green)

      {:error, %Ecto.Changeset{} = changeset} ->
        "Error creating subscription: #{inspect(changeset_errors(changeset))}" |> color_info(:red)

      {:error, error} ->
        "Error creating subscription: #{inspect(error)}" |> color_info(:red)

      _ -> "Error creating subscription" |> color_info(:red)
    end
  rescue e ->
    "create_subscription/1 exception: #{inspect e}" |> color_info(:red)
  end

  defp update_subscription_status(subscription, status) do
    "update_subscription_status/1 :: #{inspect(status)}" |> color_info(:yellow)

    {:ok, subscription} = Subscription.set_status(subscription, %{"status" => status})
  rescue
    e -> "update_subscription_status/2 exception: #{inspect e}" |> color_info(:red)
  end

  # Initial testing endpoints

  def get_subscription(conn, _opts) do
    "get_subscription/2" |> color_info(:lightblue)
    params = req_query_params(conn)
    response_message = %{
      type: "finding subscription",
      message: "searching DB for subscriber"
    }

    if params["msisdn"] do
      msisdn = Map.get(params, "msisdn", "")

      if Subscription.exists?(msisdn) do
        status = Subscription.get_status(msisdn)
        response_message = %{
          type: "retrieved subscription",
          message: "MSISDN #{msisdn} found, status is: #{status}"
        }
      else
        response_message = %{
          type: "no existing subscription",
          message: "MSISDN #{msisdn} not found"
        }
      end
    end

    encoded_response = Poison.encode!(response_message)

    conn
    |> put_resp_content_type(@content_type)
    |> send_resp(200, encoded_response)
  end

  def add_subscription(conn, _opts) do
    "add_subscription/2" |> color_info(:lightblue)
    map = req_body_map(conn)
    response_message = %{
      type: "creation started",
      message: "adding subscriber"
    }
    msisdn = Map.get(map, "msisdn", "")

    if msisdn == "" do
      response_message = %{
        type: "creation failed",
        message: "MSISDN is required"
      }
    else
      if Subscription.exists?(msisdn) do
        response_message = %{
          type: "creation stopped",
          message: "Subscription for MSISDN #{msisdn} already exists"
        }
      else
        status = map |> Map.get("status")
        create_subscription(msisdn, status)
        subscription = Subscription.get_by_msisdn(msisdn)
        response_message =
          if is_nil(subscription) do
            %{
              type: "creation failed",
              message: "Error subscribing MSISDN #{msisdn} in DB"
            }
          else
            %{
              type: "creation success",
              message: "Created subscription with MSISDN #{msisdn}, ref: #{subscription.id}"
            }
          end
      end
    end

    conn
    |> put_resp_content_type(@content_type)
    |> send_resp(200, Poison.encode!(response_message))
  end

  def bkp_addsub(conn, opts) do
    "POST /addsub" |> color_info(:lightblue)
    map = req_query_params(conn)
    msisdn = Map.get(map, "msisdn", "")
    valid? =
      if valid_parameters(map) do
        if valid_msisdn_format(msisdn) do
          if valid_msisdn_existance(msisdn) do
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

    if valid? do
      response = call_cell_c(map)
      if response["status"] == "pending" do
        update_subscription_details(msisdn, response)
        conn
        |> put_resp_content_type(@content_type)
        |> send_resp(200, response)
      else
        raise ApiError, message: response["error"]
      end
    else
      raise ValidationError, message: "invalid msisdn", status: 502
    end
  rescue
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
      "Exception: #{inspect(e)}" |> color_info(:red)
      status = 500
      message = "error occured"
      r_json(~m(status message)s)
  end

  # Helpers

  defp changeset_errors(changeset) do
    field_name = get_field_name(changeset)
    field_error = get_field_error(changeset)
    "#{field_name}: #{field_error}"
  end

  defp get_field_name(changeset) do
    changeset.errors
    |> List.first()
    |> elem(0)
    |> Atom.to_string()
  end

  defp get_field_error(changeset) do
    changeset.errors
    |> List.first()
    |> elem(1)
    |> elem(0)
  end

  defp not_found_message() do
    Poison.encode!(%{
      type: "error",
      message: "requested endpoint not available"
    })
  end

  defp return_welcome_response(conn) do
    message = "welcome to tenbew gateway"
    type = "default"
    r_json(~m(message type))
  end

  def error_message(code) do
    case code do
      500 -> "general error"
      501 -> "invalid MSISDN"
      502 -> "MSISDN Already Subscribed"
    end
  end

end
