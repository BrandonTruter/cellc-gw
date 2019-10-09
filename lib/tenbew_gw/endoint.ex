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

  alias TenbewGw.Repo
  alias TenbewGw.Router
  alias Plug.{Adapters.Cowboy2, HTML}
  alias TenbewGw.Model.{Payment, Subscription}

  require Logger

  plug(:match)
  plug(Plug.Logger, log: :info)
  plug(Plug.RequestId)
  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["application/json", "application/octet-stream"],
    json_decoder: Poison # Jason
  )
  plug(:dispatch)

  @content_type "application/json"

  @retries_schedule [6,10,14,18,22]

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

  get "/home" do
    "/home" |> color_info(:lightblue)
    return_welcome_response(conn)
  end

  get "/api/v1/" do
    "/api/v1/" |> color_info(:lightblue)
    status  = 200
    message = "specify an API endpoint"
    r_json(~m(status message))
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
            "/AddSub" -> {__MODULE__, :add_sub, ["general"]}
            "/addsub.php" -> {__MODULE__, :add_sub, ["general"]}
            "/ChargeSub" -> {__MODULE__, :charge_sub, ["general"]}
            "/CancelSub" -> {__MODULE__, :cancel_sub, ["general"]}

            "/get_payment" -> {__MODULE__, :get_payment, ["general"]}
            "/get_subscription" -> {__MODULE__, :get_subscription, ["general"]}

            "/doi/subscriptions" -> {__MODULE__, :doi_subscriptions, ["general"]}
            _ -> nil
          end

        "POST" ->
          case route do
            "/add_subscription" -> {__MODULE__, :add_subscription, ["general"]}
            "/add_payment" -> {__MODULE__, :add_payment, ["general"]}

            "/callback_url" -> {__MODULE__, :update_sub_status, ["general"]}
            "/update_sub_status" -> {__MODULE__, :update_sub_status, ["general"]}

            "/cellc/add" -> {__MODULE__, :cellc_add, ["general"]}
            "/cellc/charge" -> {__MODULE__, :cellc_charge, ["general"]}
            "/cellc/cancel" -> {__MODULE__, :cellc_cancel, ["general"]}
            "/cellc/notify" -> {__MODULE__, :cellc_notify, ["general"]}
            _ -> nil
          end

        _ ->
          nil
      end

    if is_nil(route_match) do
      "NOT FOUND" |> color_info(:red)

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

  defp doi_api_url, do: Application.get_env(:tenbew_gw, :doi_api_url)

  defp redirect_url, do: Application.get_env(:tenbew_gw, :redirect_url)

  def error(conn, error, error_number \\ 403), do: send_resp(conn, error_number, error)

  def handle_errors(%{status: status} = conn, %{kind: _kind, reason: _reason, stack: _stack}),
    do: send_resp(conn, status, "Something went wrong")

  def render_error(%{status: status} = conn) do
    message = error_message(status)
    err_msg = Poison.encode!(%{error: message})
    "render_error/1, code: #{status}, message: #{inspect(message)}" |> color_info(:red)
    send_resp(conn, status, "#{err_msg}")
  end

  # STEP 1 - Receive add subscriber request
  def valid_parameters(map) when is_map(map) do
    "valid_parameters/1" |> color_info(:yellow)
    # The request will originate from the Cell C QQ portal for a new subscriber.
    keys = ~w(waspTID serviceID msisdn mn)

    Enum.all?(keys, fn x -> Map.get(map, x) != nil end)
  end
  def valid_parameters(_, _) , do: false

  # STEP 2 - Conduct basic MSISDN Validation
  def valid_msisdn_format(msisdn) do
    "valid_msisdn_format/1" |> color_info(:yellow)
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
  def valid_msisdn_existance(msisdn, status) do
    "valid_msisdn_existance/2" |> color_info(:yellow)
    # This processes queries Tenbew database to see if the MSISDN is registered in the subscriber database and listed as either pending or active
    if Subscription.exists?(msisdn) do
      case Subscription.get_status(msisdn) do
        str when str == status -> true
        _ -> false
      end
    else
      true
    end
  rescue e ->
    "valid_msisdn_existance/2 exception : #{inspect e}" |> color_info(:red)
    false
  end
  def valid_msisdn_existance(msisdn) do
    "valid_msisdn_existance/1" |> color_info(:yellow)
    if Subscription.exists?(msisdn) do
      case Subscription.get_status(msisdn) do
        # str when str in ["pending", "active"] -> true
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

  def validate_daily_payment(msisdn) do
    "validate_daily_payment/1" |> color_info(:yellow)
    # This process checks the database to ensure that the subscriber does not get charged twice.
    # This could potentially be the case when a subsequent retry of a failed charge shows that the subscriber has already been charged but QQ has not been updated
    if Payment.exists?(msisdn) do
      subscriber = Subscription.get_by_msisdn(msisdn) # |> Repo.preload([:payments])
      if not is_nil(subscriber) do
        # Payment.is_paid(subscription_id)
        payment = Payment.last_payment_by_subscriber(subscriber.id)
        if not is_nil(payment) do
          if payment.paid == true do
            difference = Date.diff(payment.updated_at, NaiveDateTime.utc_now) |> abs
            difference == 0
          else
            false
          end
        else
          false
        end
      else
        false
      end
    else
      false
    end
    # false
  rescue e ->
    "validate_daily_payment/1 exception: #{inspect e}" |> color_info(:red)
  end

  # STEP 4 - Call up Cell C DOI Service
  def call_cell_c(endpoint, map) do
    # TODO Needs work
    "call_cell_c/2" |> color_info(:yellow)
    # The DOI service (double opt in) is a legal requirement.
    # It allows the subscriber to confirm that they have indeed made the decision to subscriber.
    # When this function is called, the subscriber is sent an SMS by Cell C to confirm the request.
    # If the MSISDN is valid, Cell C returns a message that the subscriber is pending.
    # Otherwise may reject the request because the subscriber is either not a Cell C subscriber or other reasons.
    method = :post
    msisdn = Map.get(map, "msisdn", "")
    params = %{ "msisdn" => msisdn }
    payload = Poison.encode!(params)
    base_url = doi_api_url() <> "/" <> endpoint
    headers = [{"Content-Type", "application/json"}]

    unless endpoint in ["add_sub", "charge_sub", "cancel_sub", "notify_sub"] do
      raise ApiError, message: "invalid endpoint, #{endpoint} not support", status: 501
    end

    response =
      case request(base_url, method, headers, payload, 30) do
        {200, response} -> response
        {st, error} ->
          if error == "undefined error" do
            "code: #{st}, response: DOI connection error"
          else
            "code: #{st}, response: #{error}"
          end
        {:error, :econnrefused} -> "connection error: econnrefused"
        {:econnrefused, err} -> "connection error: #{inspect(err)}"
        _ -> "general error calling DOI API with payload: #{payload}"
      end

    if is_nil(response), do: raise ApiError, message: "invalid DOI response", status: 501

    if is_binary(response) do
      message = "#{endpoint} request failed, #{inspect(response)}"
      message |> color_info(:red)
      %{
        "code" => 500,
        "data" => nil,
        "response" => nil,
        "payload" => params,
        "status" => "pending",
        "message" => "#{message}",
        "error" => %{error: response}
      }
    else
      message = "#{endpoint} processed successfully, #{inspect(response)}"
      "#{message}" |> color_info(:green)
      msg = stringify_message(endpoint)
      service_id = response["service_id"]
      returned_data = %{
        status: "active",
        service_id: service_id
      }
      response_message = if endpoint == "cancel_sub" do
                            "cancelled successfully"
                          else
                            if is_nil(service_id), do: msg , else: "#{msg}, serviceID: #{service_id}"
                          end
      %{
        "code" => 200,
        "error" => nil,
        "status" => "active",
        "data" => returned_data,
        "message" => "#{message}",
        "response" => %{success: response_message}
      }
    end
  rescue
    e in ApiError ->
      "call_cell_c/2 :: ApiError Exception : #{inspect e.message}" |> color_info(:red)
      %{
        "code" => 500,
        "data" => nil,
        "response" => nil,
        "payload" => map,
        "status" => "pending",
        "message" => "ApiError",
        "error" => %{error: "#{inspect e.message}"}
      }
    e ->
      "call_cell_c/2 :: exception : #{inspect e}" |> color_info(:red)
      %{
        "code" => 500,
        "data" => nil,
        "response" => nil,
        "payload" => map,
        "status" => "pending",
        "message" => "Exception Raised",
        "error" => %{error: "#{inspect e.message}"}
      }
  end

  defp stringify_message(endpoint) do
    case endpoint do
      "add_sub" -> "subscribed"
      "charge_sub" -> "charged"
      "notify_sub" -> "notified"
      _ -> "processed"
    end
  end


  def charge_retries(msisdn, data) do
    @retries_schedule
    |> Enum.map(fn x -> x * 3_600 * 1_000 end)
    |> Enum.each(fn x -> :timer.apply_after(__MODULE__, :charge_retry, [msisdn, data]) end)
  end

  def charge_retry(msisdn, data) do
    func = "charge_retry/2 ::"
    "#{func} msisdn: #{inspect(msisdn)}, data: #{inspect(data)}" |> color_info(:lightblue)

    if validate_daily_payment(msisdn) do
      "#{func} MSISDN already charged for the day" |> color_info(:yellow)
    else
      response = call_cell_c("charge_sub", data)

      if response["code"] == 200 do
        create_payment_details(msisdn)
        update_subscription_details(msisdn, response["data"])
        "#{func} MSISDN charged, DB updated" |> color_info(:green)
      end
    end
  end


  def add_sub(conn, opts) do
    map = req_query_params(conn)
    msisdn = Map.get(map, "msisdn", "")
    "GET /AddSub :: msisdn: #{msisdn}" |> color_info(:lightblue)

    # 1.Receive add subscriber request
    unless valid_parameters(map) do
      raise ValidationError, message: "invalid params, missing details", status: 500
    end

    # 2. Conduct basic MSISDN Validation
    unless valid_msisdn_format(msisdn) do
      raise ValidationError, message: "invalid msisdn, incorrect format", status: 501
    end

    # 3. Check if the MSISDN is already Subscribed
    unless valid_msisdn_existance(msisdn, "pending") do
      raise ValidationError, message: "invalid msisdn, already subscribed", status: 502
    end

    # 4. Call up Cell C DOI Service
    response = call_cell_c("add_sub", map)

    if response["code"] == 200 do
      # 5. Update Database, send code 200 to QQ
      update_subscription_details(msisdn, response["data"])
      status = 200
      message = response["response"]
      r_json(~m(status message)s)
    else
      status = response["code"]
      message = response["error"]
      r_json(~m(status message)s)
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
      # message = "error occured"
      message = "exception raised"
      r_json(~m(status message)s)
  end

  def charge_sub(conn, opts) do
    map = req_query_params(conn)
    msisdn = Map.get(map, "msisdn", "")
    "GET /ChargeSub :: msisdn: #{msisdn}" |> color_info(:lightblue)

    # 1.Receive Charge subscriber request
    if valid_parameters(map) do
      # 2. Conduct basic MSISDN Validation
      if validate_format(msisdn) do
        # 3. Is MSISDN subscribed with active status
        if validate_presence(msisdn, "active") do
          # 7. Is MSISDN already charged for the day?
          if validate_daily_payment(msisdn) do
            status = 200
            message = "already charged"
            r_json(~m(status message)s)
          else
            # 4. Call up Cell C Charge Service
            response = call_cell_c("charge_sub", map)
            # 5. Update Database, send code 200 to QQ
            if response["code"] == 200 do
              create_payment_details(msisdn)
              update_subscription_details(msisdn, response["data"])

              status  = 200
              message = response["response"]
              r_json(~m(status message)s)
            else
              # TODO - retry every 4 hours
              pid = spawn_link(__MODULE__,  :charge_retries , [msisdn, map])
              "Spawning #{inspect pid} calling charge_retries" |> color_info(:yellow)

              status = 504
              message = response["error"]
              r_json(~m(status message)s)
            end
          end
        else
          # 6. Initiate the Cell C DOI Process
          if valid_msisdn_status(msisdn, "cancelled") do
            # additional validation step requested by Kibata on Flock
            raise ValidationError, message: "invalid msisdn, subscription is cancelled", status: 503
          else
            if Subscription.exists?(msisdn) do
              response = call_cell_c("notify_sub", map)
              status   = 503
              message  =
                if response["code"] == 200, do: response["response"], else: "subscriber notified"

              r_json(~m(status message)s)
            else
              raise ValidationError, message: "invalid msisdn, MSISDN not subscribed", status: 503
              # raise ValidationError, message: "invalid msisdn, subscriber does not exist", status: 502
            end
          end
        end
      else
        raise ValidationError, message: "invalid msisdn, incorrect format", status: 501
      end
    else
      raise ValidationError, message: "invalid params, missing details", status: 500
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

  def cancel_sub(conn, opts) do
    map = req_query_params(conn)
    msisdn = Map.get(map, "msisdn", "")
    "GET /CancelSub :: msisdn: #{msisdn}" |> color_info(:lightblue)

    is_valid? =
      if valid_parameters(map) do
        if valid_msisdn_format(msisdn), do: true, else: raise ValidationError, message: "invalid msisdn, incorrect format", status: 501
        if valid_msisdn_presence(msisdn), do: true, else: raise ValidationError, message: "invalid msisdn, not subscribed", status: 502
        if valid_msisdn_status(msisdn, "active"), do: true, else: raise ValidationError, message: "invalid msisdn, subscription not active", status: 502
      else
        false
      end

    response = call_cell_c("cancel_sub", map)
    status = response["code"]
    is_success? =
      if (is_valid? == true and status == 200), do: true, else: false

    if is_success? do
      subscriber = Subscription.get_by_msisdn(msisdn)

      case update_subscription_status(subscriber, "cancelled") do
        {:ok, subscription} -> "subscription status saved" |> color_info(:green)

        {:error, %Ecto.Changeset{} = cs} ->
          "Error updating status: #{inspect(changeset_errors(cs))}" |> color_info(:red)
      end
    end

    message =
      case is_success? do
        true -> response["response"]
        false -> response["error"]
        _ -> "cancellation failed"
      end

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

  # STEP 5 - Update Database, send code 200 to QQ

  def update_subscription_details(msisdn, data) do
    subscription = Subscription.get_by_msisdn(msisdn)

    if is_nil(subscription) do
      create_subscription(msisdn, data)
    else
      # TODO: update this to append any existing services
      services = data[:service_id] || subscription.services
      status = data[:status] || subscription.status
      update_attrs = %{
        msisdn: msisdn,
        status: status,
        validated: true,
        services: services
      }
      update_subscription(subscription, update_attrs)
    end
  rescue e ->
    "update_subscription_details/2 exception : #{inspect e}" |> color_info(:red)
  end

  def create_payment_details(msisdn) do
    subscription = Subscription.get_by_msisdn(msisdn)

    unless is_nil(subscription) do
      payment_date = NaiveDateTime.utc_now  #|| subscription.inserted_at |> NaiveDateTime.from_iso8601!()
      qq_charges = Application.get_env(:tenbew_gw, :charges)
      service = qq_charges[:code] || subscription.services
      charge = qq_charges[:value]
      amount =
        case charge do
          v when is_nil(v) -> 0
          v when is_integer(v) -> v
          v when is_binary(v) -> String.to_integer(v)
        end
      attrs = %{
        paid: true,
        msisdn: msisdn,
        amount: amount,
        status: "paid",
        service_type: service,
        paid_at: payment_date,
        subscription_id: subscription.id
      }
      case Payment.create_payment(attrs) do
        {:ok, payment} ->
          "Payment Success: #{inspect(payment)}" |> color_info(:green)

        {:error, %Ecto.Changeset{} = changeset} ->
          "Payment Error: #{changeset_errors(changeset)}" |> color_info(:red)

        _ -> "Payment Exception with attrs: #{inspect(attrs)}" |> color_info(:red)
      end
    end
    rescue e -> "create_payment_details/2 exception: #{inspect e}" |> color_info(:red)
  end

  defp create_subscription(msisdn, data \\ nil) do
    "create_subscription/2 :: #{inspect(msisdn)}" |> color_info(:yellow)
    services = if is_nil(data), do: "00", else: data[:service_id] || "00"
    status = if is_nil(data), do: "pending", else: data[:status] || "pending"
    attrs = %{
      msisdn: msisdn,
      status: status,
      validated: true,
      services: services
    }

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

  defp update_subscription(subscription, attrs) do
    "update_subscription/2 :: #{inspect(attrs)}" |> color_info(:yellow)

    if not is_nil(subscription) do
      case Subscription.update_subscription(subscription, attrs) do
        {:ok, subscription} ->
          "Subscription updated successfully: #{inspect(subscription)}" |> color_info(:green)

        {:error, %Ecto.Changeset{} = changeset} -> errors = changeset_errors(changeset)
          "Error updating subscription: #{inspect(errors)}" |> color_info(:red)

        {:error, error} ->
          "Error updating subscription: #{inspect(error)}" |> color_info(:red)

        _ -> "Error updating subscription" |> color_info(:red)
      end
    else
      "Error updating subscription: subscription not found" |> color_info(:red)
    end
  rescue e ->
    "update_subscription/2 exception: #{inspect e}" |> color_info(:red)
  end

  defp update_subscription_status(subscription, status) do
    "update_subscription_status/2 :: #{inspect(status)}" |> color_info(:yellow)

    {:ok, subscription} = Subscription.set_status(subscription, %{"status" => status})
  rescue
    e -> "update_subscription_status/2 exception: #{inspect e}" |> color_info(:red)
  end

  def update_sub_status(conn, _opts) do
    map = req_body_map(conn)
    status = map |> Map.get("status")
    msisdn = Map.get(map, "msisdn", "")
    "update_sub_status/2" |> color_info(:lightblue)
    subscription = update_status(msisdn, status)

    r_json(~m(subscription)s)
  rescue e ->
    "update_sub_status/2 exception : #{inspect e}" |> color_info(:red)
  end

  defp update_status(msisdn, status) do
    if not empty?(msisdn) do
      if not empty?(status) do
        if Subscription.exists?(msisdn) do
          subscription = Subscription.get_by_msisdn(msisdn)
          unless is_nil(subscription) do
            unless subscription.status == status do
              case update_subscription_status(subscription, status) do
                {:ok, subscription} ->
                  "Updated status from: #{status}, to: #{subscription.status}" |> color_info(:green)
                  %{success: formatted_subscriber(subscription)}
                {:error, error} ->
                  "Subscription status update failed: #{inspect(error)}" |> color_info(:red)
                  %{error: error}
              end
            else
              %{error: "subscription status is already #{status}"}
            end
          else
            %{error: "subscription not found"}
          end
        else
          %{error: "MSISDN not found"}
        end
      else
        %{error: "status required"}
      end
    else
      %{error: "MSISDN required"}
    end
  rescue e ->
    "update_status/2 exception : #{inspect e}" |> color_info(:red)
  end

  def add_subscription(conn, _opts) do
    map = req_body_map(conn)
    status = map |> Map.get("status")
    msisdn = Map.get(map, "msisdn", "")
    "add_subscription/2" |> color_info(:lightblue)

    subscription =
      if empty?(msisdn) do
        %{error: "MSISDN required"}
      else
        if Subscription.exists?(msisdn) do
          %{error: "Subscription already exists"}
        else
          attrs = %{
            msisdn: msisdn,
            services: "testing",
            status: status || "pending"
          }
          case Subscription.create_subscription(attrs) do
            {:ok, subscription} ->
              "Subscription created successfully: #{inspect(subscription)}" |> color_info(:green)
              %{success: formatted_subscriber(subscription)}

            {:error, %Ecto.Changeset{} = changeset} ->
              errors = changeset_errors(changeset)
              "Subscription Error: #{inspect(errors)}" |> color_info(:red)
              %{error: errors}

            {:error, error} ->
              "Subscription Error: #{inspect(error)}" |> color_info(:red)
              %{error: error}

            _ -> %{error: "failed to create subscription"}
          end
        end
      end

    r_json(~m(subscription))
  rescue e ->
    "add_subscription/2 exception: #{inspect e}" |> color_info(:red)
  end

  def add_payment(conn, _opts) do
    map = req_body_map(conn)
    msisdn = Map.get(map, "msisdn", "")
    "add_payment/2" |> color_info(:lightblue)

    payment =
      if empty?(msisdn) do
        %{error: "msisdn is required"}
      else
        if Subscription.exists?(msisdn) do
          subscriber = Subscription.get_by_msisdn(msisdn)
          status = Map.get(map, "status", "paying")
          amount = Map.get(map, "amount", 0)
          attrs = %{
            msisdn: msisdn,
            amount: amount,
            status: status,
            service_type: "tester",
            subscription_id: subscriber.id
          }
          case Payment.create_payment(attrs) do
            {:ok, payment} ->
              "Payment Success: #{inspect(payment)}" |> color_info(:green)
              %{success: formatted_payment(payment)}

            {:error, %Ecto.Changeset{} = changeset} ->
              errors = inspect(changeset_errors(changeset))
              "Payment Error: #{errors}" |> color_info(:red)
              %{error: errors}

            {:error, error} ->
              "Payment Error: #{inspect(error)}" |> color_info(:red)
              %{error: "#{inspect(error)}"}

            _ ->
              "Error creating payment" |> color_info(:red)
              %{error: "failed to create payment"}
          end
        else
          %{error: "no subscriber found"}
        end
      end

    r_json(~m(payment))
  rescue e ->
    "add_payment/2 exception: #{inspect e}" |> color_info(:red)
  end

  def get_subscription(conn, _opts) do
    params = req_query_params(conn)
    msisdn = Map.get(params, "msisdn", "")
    "get_subscription/2 :: params: #{inspect(params)}" |> color_info(:lightblue)

    subscription =
      if empty?(msisdn) do
        %{error: "MSISDN required"}
      else
        if Subscription.exists?(msisdn) do
          status = Subscription.get_status(msisdn)
          # %{success: formatted_subscriber(subscription)}
          %{success: "MSISDN #{msisdn} found, status is: #{status}"}
        else
          %{error: "MSISDN #{msisdn} not found"}
        end
      end

    r_json(~m(subscription))
  rescue e ->
    "get_subscription/2 exception: #{inspect e}" |> color_info(:red)
  end

  def get_payment(conn, _opts) do
    params = req_query_params(conn)
    "get_payment/2 :: params: #{inspect(params)}" |> color_info(:lightblue)

    payment =
      if params["id"] do
        Payment.get_payment(params["id"])
      else
        if params["msisdn"] do
          Payment.get_payment_by_msisdn(params["msisdn"]) # || Subscription.get_payments_by_msisdn(params["msisdn"])
        else
          ""
        end
      end # || "none"

    payment =
      if empty?(payment) do
        %{error: "no payment found"}
      else
        %{success: formatted_payment(payment)}
      end

    r_json(~m(payment))
  rescue e ->
    "get_payment/2 exception: #{inspect e}" |> color_info(:red)
  end

  # refactored validations

  def validate_format(msisdn) do
    msisdn = if is_number(msisdn), do: Integer.to_string(msisdn), else: "#{msisdn}"
    case msisdn do
      val when val in [nil, ""] -> false
      val when is_binary(val) ->
        case Integer.parse(msisdn) do
          {_, ""} -> true
          _  -> false
        end
        |> Kernel.and( String.starts_with?(val, "27") and String.length(val) == 11 )
    end
  rescue
    e -> false
  end

  def validate_presence(msisdn, status) do
    if Subscription.exists?(msisdn) do
      case Subscription.get_status(msisdn) do
        str when str == status -> true
        _ -> false
      end
    else
      true
    end
  rescue e ->
    false
  end

  def validate_presence(msisdn) do
    if Subscription.exists?(msisdn) do
      case Subscription.get_status(msisdn) do
        str when str in ["pending", "active"] -> true
        _ -> false
      end
    else
      true
    end
  rescue e ->
    false
  end

  defp valid_status_options do
    ["pending", "active"]
  end

  def valid_msisdn_presence(msisdn) do
    "valid_msisdn_presence/1" |> color_info(:yellow)
    if Subscription.exists?(msisdn), do: true, else: false
  rescue e ->
    "valid_msisdn_presence/1 exception : #{inspect e}" |> color_info(:red)
    false
  end

  def valid_msisdn_status(msisdn, status) do
    "valid_msisdn_status/2 :: msisdn: #{inspect(msisdn)}, status: #{inspect(status)}" |> color_info(:yellow)
    case Subscription.get_status(msisdn) do
      str when str == status -> true
      _ -> false
    end
  rescue e ->
    "valid_msisdn_status/2 exception : #{inspect e}" |> color_info(:red)
    false
  end

  # TODO - REMOVE
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

  # Helpers

  defp formatted_subscriber(subscription) do
    %{
      id: subscription.id,
      msisdn: subscription.msisdn,
      status: subscription.status,
      services: subscription.services,
      date: subscription.updated_at || subscription.inserted_at,
      is_validated: (if subscription.validated == true, do: "Yes", else: "No")
    }
  end

  defp formatted_payment(payment) do
    %{
      id: payment.id,
      mobile: payment.msisdn,
      amount: payment.amount,
      status: payment.status,
      payment_date: payment.paid_at || payment.inserted_at,
      is_paid: (if payment.paid == true, do: "Yes", else: "No")
    }
  end

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

  def empty?(val) when is_nil(val) do
    true
  end

  def empty?(val) when is_binary(val) do
    if val == "" do
      true
    else
      false
    end
  end

  def empty?(val) do
    false
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

  # endpoints to test DOI API via Rails App

  def cellc_request(method, endpoint, payload, timeout) do
    try do
      headers = [{"Content-Type", "application/json"}]

      base_url = doi_api_url() <> "/" <> endpoint

      case request(base_url, method, headers, payload, timeout) do
        {200, response} ->
          response

        {st, error} ->
          "DOI Error (#{st}): #{inspect(error)}" |> color_info(:red)
          error
      end
    rescue
      e -> "cellc_request/5 exception: #{inspect e}" |> color_info(:red)
    end
  end

  def cellc_add(conn, _opts) do
    func = "cellc_add/2 ::"
    map = req_body_map(conn)
    msisdn = Map.get(map, "msisdn", "")
    "#{func} params: #{inspect(map)}" |> color_info(:yellow)

    params = %{"msisdn" => msisdn}
    payload = Poison.encode!(params)
    response = cellc_request(:post, "add_sub", payload, 30)
    "#{func} response: #{inspect(response)}" |> color_info(:green)

    r_json(~m(response))
  rescue e ->
    "cellc_add/2 exception: #{inspect e}" |> color_info(:red)
  end

  def cellc_charge(conn, _opts) do
    func = "cellc_charge/2 ::"
    map = req_body_map(conn)
    "#{func} params: #{inspect(map)}" |> color_info(:yellow)

    headers = [{"Content-Type", "application/json"}]
    endpoint = doi_api_url() <> "/charge_sub"
    msisdn = Map.get(map, "msisdn", "")
    params = %{"msisdn" => msisdn}

    response =
      case request("#{endpoint}", :post, headers, params, 20) do
        {200, body} -> body
        _ -> "error"
      end

    "#{func} response: #{inspect(response)}" |> color_info(:green)

    r_json(~m(response))
  rescue e ->
    "cellc_charge/2 exception: #{inspect e}" |> color_info(:red)
  end

  def cellc_cancel(conn, _opts) do
    func = "cellc_cancel/2 ::"
    map = req_body_map(conn)
    msisdn = Map.get(map, "msisdn", "")
    "#{func} params: #{inspect(map)}" |> color_info(:yellow)

    payload = %{"msisdn" => msisdn} |> Poison.encode!()
    response = cellc_request(:post, "cancel_sub", payload, 20)
    "#{func} response: #{inspect(response)}" |> color_info(:green)

    r_json(~m(response))
  rescue e ->
    "cellc_cancel/2 exception: #{inspect e}" |> color_info(:red)
  end

  def cellc_notify(conn, _opts) do
    func = "cellc_notify/2 ::"
    map = req_body_map(conn)
    msisdn = Map.get(map, "msisdn", "")
    "#{func} params: #{inspect(map)}" |> color_info(:yellow)

    params = %{"msisdn" => msisdn}
    payload = Poison.encode!(params)
    response = cellc_request(:post, "notify_sub", payload, 40)
    "#{func} response: #{inspect(response)}" |> color_info(:green)

    r_json(~m(response))
  rescue e ->
    "cellc_notify/2 exception: #{inspect e}" |> color_info(:red)
  end

  # Backups

  def bkp_add_sub(conn, opts) do
    # This happens when a subscriber through QQ portal ask to subscribe for service(s).
    # QQ portal calls Tenbew gateway for downstream processing
    map = req_query_params(conn)
    msisdn = Map.get(map, "msisdn", "")
    "GET /AddSub :: msisdn: #{msisdn}" |> color_info(:lightblue)

    # 1.Receive add subscriber request
    unless valid_parameters(map) do
      raise ValidationError, message: "invalid params, missing details", status: 500
    end

    # 2. Conduct basic MSISDN Validation
    unless valid_msisdn_format(msisdn) do
      raise ValidationError, message: "invalid msisdn, incorrect format", status: 501
    end

    # 3. Check if the MSISDN is already Subscribed
    sub_status = Subscription.get_status(msisdn)
    is_valid =
      if Subscription.exists?(msisdn) do
        if sub_status == "active" do
          false
        else
          if sub_status == "pending" do
            true
          else
            false
          end
        end
      else
        true
      end

    if is_valid do
      # 4. Call up Cell C DOI Service
      doi_response = call_cell_c("add_sub", map)

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

      message = if is_success, do: doi_response["response"], else: doi_response["error"]

      r_json(~m(status message)s)
    else
      raise ValidationError, message: "invalid msisdn, already subscribed", status: 502
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

  def bkp_charge_sub(conn, opts) do
    # This is a call from Tenbew to charge the subscriber for usage of the content.
    # Tenbew then sends the call to Cell C after basic validation
    map = req_query_params(conn)
    msisdn = Map.get(map, "msisdn", "")
    "GET /ChargeSub :: msisdn: #{msisdn}" |> color_info(:lightblue)

    valid? =
      # 1.Receive Charge subscriber request
      if valid_parameters(map) do
        # 2. Conduct basic MSISDN Validation
        if valid_msisdn_format(msisdn) do
          # 3. Is MSISDN subscribed with active status
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
      response = call_cell_c("charge_sub", map)

      # if response["status"] == "pending" do
        if is_nil(response["error"]), do: update_subscription_details(msisdn, response)
        # message = response["message"]
        status = response["code"]

        is_success? =
          if (status == 200 and is_nil(response["error"])), do: true, else: false

        message = if is_success?, do: response["response"], else: response["error"]

        r_json(~m(status message)s)
      # else
      #   raise ApiError, message: response["error"]
      # end
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

  def bkp_cancel_sub(conn, opts) do
    # This takes place when the subscriber no longer wants subscribe for the content.
    # They initiate the cancel subscription from QQ portal
    map = req_query_params(conn)
    msisdn = Map.get(map, "msisdn", "")
    "GET /CancelSub :: msisdn: #{msisdn}" |> color_info(:lightblue)

    is_valid? =
      if valid_parameters(map) do
        if valid_msisdn_format(msisdn), do: true, else: raise ValidationError, message: "invalid msisdn, incorrect format", status: 501
        if valid_msisdn_existance(msisdn) == false, do: true, else: raise ValidationError, message: "invalid msisdn, not subscribed", status: 502
      else
        false
      end

    response = call_cell_c("cancel_sub", map)

    # doi_resp_code =
      # if is_nil(response["error"]), do: 200, else: response["code"]

    # doi_resp_msg =
      # if is_nil(response["error"]), do: "cancelled successfully", else: response["message"]

    # status =
    #   case is_valid? do
    #     true -> doi_resp_code
    #     false -> 500
    #     _ -> 500
    #   end

    status = response["code"]

    is_success? =
      if (is_valid? and status == 200), do: true, else: false

    message =
      case is_success? do
        true -> response["response"]
        false -> response["error"]
        _ -> "cancellation failed"
      end

    r_json(~m(status message)s)
  rescue
    e in ValidationError ->
      "Validation Error: #{e.message}" |> color_info(:red)
       status = e.status
       message = e.message
       r_json(~m(status message)s)
    e ->
      "Exception: #{inspect(e)}" |> color_info(:red)
      status = 500
      message = "error occured"
      r_json(~m(status message)s)
  end

  def bkp_call_cell_c(map) do
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
        {:error, :econnrefused} -> "connection error"
        {:econnrefused, error} -> "connection error: #{error}"
        _ -> "general error"
      end
    "RESPONSE : #{inspect(response)}" |> color_info(:green)

    if is_binary(response) do
      %{
        "code" => 500,
        "response" => nil,
        "payload" => params,
        "status" => "pending",
        "error" => "#{response}",
        "message" => "error calling DOI API"
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
  rescue
    e in MatchError ->
      "call_cell_c/1 :: MatchError error : #{inspect e}" |> color_info(:red)

    e in HackneyConnectionError ->
      "call_cell_c/1 :: HackneyConnectionError error : #{inspect e}" |> color_info(:red)

    e -> "call_cell_c/1 :: exception : #{inspect e}" |> color_info(:red)
  end

  # def bckp_add_sub_2(conn, opts) do
  #   map = req_query_params(conn)
  #   msisdn = Map.get(map, "msisdn", "")
  #   "GET /AddSub :: msisdn: #{msisdn}" |> color_info(:lightblue)
  #
  #   # 1.Receive add subscriber request
  #   unless valid_parameters(map) do
  #     raise ValidationError, message: "invalid params, missing details", status: 500
  #   end
  #
  #   # 2. Conduct basic MSISDN Validation
  #   unless valid_msisdn_format(msisdn) do
  #     raise ValidationError, message: "invalid msisdn, incorrect format", status: 501
  #   end
  #
  #   # 3. Check if the MSISDN is already Subscribed
  #   unless valid_msisdn_presence(msisdn) do
  #     raise ValidationError, message: "invalid msisdn, already subscribed", status: 502
  #   end
  #   unless valid_msisdn_status(msisdn, "pending") do
  #     raise ValidationError, message: "invalid msisdn, incorrect status", status: 502
  #   end
  #
  #   # 4. Call up Cell C DOI Service
  #   response = call_cell_c("add_sub", map)
  #   is_success? = if (response["code"] == 200 and is_nil(response["error"])), do: true, else: false
  #
  #   unless is_success? do
  #     raise ApiError, message: "invalid DOI response, #{response["error"]}"
  #   end
  #
  #   # 5. Update Database, send code 200 to QQ
  #   update_subscription_details(msisdn, response["data"])
  #   status = if is_success?, do: 200, else: response["code"]
  #   message = if is_success?, do: response["response"], else: response["error"]
  #   r_json(~m(status message)s)
  # rescue
  #   e in ValidationError ->
  #     "Validation Error: #{e.message}" |> color_info(:red)
  #      status = e.status
  #      message = e.message
  #      r_json(~m(status message)s)
  #   e in ApiError ->
  #     "API Error: #{e.message}" |> color_info(:red)
  #     status = 501
  #     message = e.message
  #     r_json(~m(status message)s)
  #   e ->
  #     "Exception: #{inspect(e)}" |> color_info(:red)
  #     status = 500
  #     # message = "error occured"
  #     message = "exception raised"
  #     r_json(~m(status message)s)
  # end

end
