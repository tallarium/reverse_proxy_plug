defmodule ReverseProxyPlug do
  @moduledoc """
  The main ReverseProxyPlug module.
  """

  alias Plug.Conn

  alias ReverseProxyPlug.HTTPClient
  import Plug.Conn, only: [fetch_cookies: 1]

  @behaviour Plug
  @http_methods ["GET", "HEAD", "POST", "PUT", "DELETE", "CONNECT", "OPTIONS", "TRACE", "PATCH"]
  @timeout_error_reasons [:connect_timeout, :timeout, {:closed, :timeout}]

  @spec init(Keyword.t()) :: Keyword.t()
  def init(opts) do
    (@http_methods ++ Keyword.get(opts, :custom_http_methods, []))
    |> Enum.each(fn x ->
      x
      |> String.downcase()
      |> String.to_atom()
    end)

    upstream_parts =
      opts
      |> Keyword.fetch!(:upstream)
      |> get_string()
      |> upstream_parts()

    if opts[:status_callbacks] != nil and opts[:response_mode] not in [nil, :stream] do
      raise ":status_callbacks must only be specified with response_mode: :stream"
    end

    opts
    |> ensure_http_client()
    |> Keyword.merge(upstream_parts)
    |> Keyword.put_new(:client_options, [])
    |> Keyword.put_new(:response_mode, :stream)
    |> Keyword.put_new(:stream_headers_mode, :replace)
    |> Keyword.put_new(:buffer_headers_mode, :prepend)
    |> Keyword.put_new(:normalize_headers, &ReverseProxyPlug.downcase_headers/1)
    |> Keyword.put_new(:status_callbacks, %{})
    |> Keyword.update(:error_callback, nil, fn
      {m, f, a} -> {m, f, a}
      fun when is_function(fun) -> fun
    end)
    |> ensure_response_mode_compatibility()
  end

  @spec call(Plug.Conn.t(), Keyword.t()) :: Plug.Conn.t()
  def call(conn, opts) do
    upstream_parts =
      opts
      |> Keyword.get(:upstream, "")
      |> get_applied_fn(conn)
      |> upstream_parts()

    opts =
      opts
      |> Keyword.merge(upstream_parts)

    {body, conn} = read_body(conn)
    conn |> request(body, opts) |> response(conn, opts)
  end

  @doc false
  def get_timeout_error_reasons, do: @timeout_error_reasons

  defp get_string(upstream, default \\ "")

  defp get_string(upstream, _) when is_binary(upstream) do
    upstream
  end

  defp get_string(_, default) do
    default
  end

  defp get_applied_fn(upstream, conn, default \\ "")

  defp get_applied_fn(upstream, _conn, _) when is_function(upstream, 0) do
    upstream.()
  end

  defp get_applied_fn(upstream, conn, _) when is_function(upstream, 1) do
    upstream.(conn)
  end

  defp get_applied_fn(_, _conn, default) do
    default
  end

  defp upstream_parts("" = _upstream) do
    []
  end

  defp upstream_parts(upstream) do
    upstream
    |> URI.parse()
    |> Map.to_list()
    |> Enum.filter(fn {_, val} -> val end)
    |> keyword_rename(:path, :request_path)
    |> keyword_rename(:query, :query_string)
  end

  def request(conn, body, opts) do
    {method, url, headers, client_options} = prepare_request(conn, opts)

    opts[:client].request(%HTTPClient.Request{
      method: method,
      url: url,
      body: body,
      headers: headers,
      options: client_options
    })
  end

  def response({:ok, resp}, conn, opts) do
    process_response(opts[:response_mode], conn, resp, opts)
  end

  def response(error, conn, opts) do
    do_error_callback(opts[:error_callback], error, conn)
  end

  defp do_error_callback({m, f, a}, error, conn) do
    cond do
      function_exported?(m, f, length(a) + 2) ->
        apply(m, f, a ++ [error, conn])

      function_exported?(m, f, length(a) + 1) ->
        apply(m, f, a ++ [error])
        default_error_resp(error, conn)

      true ->
        raise "error callback has invalid arity"
    end
  end

  defp do_error_callback(fun, error, conn) when is_function(fun) do
    case Function.info(fun, :arity) do
      {:arity, 2} ->
        fun.(error, conn)

      {:arity, 1} ->
        fun.(error)
        default_error_resp(error, conn)
    end
  end

  defp do_error_callback(nil, error, conn), do: default_error_resp(error, conn)

  defp default_error_resp(error, conn) do
    conn
    |> Conn.resp(status_from_error(error), "")
    |> Conn.send_resp()
  end

  defp status_from_error({:error, %HTTPClient.Error{id: nil, reason: reason}})
       when reason in @timeout_error_reasons do
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

  defp process_response(
         :buffer,
         conn,
         %{status_code: status, body: body, headers: headers},
         opts
       ) do
    headers
    |> opts[:normalize_headers].()
    |> remove_hop_by_hop_headers
    |> add_resp_headers(conn, opts[:buffer_headers_mode])
    |> Conn.resp(status, body)
  end

  defp process_response(:stream, initial_conn, %HTTPClient.AsyncResponse{} = resp, opts) do
    resp
    |> opts[:client].stream_response()
    |> Enum.reduce_while(initial_conn, fn
      {:status, status}, conn ->
        case Map.fetch(opts[:status_callbacks], status) do
          {:ok, handler} ->
            {:halt, handler.(conn, opts)}

          :error ->
            {:cont, conn |> Conn.put_status(status)}
        end

      {:headers, headers}, conn ->
        {:cont, conn |> send_stream_response_headers(headers, opts)}

      {:chunk, chunk}, conn ->
        case Conn.chunk(conn, chunk) do
          {:ok, conn_after_chunk} -> {:cont, conn_after_chunk}
          {:error, _error} -> {:halt, conn}
        end

      {:error, error}, conn ->
        {:halt, do_error_callback(opts[:error_callback], error, conn)}
    end)
  end

  defp prepare_url(conn, overrides) do
    keys = [:scheme, :host, :port, :query_string]

    x =
      conn
      |> Map.to_list()
      |> Enum.filter(fn {key, _} -> key in keys end)
      |> Keyword.put(:host, conn.host)
      |> Keyword.merge(Enum.filter(overrides, fn {_, val} -> val end))

    request_path = Enum.join(conn.path_info, "/")
    request_path = Path.join(overrides[:request_path] || "/", request_path)

    request_path =
      if String.ends_with?(conn.request_path, "/") && !String.ends_with?(request_path, "/"),
        do: request_path <> "/",
        else: request_path

    url = "#{x[:scheme]}://#{x[:host]}:#{x[:port]}#{request_path}"

    case x[:query_string] do
      "" -> url
      query_string -> url <> "?" <> query_string
    end
  end

  defp prepare_request(conn, options) do
    method =
      try do
        conn.method
        |> String.downcase()
        |> String.to_existing_atom()
      rescue
        ArgumentError ->
          reraise "invalid http method, if you want to forward custom http methods, " <>
                    "please add them as a list param of opts[:custom_http_methods].",
                  __STACKTRACE__
      end

    url = prepare_url(conn, options)

    headers =
      conn.req_headers
      |> options[:normalize_headers].()
      |> remove_hop_by_hop_headers
      |> add_x_fwd_for_header(conn)

    proxy_req_host =
      if options[:preserve_host_header] do
        conn.host
      else
        host_header_from_url(url)
      end

    headers = List.keystore(headers, "host", 0, {"host", proxy_req_host})

    client_options =
      options[:response_mode]
      |> get_client_opts(options[:client_options])
      |> recycle_cookies(conn)

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

  defp send_stream_response_headers(%{status: status} = conn, headers, opts) do
    headers
    |> opts[:normalize_headers].()
    |> remove_hop_by_hop_headers
    |> Enum.reject(fn {header, _} -> header == "content-length" end)
    |> add_resp_headers(conn, opts[:stream_headers_mode])
    |> Conn.send_chunked(status)
  end

  def downcase_headers(headers) do
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

    # We downcase here, in case a custom :normalize_headers function does not downcase headers
    headers
    |> Enum.reject(fn {header, _} -> Enum.member?(hop_by_hop_headers, String.downcase(header)) end)
  end

  defp add_x_fwd_for_header(headers, conn) do
    {x_fwd_for, headers} = Enum.split_with(headers, fn {k, _v} -> k == "x-forwarded-for" end)

    remote_ip = conn.remote_ip |> Tuple.to_list() |> Enum.join(".")

    x_forwarded_for =
      case x_fwd_for do
        [{"x-forwarded-for", x_fwd_value}] ->
          "#{x_fwd_value}, #{remote_ip}"

        _ ->
          remote_ip
      end

    headers ++ [{"x-forwarded-for", x_forwarded_for}]
  end

  defp recycle_cookies(client_opts, conn) do
    case get_cookies(conn) do
      "" ->
        client_opts

      cookies when is_bitstring(cookies) ->
        Keyword.put(client_opts, :hackney, cookie: cookies)
    end
  end

  defp get_cookies(%Conn{cookies: %Conn.Unfetched{aspect: :cookies}} = conn) do
    conn |> fetch_cookies() |> get_cookies()
  end

  defp get_cookies(%Conn{req_cookies: cookies}) do
    cookies |> Enum.map_join("; ", fn {k, v} -> "#{k}=#{v}" end)
  end

  def read_body(conn, opts \\ [])

  def read_body(%{assigns: %{raw_body: raw_body}} = conn, _opts), do: {raw_body, conn}

  def read_body(conn, opts) do
    Stream.unfold(Plug.Conn.read_body(conn, opts), fn
      :done ->
        nil

      {:ok, body, new_conn} ->
        {{new_conn, body}, :done}

      {:more, partial_body, new_conn} ->
        {partial_body, Plug.Conn.read_body(new_conn, opts)}
    end)
    |> Enum.reduce({"", conn}, fn
      {new_conn, body}, {body_acc, _conn_acc} -> {body_acc <> body, new_conn}
      partial_body, {body_acc, conn_acc} -> {body_acc <> partial_body, conn_acc}
    end)
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

  defp host_header_from_url(%URI{host: host, port: port, scheme: "https"}) do
    "#{host}:#{port}"
  end

  defp ensure_http_client(opts) do
    module =
      opts[:client] || Application.get_env(:reverse_proxy_plug, :http_client) ||
        HTTPClient.Adapters.HTTPoison

    Keyword.put(opts, :client, Code.ensure_loaded!(module))
  end

  defp ensure_response_mode_compatibility(opts) do
    if opts[:response_mode] == :stream and
         not function_exported?(opts[:client], :stream_response, 1) do
      raise ArgumentError,
            "The client adapter does not support streaming responses. Please use :buffer response mode."
    else
      opts
    end
  end

  defp add_resp_headers(resp_headers, conn, :prepend) do
    Conn.prepend_resp_headers(conn, resp_headers)
  end

  defp add_resp_headers(resp_headers, conn, :replace) do
    Enum.reduce(resp_headers, conn, fn {header, value}, conn ->
      Conn.put_resp_header(conn, header, value)
    end)
  end
end
