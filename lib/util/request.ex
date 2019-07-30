defmodule WebRequestError do
  @moduledoc false
  defexception [:message]
end

defmodule Util.WebRequest do
  import Util.Log
  import TenbewGw
  import ShortMaps
  @base_api "api/v1"

  def finish_request(ref) do
    {:ok, body} = :hackney.body(ref)
    body
  end

  def loop(ref) do
    "ref: #{inspect ref}" |> color_info(:yellow)
    :hackney.stream_next(ref)
    receive do
      {:hackney_response, ^ref, {:headers, headers}} ->
      "headers at loop: #{inspect headers}" |> color_info(:yellow)
      "ref: #{inspect ref}" |> color_info(:yellow)
      {:ok, ref} = :hackney.stop_async(ref)
      "ref: #{inspect ref}" |> color_info(:yellow)
      finish_request(ref)
    end
  end

  def request(url, method \\ :get, headers \\ [], body \\ "", timeout \\ 5) do
    "URL #{inspect url} BODY #{inspect body}" |> color_info(:blue)
    body =
      case body do
        b when is_map(b) -> Poison.encode!(b)
        b when is_binary(b) -> b
        _ -> ""
      end
    timeout = timeout * 1000
    #{:ok, ref} = :hackney.request(method, url, headers, body, [{:async, :once}])
    {:ok, ref} =
      :hackney.request(method, url, headers, body,
        [{:async, :once}, {:connect_timeout, timeout}, {:recv_timeout, timeout}])
    receive do
      {:hackney_response, ^ref, {:status, status, _reason}} ->
        body = loop(ref)
        "hackney: status: #{status} #{inspect body}" |> color_info(:magenta)
        {status, body |> Poison.decode!()}
      other ->
        "hackney receive when error #{inspect other}" |> color_info(:magenta)
        "undefined response from hackney" |> color_info(:yellow)
        :hackney.stop_async(ref)
        {403, "undefined error"}
    after
      timeout ->
        "request timeout" |> color_info(:yellow)
        error = "request timeout"
        :hackney.stop_async(ref)
        #{403, ~m(error)s}
        {403, error}
    end
  rescue
    e ->
      "hackney rescue #{inspect e}" |> color_info(:red)
      st_data(System.stacktrace(), e) |> log_error_data()
      {403, "undefined error"}
  end

  def request!(url, method, headers, body, timeout \\ 5) do
    case request(url, method, headers, body, timeout) do
      {200, response} -> response
      {x, y} -> raise WebRequestError, message: "#{x}, #{inspect y}"
      x ->
        "Undefined error: #{inspect x}" |> color_info(:yellow)
        raise WebRequestError, message: "undefined error"
    end
  end


  def api_call(url, method \\ :get, headers \\ [], body \\ "", timeout \\ 10) do
    body =
      case body do
        b when is_map(b) ->
          "WebRequest body is map" |> color_info(:magenta)
          "WebRequest url: #{inspect url}" |> color_info(:magenta)
          "WebRequest method: #{inspect method}" |> color_info(:magenta)
          "WebRequest headers: #{inspect headers}" |> color_info(:magenta)
          "WebRequest body: #{inspect b}" |> color_info(:magenta)
          "WebRequest timeout: #{inspect timeout}" |> color_info(:magenta)
          Jason.encode!(b)
        b when is_binary(b) ->
          "WebRequest body is binary" |> color_info(:magenta)
          "WebRequest url: #{inspect url}" |> color_info(:magenta)
          "WebRequest method: #{inspect method}" |> color_info(:magenta)
          "WebRequest headers: #{inspect headers}" |> color_info(:magenta)
          "WebRequest body: #{inspect b}" |> color_info(:magenta)
          "WebRequest timeout: #{inspect timeout}" |> color_info(:magenta)
          b
        b ->
          "WebRequest body is strange, defaulting to empty string" |> color_info(:magenta)
          "WebRequest url: #{inspect url}" |> color_info(:magenta)
          "WebRequest method: #{inspect method}" |> color_info(:magenta)
          "WebRequest headers: #{inspect headers}" |> color_info(:magenta)
          "WebRequest body: #{inspect b}" |> color_info(:magenta)
          "WebRequest timeout: #{inspect timeout}" |> color_info(:magenta)
          ""
      end

    pool = :default
    timeout = timeout * 1000
    options = [async: :once, connect_timeout: timeout, recv_timeout: timeout, pool: pool]
    {:ok, ref} = :hackney.request(method, url, headers, body, options)
    "WebRequest body: #{inspect body} has ref #{inspect ref}" |> color_info(:magenta)

    receive do
      {:hackney_response, ^ref, {:status, status, reason}} ->
        body = loop(ref)
        case Jason.decode(body) do
          {:ok, val} -> {status, val}
          {:error, error} ->
            "Jason decode error #{inspect error}" |> color_info(:red)
            {403, "decode error"}
        end
      val ->
        "non matched response from hackney in WebRequest.request receive #{inspect val}" |> color_info(:red)
        :hackney.stop_async(ref)
        {403, "internal service is busy"}
    after
      timeout ->
        "request timeout" |> color_info(:yellow)
        error = "request timeout"
        :hackney.stop_async(ref)
        {403, %{"error" => error}}
    end
  rescue
    e ->
      "rescuing WebRequest.request #{inspect e}" |> color_info(:red)
      st_data(System.stacktrace(), e) |> log_error_data()
      {403, "undefined error"}
  end

  def api_call!(url, method, headers, body, timeout \\ 5) do
    case api_call(url, method, headers, body, timeout) do
      {200, response} ->
        response
      {x, y} ->
        raise WebRequestError, message: "#{x}, #{inspect(y)}"
      x ->
        "Undefined error: #{inspect(x)}" |> color_info(:yellow)
        raise WebRequestError, message: "undefined error"
    end
  end


  def test() do
    case request("http://localhost:4000/#{@base_api}/get_subscription?msisdn=0712363482", :get, [], "", 5) do
      {200, body} -> body
      _ ->
        "error"
    end
  end

  def test2() do
    s = TenbewGw.Model.Subscription.get_first_subscription()
    msisdn = s.msisdn
    data = ~m(msisdn)s # |> Poison.encode!()
    case request("http://localhost:4000/#{@base_api}/add_subscriber", :post, [], data, 5) do
      {200, body} -> body
      _ ->
        "error"
    end
  end

  def test3() do
    # unknown = "1231"
    # data = ~m(unknown)s # |> Poison.encode!()
    data = %{"unknown" => "1231"}
    case request("http://localhost:4000/#{@base_api}/add_subscriber", :post, [], data, 5) do
      {200, body} -> body
      _ ->
        "error"
    end
  end

  def test4() do
    msisdn = "0723321527"
    data = ~m(msisdn)s # |> Poison.encode!()
    case request("http://localhost:4000/#{@base_api}/add_subscriber", :post, [], data, 5) do
      {200, body} -> body
      _ ->
        "error"
    end
  end

end
