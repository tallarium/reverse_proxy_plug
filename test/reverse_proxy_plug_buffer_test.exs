defmodule ReverseProxyBufferTest do
  use ExUnit.Case
  use Plug.Test

  import Mox

  @opts ReverseProxyPlug.init(
          response_mode: :buffer,
          upstream: "example.com",
          client: ReverseProxyPlug.HTTPClientMock
        )

  defp get_buffer_responder(status \\ 200, headers \\ [], body \\ "Success") do
    fn _method, _url, _body, _headers, _options ->
      {:ok, %HTTPoison.Response{body: body, headers: headers, status_code: status}}
    end
  end

  defp default_buffer_responder do
    get_buffer_responder().(nil, nil, nil)
  end

  test "receives response" do
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

  test "removes hop-by-hop headers from response" do
    hop_by_hop_headers = [
      {"connection", "keep-alive"},
      {"keep-alive", "timeout=5, max=1000"},
      {"upgrade", "h2c"},
      {"transfer-encoding", "chunked"}
    ]

    other_headers = [
      {"host", "example.com"},
      {"content-length", "42"},
      {"cache-control", "max-age=3600"}
    ]

    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, get_buffer_responder(200, Enum.concat(hop_by_hop_headers, other_headers)))

    conn =
      conn(:get, "/")
      |> ReverseProxyPlug.call(@opts)

    assert Enum.all?(hop_by_hop_headers, fn x -> x not in conn.resp_headers end),
           "deletes hop-by-hop headers"

    assert Enum.all?(other_headers, fn x -> x in conn.resp_headers end),
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
end
