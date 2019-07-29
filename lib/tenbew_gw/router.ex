defmodule TenbewGw.Router do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  @content_type "application/json"

  get "/" do
    conn
    |> put_resp_content_type(@content_type)
    |> send_resp(200, welcome_message())
  end

  get "/home" do
    conn
    |> put_resp_content_type(@content_type)
    |> send_resp(400, welcome_message())
  end

  match _ do
    send_resp(conn, 404, error_message())
  end

  defp welcome_message do
    Poison.encode!(%{
      response_type: "default",
      text: "welcome to our gateway :)"
    })
  end

  defp error_message do
    Poison.encode!(%{
      response_type: "error",
      text: "requested endpoint not available"
    })
  end

end
