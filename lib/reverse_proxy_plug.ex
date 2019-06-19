defmodule ReverseProxyPlug do
  @moduledoc """
  The main ReverseProxyPlug module.
  """

  alias Plug.Conn

  @behaviour Plug
  @http_client HTTPoison

  @spec init(Keyword.t()) :: Keyword.t()
  def init(opts) do
    upstream_parts =
      opts
      |> Keyword.get(:upstream, "")
      |> URI.parse()
      |> Map.to_list()
      |> Enum.filter(fn {_, val} -> val end)
      |> keyword_rename(:path, :request_path)
      |> keyword_rename(:query, :query_string)

    opts
    |> Keyword.merge(upstream_parts)
    |> Keyword.put_new(:client, @http_client)
    |> Keyword.put_new(:client_options, [])
    |> Keyword.put_new(:response_mode, :stream)
  end

  @spec call(Plug.Conn.t(), Keyword.t()) :: Plug.Conn.t()
  def call(conn, opts) do
    body = read_body(conn)
    conn |> request(body, opts) |> response(conn, opts)
  end

  def request(conn, body, opts) do
    {method, url, headers, client_options} = prepare_request(conn, opts)

    opts[:client].request(%HTTPoison.Request{
      method: method,
      url: url,
      body: body,
      headers: headers,
      options: client_options
    })
  end

  def response({:ok, resp}, conn, opts) do
    process_response(opts[:response_mode], conn, resp)
  end

  def response(error, conn, opts) do
    error_callback = opts[:error_callback]

    if error_callback do
      error_callback.(error)
    end

    conn
    |> Conn.resp(status_from_error(error), "")
    |> Conn.send_resp()
  end

  defp status_from_error({:error, %HTTPoison.Error{id: nil, reason: reason}})
       when reason in [:timeout, :connect_timeout] do
    :gateway_timeout
  end

  defp status_from_error(_any) do
    :bad_gateway
  end

  defp keyword_rename(keywords, old_key, new_key),
    do:
      keywords
      |> Keyword.put(new_key, keywords[old_key])
      |> Keyword.delete(old_key)

  defp process_response(:stream, conn, _resp),
    do: stream_response(conn)

  defp process_response(:buffer, conn, %{status_code: status, body: body, headers: headers}) do
    resp_headers =
      headers
      |> normalize_headers

    conn
    |> Conn.prepend_resp_headers(resp_headers)
    |> Conn.resp(status, body)
  end

  @spec stream_response(Conn.t()) :: Conn.t()
  defp stream_response(conn) do
    receive do
      %HTTPoison.AsyncStatus{code: code} ->
        conn
        |> Conn.put_status(code)
        |> stream_response

      %HTTPoison.AsyncHeaders{headers: headers} ->
        headers
        |> normalize_headers
        |> Enum.reject(fn {header, _} -> header == "content-length" end)
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
    method = conn.method |> String.downcase() |> String.to_atom()
    url = prepare_url(conn, options)

    headers =
      conn.req_headers
      |> normalize_headers
      
    headers =
    if is_list(options[:client_headers]),
        do:
        Map.merge(Enum.into(headers, %{}), Enum.into(options[:client_headers], %{}))
        |> Map.to_list,
        else: headers

    headers =
      if options[:preserve_host_header],
        do: headers,
        else: List.keyreplace(headers, "host", 0, {"host", host_header_from_url(url)})

    client_options =
      options[:response_mode]
      |> get_client_opts(options[:client_options])

    {method, url, headers, client_options}
  end

  defp get_client_opts(:stream, opts) do
    opts
    |> Keyword.put_new(:timeout, :infinity)
    |> Keyword.put_new(:recv_timeout, :infinity)
    |> Keyword.put_new(:stream_to, self())
  end

  defp get_client_opts(:buffer, opts) do
    opts
    |> Keyword.put_new(:timeout, :infinity)
    |> Keyword.put_new(:recv_timeout, :infinity)
  end

  defp normalize_headers(headers) do
    headers
    |> downcase_headers
    |> remove_hop_by_hop_headers
  end

  defp downcase_headers(headers) do
    headers
    |> Enum.map(fn {header, value} -> {String.downcase(header), value} end)
  end

  defp remove_hop_by_hop_headers(headers) do
    hop_by_hop_headers = [
      "te",
      "transfer-encoding",
      "trailer",
      "connection",
      "keep-alive",
      "proxy-authenticate",
      "proxy-authorization",
      "upgrade"
    ]

    headers
    |> Enum.reject(fn {header, _} -> Enum.member?(hop_by_hop_headers, header) end)
  end

  def read_body(conn) do
    case Conn.read_body(conn) do
      {:ok, "", %{assigns: %{raw_body: raw_body}}} ->
        raw_body

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

  defp host_header_from_url(url) when is_binary(url) do
    url |> URI.parse() |> host_header_from_url
  end

  defp host_header_from_url(%URI{host: host, port: nil}) do
    host
  end

  defp host_header_from_url(%URI{host: host, port: 80, scheme: "http"}) do
    host
  end

  defp host_header_from_url(%URI{host: host, port: 443, scheme: "https"}) do
    host
  end

  defp host_header_from_url(%URI{host: host, port: port, scheme: "http"}) do
    "#{host}:#{port}"
  end
end
