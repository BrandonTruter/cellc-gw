defmodule Util.Log do
  require Logger
  @error_loggers Application.get_env(:tenbew_gw, :error_loggers)

  def color_reset , do: "\x1b[0m"
  def color_red, do: "\x1b[31m"
  def color_green, do: "\x1b[32m"
  def color_yellow, do: "\x1b[33m"
  def color_blue, do: "\x1b[34m"
  def color_magenta, do: "\x1b[35m"
  def color_light_blue, do: "\x1b[94m"
  def color_light_red, do: "\x1b[91m"

  def color_me(value, atom \\ nil) do
    color =
    case atom do
      :red -> color_red()
      :green -> color_green()
      :yellow -> color_yellow()
      :blue -> color_blue()
      :magenta -> color_magenta()
      :lightblue -> color_light_blue()
      :lightred -> color_light_red()
      _ -> ""
    end
    end_color =
    if color === "" do
        ""
    else
        color_reset()
    end
    "#{color}#{value}#{end_color}"
  end

  def color_info(color, msg) when is_atom(color) do
    msg |> color_me(color) |> Logger.info
    color
  end

  def color_info(msg, color) when is_atom(color) do
    msg |> color_me(color) |> Logger.info
    msg
  end

  defp get_running_context() do
    Mix.env
    |> Atom.to_string()
    rescue
      e in UndefinedFunctionError -> :escript |> Atom.to_string()
      _ -> :undefined
  end

  def zf(val, zeroes \\ 1) when is_integer(val) do
    val
    |> Integer.to_string
    #|> String.rjust(zeroes, ?0)
    |> String.pad_leading(zeroes, "0")
  end

  def log_to(what, func, module \\ "DP") do
    spawn __MODULE__, :log_to_targets, [what, func, module]
  end

  def log_to_targets(what, func, module) do
    @error_loggers |> Enum.map(fn x -> log_to({x, what, func, module}) end)
  end

  def log_to({:file_logger, what, func, module}) do
    {{y, m, d}, {h, mi, s}} = :os.timestamp |> :calendar.now_to_datetime
    prepend = "#{zf(y,4)}-#{zf(m,2)}-#{zf(d,2)} #{zf(h,2)}:#{zf(mi,2)}:#{zf(s,2)}} [#{module}.#{func}]"
    File.write("#{get_running_context()}_error_logger.txt", "#{prepend} #{inspect what}\n", [:append])
  end

  def log_to({:screen, what, func, module}) do
    "[#{inspect module}.#{func}] #{inspect what}" |> color_info(:red)
  end

  def log_to({:db, _what, _func, _module}) do
    "When ready stacktrace info would go to DB" |> color_info(:green)
    rescue _e -> nil
  end

  def log_to({:kafka, _what, _func, _module}) do
    "When ready stacktrace info would go to DB" |> color_info(:green)
    rescue _e -> nil
  end

  def log_error_targets(map) when is_map(map) do
    @error_loggers |> Enum.map(fn x -> log_error_data({x, map}) end)
  end

  def log_error_data(map) when is_map(map) do
    spawn __MODULE__, :log_error_targets, [map]
  end

  def log_error_data({:file_logger, map}) do
    {{y, m, d}, {h, mi, s}} = :os.timestamp |> :calendar.now_to_datetime
    prepend = "#{zf(y,4)}-#{zf(m,2)}-#{zf(d,2)} #{zf(h,2)}:#{zf(mi,2)}:#{zf(s,2)}}"
    File.write("#{get_running_context()}_error_logger.txt", "#{prepend} #{inspect map}\n", [:append])
    rescue _e -> nil
  end

  def log_error_data({:screen, map}) do
    "#{inspect map}" |> color_info(:red)
    rescue e -> nil
  end

  def log_error_data({:db, _map}) do
    #%Error{}
    #|> Error.changeset(map)
    #|> Repo.insert()
    nil
    rescue _e -> nil
  end

  def log_error_data({:kafka, _map}) do
    "When ready stacktrace info would go to Kafka" |> color_info(:green)
    rescue _e -> nil
  end

  @doc """
  this exists as an example of how to handle the error logging
  Just
  import Util.Log at the beginning of the .ex file
  and...
  add at the end of any function you want to be error logged ...

    rescue e ->
      st_data(System.stacktrace, e) |> log_error_data()
      reraise e, System.stacktrace

  """
  def test_error() do
    1 / 0
    rescue e ->
      st_data(System.stacktrace, e) |> log_error_data()
      reraise e, System.stacktrace
  end

  def st_data(stack_trace, e) do
    [st | _] = stack_trace
    module = elem(st, 0)
    function = elem(st, 1)
    arity = elem(st, 2)
    where = elem(st, 3)
    file =
    case Keyword.fetch(where, :file) do
      {:ok, val} -> val
      _ -> "source unavailable"
    end
    line =
    case Keyword.fetch(where, :line) do
      {:ok, val} -> val
      _ -> "line unavailable"
    end
    %{module: Atom.to_string(module),
      function: Atom.to_string(function),
      arity: arity,
      file: "#{file}",
      line: line,
      error: "#{inspect e}"
    }
    rescue _e -> %{
      module: "Unknown",
      function: "Unknown",
      arity: 0,
      file: "",
      line: 0,
      error: "Unknown"
    }
  end
end
