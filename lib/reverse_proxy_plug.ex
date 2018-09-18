defmodule ReverseProxyPlug do
  @moduledoc """
  The main ReverseProxyPlug module.
  """

  alias Plug.Conn

  @behaviour Plug
  @http_client HTTPoison

  @spec init(Keyword.t()) :: Keyword.t()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), Keyword.t()) :: Plug.Conn.t()
  def call(conn, opts) do
    upstream_parts =
      opts
      |> Keyword.get(:upstream, "")
      |> URI.parse()
      |> Map.to_list()
      |> Enum.filter(fn {_, val} -> val end)
      |> keyword_rename(:path, :request_path)
      |> keyword_rename(:query, :query_string)

    opts =
      opts
      |> Keyword.merge(upstream_parts)
      |> Keyword.put_new(:client, @http_client)
      |> Keyword.put_new(:client_options, [])
      |> Keyword.put_new(:transfer, :chunked)

    retrieve(conn, opts)
  end

  defp keyword_rename(keywords, old_key, new_key),
    do:
      keywords
      |> Keyword.put(new_key, keywords[old_key])
      |> Keyword.delete(old_key)

  defp retrieve(conn, options) do
    {method, url, body, headers, client_options} = prepare_request(conn, options)

    with {:ok, resp} <-
           options[:client].request(
             method,
             url,
             body,
             headers,
             client_options
           ) do
      process_response(options[:transfer], conn, resp)
    else
      _ ->
        conn
        |> Conn.resp(:bad_gateway, "")
        |> Conn.send_resp()
    end
  end

  defp process_response(:chunked, conn, _resp),
    do: stream_response(conn)

  defp process_response(_, conn, %{status_code: status, body: body}),
    do:
      conn
      |> Conn.resp(status, body)

  @spec stream_response(Conn.t()) :: Conn.t()
  defp stream_response(conn) do
    receive do
      %HTTPoison.AsyncStatus{code: code} ->
        conn
        |> Conn.put_status(code)
        |> stream_response

      %HTTPoison.AsyncHeaders{headers: headers} ->
        headers
        |> Enum.map(fn {header, value} -> {header |> String.downcase(), value} end)
        |> Enum.reject(fn {header, _} -> header == "content-length" end)
        |> Enum.reject(fn {header, _} -> header == "transfer-encoding" end)
        |> Enum.concat([{"transfer-encoding", "chunked"}])
        |> Enum.reduce(conn, fn {header, value}, conn ->
          Conn.put_resp_header(conn, header, value)
        end)
        |> Conn.send_chunked(conn.status)
        |> stream_response

      %HTTPoison.AsyncChunk{chunk: chunk} ->
        case Conn.chunk(conn, chunk) do
          {:ok, conn} ->
            stream_response(conn)

          {:error, :closed} ->
            conn
        end

      %HTTPoison.AsyncEnd{} ->
        conn
    end
  end

  defp prepare_url(conn, overrides) do
    keys = [:scheme, :host, :port, :query_string]

    x =
      conn
      |> Map.to_list()
      |> Enum.filter(fn {key, _} -> key in keys end)
      |> Keyword.merge(Enum.filter(overrides, fn {_, val} -> val end))

    request_path = Enum.join(conn.path_info, "/")
    request_path = Path.join(overrides[:request_path] || "/", request_path)

    request_path =
      if String.ends_with?(conn.request_path, "/"),
        do: request_path <> "/",
        else: request_path

    url = "#{x[:scheme]}://#{x[:host]}:#{x[:port]}#{request_path}"

    case x[:query_string] do
      "" -> url
      query_string -> url <> "?" <> query_string
    end
  end

  defp prepare_request(conn, options) do
    # With HTTP/2 `transfer-encoding` shouldn't be included.
    conn =
      conn
      |> Conn.delete_req_header("transfer-encoding")

    method = conn.method |> String.downcase() |> String.to_atom()
    url = prepare_url(conn, options)
    headers = conn.req_headers

    headers =
      if options[:preserve_host_header],
        do: headers,
        else: List.keyreplace(headers, "host", 0, {"host", options[:host]})

    body = read_body(conn)

    client_options =
      options[:transfer]
      |> get_client_opts(options[:client_options])

    {method, url, body, headers, client_options}
  end

  defp get_client_opts(:chunked, opts) do
    opts
    |> Keyword.put_new(:timeout, :infinity)
    |> Keyword.put_new(:timeout, :infinity)
    |> Keyword.put_new(:stream_to, self())
  end

  defp get_client_opts(_, opts), do: opts

  defp read_body(conn) do
    case Conn.read_body(conn) do
      {:ok, body, _conn} ->
        body

      {:more, body, conn} ->
        {:stream,
         Stream.resource(
           fn -> {body, conn} end,
           fn
             {body, conn} ->
               {[body], conn}

             nil ->
               {:halt, nil}

             conn ->
               case Conn.read_body(conn) do
                 {:ok, body, _conn} ->
                   {[body], nil}

                 {:more, body, conn} ->
                   {[body], conn}
               end
           end,
           fn _ -> nil end
         )}
    end
  end
end
