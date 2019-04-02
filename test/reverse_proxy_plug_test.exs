defmodule ReverseProxyPlugTest do
  use ExUnit.Case
  use Plug.Test

  import Mox

  @opts ReverseProxyPlug.init(
          response_mode: :buffer,
          upstream: "example.com",
          client: ReverseProxyPlug.HTTPClientMock
        )

  @hop_by_hop_headers [
    {"connection", "keep-alive"},
    {"keep-alive", "timeout=5, max=1000"},
    {"upgrade", "h2c"},
    {"proxy-authenticate", "Basic"},
    {"proxy-authorization", "Basic abcd"},
    {"te", "compress"},
    {"trailer", "Expires"}
  ]

  @end_to_end_headers [
    {"cache-control", "max-age=3600"},
    {"cookie", "acookie"},
    {"date", "Tue, 15 Nov 1994 08:12:31 GMT"}
  ]

  @host_header [
    {"host", "example.com"}
  ]

  setup :verify_on_exit!

  test "receives buffer response" do
    headers = [{"host", "example.com"}, {"content-length", "42"}]

    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, get_buffer_responder(200, headers, "Success"))

    conn =
      conn(:get, "/")
      |> ReverseProxyPlug.call(@opts)

    assert conn.status == 200, "passes status through"
    assert Enum.all?(headers, fn x -> x in conn.resp_headers end), "passes headers through"
    assert conn.resp_body == "Success", "passes body through"
  end

  test "removes hop-by-hop headers before forwarding request" do
    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, get_mock_request(@end_to_end_headers))

    conn(:get, "/")
    |> Map.put(:req_headers, @hop_by_hop_headers ++ @end_to_end_headers)
    |> ReverseProxyPlug.call(@opts)
  end

  test "removes hop-by-hop headers from buffer response" do
    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, get_buffer_responder(200, @hop_by_hop_headers ++ @end_to_end_headers))

    conn =
      conn(:get, "/")
      |> ReverseProxyPlug.call(@opts)

    assert Enum.all?(@hop_by_hop_headers, fn x -> x not in conn.resp_headers end),
           "deletes hop-by-hop headers"

    assert Enum.all?(@end_to_end_headers, fn x -> x in conn.resp_headers end),
           "passes other headers through"
  end

  test "does not add transfer-encoding header to response" do
    headers = [{"host", "example.com"}, {"content-length", "42"}]

    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, get_buffer_responder(200, headers, "Success"))

    conn =
      conn(:get, "/")
      |> ReverseProxyPlug.call(@opts)

    resp_header_names =
      conn.resp_headers
      |> Enum.map(fn x -> elem(x, 0) end)

    refute "transfer-encoding" in resp_header_names,
           "does not add transfer-encoding header"
  end

  ### ERROR TEST

  test "returns bad gateway on error" do
    error = {:error, :some_reason}

    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, fn _method, _url, _body, _headers, _options ->
      error
    end)

    opts = ReverseProxyPlug.init(client: ReverseProxyPlug.HTTPClientMock)

    conn = conn(:get, "/") |> ReverseProxyPlug.call(opts)

    assert conn.status === 502
  end

  test "calls error callback if supplied" do
    error = {:error, :some_reason}

    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, fn _method, _url, _body, _headers, _options ->
      error
    end)

    opts =
      ReverseProxyPlug.init(
        error_callback: fn err -> send(self(), {:got_error, err}) end,
        client: ReverseProxyPlug.HTTPClientMock
      )

    conn(:get, "/") |> ReverseProxyPlug.call(opts)

    assert_receive({:got_error, error})
  end


  defp get_buffer_responder(status, headers, body \\ "Success") do
    fn _method, _url, _body, _headers, _options ->
      {:ok, %HTTPoison.Response{body: body, headers: headers, status_code: status}}
    end
  end

  defp get_stream_responder(status \\ 200, headers \\ [], body \\ "Success", no_chunks \\ 1) do
    fn _method, _url, _body, _headers, _options ->
      send(self(), %HTTPoison.AsyncStatus{code: status})
      send(self(), %HTTPoison.AsyncHeaders{headers: headers})

      body
      |> String.codepoints()
      |> Enum.chunk_every(body |> String.length() |> div(no_chunks))
      |> Enum.map(&Enum.join/1)
      |> Enum.each(fn chunk ->
        send(self(), %HTTPoison.AsyncChunk{chunk: chunk})
      end)

      send(self(), %HTTPoison.AsyncEnd{})
      {:ok, nil}
    end
  end

  defp default_stream_responder do
    get_stream_responder().(nil, nil, nil, nil, nil)
  end

  defp get_mock_request(expected_headers) do
    fn _method, _url, _body, headers, _options ->
      assert headers == expected_headers
    end
  end

  test "receives stream response" do
    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, get_stream_responder(200, @host_header, "Success", 2))

    conn =
      conn(:get, "/")
      |> ReverseProxyPlug.call(@opts |> Keyword.merge(response_mode: :stream))

    assert conn.status == 200, "passes status through"
    assert {"host", "example.com"} in conn.resp_headers, "passes headers through"
    assert conn.resp_body == "Success", "passes body through"
  end

  test "removes hop-by-hop headers from stream response" do
    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, get_stream_responder(200, @hop_by_hop_headers ++ @end_to_end_headers))

    conn =
      conn(:get, "/")
      |> ReverseProxyPlug.call(@opts |> Keyword.merge(response_mode: :stream))

    assert Enum.all?(@hop_by_hop_headers, fn x -> x not in conn.resp_headers end),
           "deletes hop-by-hop headers"

    assert Enum.all?(@end_to_end_headers, fn x -> x in conn.resp_headers end),
           "passes other headers through"
  end

  test "sets correct chunked transfer-encoding headers" do
    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, get_stream_responder(200, [{"content-length", "7"}]))

    conn =
      conn(:get, "/")
      |> ReverseProxyPlug.call(@opts |> Keyword.merge(response_mode: :stream))

    assert {"transfer-encoding", "chunked"} in conn.resp_headers,
           "sets transfer-encoding header"

    resp_header_names =
      conn.resp_headers
      |> Enum.map(fn x -> elem(x, 0) end)

    refute "content-length" in resp_header_names,
           "deletes the content-length header"
  end

  test "handles request path and query string" do
    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, fn _method, url, _body, _headers, _options ->
      assert url == "http://example.com:80/root_upstream/root_path?query=yes"
      default_stream_responder()
    end)

    conn(:get, "/root_path")
    |> ReverseProxyPlug.call(
      ReverseProxyPlug.init(
        upstream: "//example.com/root_upstream?query=yes",
        client: ReverseProxyPlug.HTTPClientMock
      )
    )
  end

  test "preserves trailing slash at the end of request path" do
    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, fn _method, url, _body, _headers, _options ->
      assert url == "http://example.com:80/root_path/"
      default_stream_responder()
    end)

    conn(:get, "/root_path/")
    |> ReverseProxyPlug.call(
      ReverseProxyPlug.init(
        upstream: "//example.com",
        client: ReverseProxyPlug.HTTPClientMock
      )
    )
  end

  test "include the port in the host header when is not the default and preserve_host_header is false in opts" do
    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, get_mock_request([{"host", "example-custom-port.com:8081"}]))

    conn(:get, "/")
    |> Plug.Conn.put_req_header("host", "custom.com:9999")
    |> ReverseProxyPlug.call(
      ReverseProxyPlug.init(
        upstream: "//example-custom-port.com:8081",
        client: ReverseProxyPlug.HTTPClientMock
      )
    )
  end

  test "don't include the port in the host header when is the default and preserve_host_header is false in opts" do
    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, get_mock_request([{"host", "example-custom-port.com"}]))

    conn(:get, "/")
    |> Plug.Conn.put_req_header("host", "custom.com:9999")
    |> ReverseProxyPlug.call(
      ReverseProxyPlug.init(
        upstream: "//example-custom-port.com:80",
        client: ReverseProxyPlug.HTTPClientMock
      )
    )
  end

  test "don't include the port in the host header when is the default for https and preserve_host_header is false in opts" do
    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, get_mock_request([{"host", "example-custom-port.com"}]))

    conn(:get, "/")
    |> Plug.Conn.put_req_header("host", "custom.com:9999")
    |> ReverseProxyPlug.call(
      ReverseProxyPlug.init(
        upstream: "https://example-custom-port.com:443",
        client: ReverseProxyPlug.HTTPClientMock
      )
    )
  end

  test "returns gateway timeout on connect timeout" do
    conn = :get |> conn("/") |> simulate_upstream_error(:connect_timeout)

    assert conn.status === 504
  end

  test "returns gateway timeout on timeout" do
    conn = :get |> conn("/") |> simulate_upstream_error(:timeout)

    assert conn.status === 504
  end

  test "passes timeout options to HTTP client" do
    timeout_val = 5_000

    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, fn _method, _url, _body, _headers, options ->
      send(self(), {:httpclient_options, options})
    end)

    opts =
      ReverseProxyPlug.init(
        client: ReverseProxyPlug.HTTPClientMock,
        client_options: [timeout: timeout_val, recv_timeout: timeout_val]
      )

    :get |> conn("/") |> ReverseProxyPlug.call(opts)

    assert_receive {:httpclient_options, httpclient_options}
    assert timeout_val == httpclient_options[:timeout]
    assert timeout_val == httpclient_options[:recv_timeout]
  end

  defp simulate_upstream_error(conn, reason) do
    error = {:error, %HTTPoison.Error{id: nil, reason: reason}}

    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, fn _method, _url, _body, _headers, _options ->
      error
    end)

    opts = ReverseProxyPlug.init(client: ReverseProxyPlug.HTTPClientMock)

    ReverseProxyPlug.call(conn, opts)
  end
end
