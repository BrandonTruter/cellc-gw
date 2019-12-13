defmodule ValidationError do
  @moduledoc false
  defexception [:message, :status]
end

# defmodule AuthorizationError do
#   @moduledoc false
#   defexception [:message]
# end

defmodule ApiError do
  @moduledoc false
  defexception [:message, :status]
end

defmodule Plug.Parsers.XML do
  @behaviour Plug.Parsers
  import Plug.Conn
  import Util.Log

  def parse(conn, _, "xml", _headers, opts) do
    decoder = Keyword.get(opts, :xml_decoder) || raise ArgumentError, "XML parser expects a :xml_decoder option"

    conn
    |> read_body(opts)
    |> decode(decoder)
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp decode({:ok, body, conn}, decoder) do
    case decoder.string(String.to_charlist(body)) do
      {parsed, []} ->
        # {:ok, %{xml: parsed}, conn}
        {:ok, %{xml: body}, conn}
      error ->
        raise "Malformed XML #{error}"
    end
  rescue
    e -> raise Plug.Parsers.ParseError, exception: e
  end
end

defmodule TenbewGw.Endpoint do
  use Plug.Router
  use Plug.Debugger
  use Plug.ErrorHandler

  import Plug.Conn
  import Util.Log
  import Util.WebRequest
  import Util.XmlParser
  import ShortMaps

  alias TenbewGw.Repo
  alias TenbewGw.Router
  alias Plug.{Adapters.Cowboy2, HTML}
  alias TenbewGw.Model.{Subscription, Payment, Message}

  require Logger

  plug(:match)
  plug(Plug.Logger, log: :info)
  plug(Plug.RequestId)
  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json, :xml],
    pass: ["*/*"], # ["application/json", "application/octet-stream", "text/xml"],
    json_decoder: Poison,
    xml_decoder: :xmerl_scan
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

            "/chargesub.php" -> {__MODULE__, :charge_subscriber, ["general"]}

            "/sms/SendSMS" -> {__MODULE__, :send_sms, ["general"]}
            "/SendSMS.php" -> {__MODULE__, :send_sms_2, ["general"]}
            _ -> nil
          end

        "POST" ->
          case route do
            "/add_subscription" -> {__MODULE__, :add_subscription, ["general"]}
            "/add_payment" -> {__MODULE__, :add_payment, ["general"]}
            "/callback_url" -> {__MODULE__, :update_sub_status, ["general"]}
            "/update_sub_status" -> {__MODULE__, :update_sub_status, ["general"]}
            "/cellc_cb_test" -> {__MODULE__, :cellc_cb_test, ["general"]}
            "/cellc_cb1" -> {__MODULE__, :cellc_cb1, ["general"]}
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


  def charge_subscriber(conn, opts) do
    map = req_query_params(conn)
    msisdn = Map.get(map, "msisdn", "")
    "GET /charge_subscriber/2 :: msisdn: #{msisdn}" |> color_info(:lightblue)

    unless valid_parameters(map) do
      raise ValidationError, message: "invalid params, missing details", status: 500
    end

    unless validate_format(msisdn) do
      raise ValidationError, message: "invalid msisdn, incorrect format", status: 501
    end

    if validate_presence(msisdn, "active") do
      if validate_daily_payment(msisdn) do
        "Validation Error: already charged" |> color_info(:red)
        status = 200
        message = "already charged"
        r_json(~m(status message)s)
      else
        subscription = Subscription.get_by_msisdn(msisdn)
        map = Map.put(map, "service_id", subscription.services)
        response = call_cell_c("charge", map)

        if response["code"] == 200 do
          create_payment_details(msisdn)
          update_subscription_details(msisdn, response["data"])

          status  = 200
          message = response["response"]
          r_json(~m(status message)s)
        else
          pid = spawn_link(__MODULE__,  :charge_retries , [msisdn, map])
          "Spawning #{inspect pid} calling charge_retries" |> color_info(:red)
          status = 504
          message = response["error"]
          r_json(~m(status message)s)
        end
      end
    else
      if valid_msisdn_status(msisdn, "cancelled") do
        raise ValidationError, message: "invalid msisdn, subscription is cancelled", status: 503
      else
        if Subscription.exists?(msisdn) do
          response = call_cell_c("notify_sub", map)
          status   = 503
          message  =
            if response["code"] == 200, do: response["response"], else: "subscriber notified"

          r_json(~m(status message)s)
          # raise ValidationError, message: "subscriber notified", status: 503
        else
          raise ValidationError, message: "invalid msisdn, MSISDN not subscribed", status: 503
          # raise ValidationError, message: "invalid msisdn, subscriber does not exist", status: 502
        end
      end
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

  # Primary Endpoints

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
    # unless valid_msisdn_existance(msisdn) do
    #   raise ValidationError, message: "invalid msisdn, already subscribed", status: 502
    # end

    # if validate_presence(msisdn, "pending") do
    #   raise ValidationError, message: "invalid msisdn, already subscribed", status: 502
    # end

    if Subscription.exists?(msisdn) do
      # this should check everything besides cancelled
      if Subscription.get_status(msisdn) == "pending" do
        raise ValidationError, message: "invalid msisdn, already subscribed", status: 502
      end
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
            "Validation Error: already charged" |> color_info(:red)
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
              pid = spawn_link(__MODULE__,  :charge_retries , [msisdn, map])
              "Spawning #{inspect pid} calling charge_retries" |> color_info(:red)
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


  # SMS integration (might remove)

  def send_sms(conn, opts) do
    map = req_query_params(conn)
    msisdn = Map.get(map, "msisdn", "")
    message = Map.get(map, "message", "")
    message_id = Map.get(map, "MessageID", "")
    subscription = Subscription.get_by_msisdn(msisdn)
    "GET /SendSMS :: msisdn: #{msisdn}, message: #{message}" |> color_info(:lightblue)
    attrs = %{message: message, message_id: message_id, subscription_id: subscription.id}
    # process_sms_request(msisdn)
    # "after process_sms_request/1" |> color_info(:yellow)

    case Message.create_message(attrs) do
      {:ok, message} ->
        success = "message created #{message.id}"
        "Message Success: #{inspect(message)}" |> color_info(:green)
        r_json(~m(success)s)

      {:error, %Ecto.Changeset{} = changeset} ->
        error = changeset_errors(changeset)
         "Message Error: #{inspect(error)}" |> color_info(:red)
        r_json(~m(error)s)
    end
  rescue e ->
    error = "#{inspect(e)}"
    "GET /SendSMS :: Exception: #{error}" |> color_info(:red)
    r_json(~m(error)s)
  end

  def send_sms_2(conn, opts) do
    map = req_query_params(conn)
    msisdn = Map.get(map, "msisdn", "")
    message = Map.get(map, "message", "")
    message_id = Map.get(map, "MessageID", "")
    subscription = Subscription.get_by_msisdn(msisdn)
    "GET /SendSMS :: msisdn: #{msisdn}, message: #{message}" |> color_info(:lightblue)
    attrs = %{message: message, message_id: message_id, subscription_id: subscription.id}

    process_message_creation(attrs)

    process_sms_request(msisdn)

    response = "SMS done"

    r_json(~m(response)s)
  rescue e ->
    error = "#{inspect(e)}"
    "GET /SendSMS :: Exception: #{error}" |> color_info(:red)
    r_json(~m(error)s)
  end

  defp process_message_creation(attrs) do
    func = "process_message_creation/1 ::"
    "#{func} #{inspect(attrs)} " |> color_info(:yellow)

    case Message.create_message(attrs) do
      {:ok, message} ->
        "#{func} Success: #{inspect(message)}" |> color_info(:green)

      {:error, %Ecto.Changeset{} = changeset} ->
         "#{func} Error: #{inspect(changeset_errors(changeset))}" |> color_info(:red)
    end
  end

  defp process_sms_request(msisdn) do
    func = "process_sms_request/1"
    "#{func} :: msisdn: #{msisdn}" |> color_info(:yellow)
    port = 13013
    user = "foo"
    pass = "bar"
    system_id = ""
    host = "156.38.208.218"
    sms_url = "cgi-bin/sendsms"
    base_url = "http://smsbox.host.name"
    sms_text = text_message |> URI.encode_query
    query_params = "username=#{user}&password=#{pass}&to=#{msisdn}&text=#{sms_text}"
    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]
    endpoint = "#{base_url}:#{port}/#{sms_url}?#{query_params}"

    # via Kannel HTTP
    "#{func} :: Kannel HTTP ..." |> color_info(:yellow)

    case request(endpoint, :get, headers, "", 30) do
      {200, response} -> "#{func} :: SUCCESS: #{inspect(response)}" |> color_info(:green)
      {st, error} -> "#{func} :: ERROR: code: #{st}, #{error}" |> color_info(:red)
      _ -> "#{func} :: EXCEPTION: failed to process SMS" |> color_info(:red)
    end

    # via SMPPEX.Session
    # "#{func} :: SMPPEX.Session ..." |> color_info(:yellow)

    # {:ok, esme} = Util.SmsSession.start_link(host, port)
    # SMPPEX.Session.send_pdu(esme, SMPPEX.Pdu.Factory.bind_transmitter(system_id, pass))
  end

  defp text_message do
    "Welcome to QQ-Tenbew Games. Experience our world. Thank you for subscribing. Service costs 5 Rands a day charged daily"
  end


  # Cell C DOI Methods

  defp cellc_request(endpoint, params) do
    method = :post
    # params = %{"msisdn" => msisdn}
    payload = Poison.encode!(params)
    base_url = doi_api_url() <> "/" <> endpoint
    headers = [{"Content-Type", "application/json"}]

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
  rescue
    e -> "cellc_request/2 exception: #{inspect e}" |> color_info(:red)
  end

  def call_cell_c(endpoint, map) do
    msisdn = Map.get(map, "msisdn", "")
    service_id = Map.get(map, "service_id", "")
    "call_cell_c/2 :: #{inspect(map)}" |> color_info(:yellow)
    unless endpoint in ["add_sub", "charge_sub", "cancel_sub", "notify_sub", "charge"] do
      raise ApiError, message: "invalid endpoint, #{endpoint} not support", status: 501
    end
    # response = cellc_request(endpoint, msisdn)

    payload =
      if endpoint == "charge" do
        %{"msisdn" => msisdn, "service_id" => service_id}
      else
        %{"msisdn" => msisdn}
      end
    response = cellc_request(endpoint, payload)

    if is_nil(response), do: raise ApiError, message: "invalid DOI response", status: 501

    if is_binary(response) do
      message = "#{endpoint} request failed, #{response}"
      return_cellc_error(map, "#{response}", "#{message}")
    else
      # status = if endpoint == "add_sub", do: "pending", else: "active"
      message = "#{endpoint} processed successfully, #{inspect(response)}"
      message |> color_info(:green)
      msg = stringify_message(endpoint)
      service_id = response["service_id"]
      status =
        case endpoint do
          "add_sub" -> "pending"
          "charge_sub" -> "active"
          "cancel_sub" -> "cancelled"
          _ -> "active"
        end
      returned_data = %{
        status: status, service_id: service_id
      }
      response_message =
        if endpoint == "cancel_sub" do
          "cancelled successfully"
        else
          if is_nil(service_id), do: msg , else: "#{msg}, serviceID: #{service_id}"
        end

      %{
        "code" => 200,
        "error" => nil,
        "status" => status,
        "data" => returned_data,
        "message" => "#{message}",
        "response" => %{success: response_message}
      }
    end
  rescue
    e in ApiError ->
      return_cellc_error(map, e.message, "ApiError")
    e in MatchError ->
      return_cellc_error(map, e.message, "MatchError")
    e in HackneyConnectionError ->
      return_cellc_error(map, e.message, "HackneyConnectionError")
    e ->
      return_cellc_error(map, e.message, "General Exception Raised")
  end

  defp return_cellc_error(map, error, type) do
    func = "call_cell_c/2 ::"
    "#{func} payload : #{inspect map}" |> color_info(:red)
    "#{func} #{type} : #{inspect error}" |> color_info(:red)
    %{
      "code" => 500,
      "data" => nil,
      "response" => nil,
      "payload" =>  map,
      "status" => "pending",
      "message" => "#{type}",
      "error" => %{error: error}
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
    |> Enum.each(fn x -> :timer.apply_after(x, __MODULE__, :charge_retry, [msisdn, data]) end)
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

  # Callback URL

  def cellc_cb1(conn, _opts) do
    func = "cellc_cb1/2"
    func |> color_info(:lightblue)

    map = req_body_map(conn)
    xml_str = Map.get(map, :xml, nil)
    asr_response = parse_asr(xml_str)
    asr = asr_response[:addSubscriptionResult]
    "#{func} :: ASR Result: #{inspect(asr)}" |> color_info(:yellow)

    cc_tid = asr[:ccTID]
    msisdn = asr[:msisdn]
    status = asr[:status]
    sms_sent = asr[:smsSent]
    sms_reply = asr[:smsReply]
    service_id = asr[:serviceID]

    unless Subscription.exists?(msisdn) do
      raise ValidationError, message: "invalid msisdn, MSISDN not subscribed", status: 503
    end

    # update subscription
    if status == "ACTIVE" do
      sub_data = %{
        status: "active",
        service_id: service_id
      }
      update_subscription_details(msisdn, sub_data)
    end

    if sms_reply == "Yes" do
      "#{func} :: Replied with Yes, SMS content: #{inspect(sms_sent)}" |> color_info(:yellow)
      subscription = Subscription.get_by_msisdn(msisdn)

      unless is_nil(subscription) do
        # TODO Ensure the same SMS isnt sent twice by multiple ASR requests
        message_exists = Message.exists?("000", subscription.id)
        message_attrs = %{
          message: sms_sent,
          message_id: "000",
          subscription_id: subscription.id
        }

        unless message_exists do
          case Message.create_message(message_attrs) do
            {:ok, message} ->
              "#{func} :: Message Created Successfully: #{inspect(message)}" |> color_info(:green)

            {:error, %Ecto.Changeset{} = changeset} ->
              "#{func} :: Error Creating Message: #{inspect(changeset_errors(changeset))}" |> color_info(:red)
          end
        end
      end
    end

    response_xml = """
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <ns2:getServicesResponse xmlns:ns2="http://wasp.doi.soap.protocol.WASP.co.za">
          <return>
            <serviceID>#{service_id}</serviceID>
            <msisdn>#{msisdn}</msisdn>
            <Result>0</Result>
            <ccTid>#{cc_tid}</ccTid>
          </return>
        </ns2:getServicesResponse>
      </soap:Body>
    </soap:Envelope>
    """

    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(200, response_xml)
  rescue
    e in ValidationError ->
      "cellc_cb1/2 exception : #{inspect e}" |> color_info(:red)
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(400, "error processing callback request: #{e.message}")
    e ->
      "cellc_cb1/2 exception : #{inspect e}" |> color_info(:red)
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(400, "failed to process callback request")
  end

  def cellc_cb_test(conn, opts) do
    func = "cellc_cb_test/2"
    func |> color_info(:lightblue)
    "#{func} :: conn: #{inspect(conn)}" |> color_info(:yellow)

    map = req_body_map(conn)
    "#{func} :: map: #{inspect(map)}" |> color_info(:yellow)

    xml_str = Map.get(map, :xml, nil)

    asr_xml_response = process_asr(xml_str)

    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(200, asr_xml_response)
  rescue e ->
    "cellc_cb_test/2 exception : #{inspect e}" |> color_info(:red)
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(400, "failed to process callback test")
  end

  # Database Methods

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
      payment_date = NaiveDateTime.utc_now
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
          Payment.get_payment_by_msisdn(params["msisdn"])
        else
          ""
        end
      end

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

  # Validation Methods

  def valid_parameters(map) when is_map(map) do
    "valid_parameters/1" |> color_info(:yellow)
    # STEP 1 - Receive add subscriber request
    # The request will originate from the Cell C QQ portal for a new subscriber.
    keys = ~w(waspTID serviceID msisdn mn)

    Enum.all?(keys, fn x -> Map.get(map, x) != nil end)
  end
  def valid_parameters(_, _) , do: false

  def valid_msisdn_format(msisdn) do
    "valid_msisdn_format/1" |> color_info(:yellow)
    # STEP 2 - Conduct basic MSISDN Validation
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

  def valid_msisdn_existance(msisdn, status) do
    "valid_msisdn_existance/2" |> color_info(:yellow)
    # STEP 3 - Check if the MSISDN is already Subscribed
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
        str when str in ["cancelled", "pending"] -> true
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
  rescue e ->
    "validate_daily_payment/1 exception: #{inspect e}" |> color_info(:red)
  end

  # refactored versions - used by ChargeSub

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
      is_paid: (if payment.paid == true, do: "Yes", else: "Not Yet")
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

  # if required, add logic for creating subscriptions on Rails App

  # def add_doi_sub(map) do
  #   headers = [{"Content-Type", "application/json"}]
  #   endpoint = doi_api_url() <> "/subscriptions"
  #   msisdn = Map.get(map, "msisdn", "")
  #   params = %{
  #     "subscription" => %{
  #       "msisdn" => msisdn,
  #       "state" => "active",
  #       "service" => "gateway",
  #       "reference" => "testing api",
  #       "message" => "gateway subscription"
  #     }
  #   } |> Poison.encode!()
  #
  #   case request(endpoint, :post, headers, params, 30) do
  #     {200, body} -> body
  #     {:error, :econnrefused} -> "connection error"
  #     {:econnrefused, error} -> "connection error: #{error}"
  #     _ -> "general error"
  #   end
  # rescue
  #   e -> "add_doi_sub/1 :: exception : #{inspect e}" |> color_info(:red)
  # end

  # Backups

  # def call_cell_c(endpoint, map) do
  #   "call_cell_c/2" |> color_info(:yellow)
  #   method = :post
  #   msisdn = Map.get(map, "msisdn", "")
  #   params = %{ "msisdn" => msisdn }
  #   payload = Poison.encode!(params)
  #   base_url = doi_api_url() <> "/" <> endpoint
  #   headers = [{"Content-Type", "application/json"}]
  #   unless endpoint in ["add_sub", "charge_sub", "cancel_sub", "notify_sub"] do
  #     raise ApiError, message: "invalid endpoint, #{endpoint} not support", status: 501
  #   end
  #   response =
  #     case request(base_url, method, headers, payload, 30) do
  #       {200, response} -> response
  #       {st, error} ->
  #         if error == "undefined error" do
  #           "code: #{st}, response: DOI connection error"
  #         else
  #           "code: #{st}, response: #{error}"
  #         end
  #       {:error, :econnrefused} -> "connection error: econnrefused"
  #       {:econnrefused, err} -> "connection error: #{inspect(err)}"
  #       _ -> "general error calling DOI API with payload: #{payload}"
  #     end
  #
  #   if is_nil(response), do: raise ApiError, message: "invalid DOI response", status: 501
  #
  #   if is_binary(response) do
  #     message = "#{endpoint} request failed, #{inspect(response)}"
  #     message |> color_info(:red)
  #     %{
  #       "code" => 500,
  #       "data" => nil,
  #       "response" => nil,
  #       "payload" => params,
  #       "status" => "pending",
  #       "message" => "#{message}",
  #       "error" => %{error: response}
  #     }
  #   else
  #     message = "#{endpoint} processed successfully, #{inspect(response)}"
  #     "#{message}" |> color_info(:green)
  #     msg = stringify_message(endpoint)
  #     service_id = response["service_id"]
  #     returned_data = %{
  #       status: "active",
  #       service_id: service_id
  #     }
  #     response_message = if endpoint == "cancel_sub" do
  #                           "cancelled successfully"
  #                         else
  #                           if is_nil(service_id), do: msg , else: "#{msg}, serviceID: #{service_id}"
  #                         end
  #     %{
  #       "code" => 200,
  #       "error" => nil,
  #       "status" => "active",
  #       "data" => returned_data,
  #       "message" => "#{message}",
  #       "response" => %{success: response_message}
  #     }
  #   end
  # rescue
  #   e in ApiError ->
  #     "call_cell_c/2 :: ApiError Exception : #{inspect e.message}" |> color_info(:red)
  #     %{
  #       "code" => 500,
  #       "data" => nil,
  #       "response" => nil,
  #       "payload" => map,
  #       "status" => "pending",
  #       "message" => "ApiError",
  #       "error" => %{error: "#{inspect e.message}"}
  #     }
  #   e ->
  #     "call_cell_c/2 :: exception : #{inspect e}" |> color_info(:red)
  #     %{
  #       "code" => 500,
  #       "data" => nil,
  #       "response" => nil,
  #       "payload" => map,
  #       "status" => "pending",
  #       "message" => "Exception Raised",
  #       "error" => %{error: "#{inspect e.message}"}
  #     }
  # end

end
