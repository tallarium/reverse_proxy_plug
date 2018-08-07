defmodule ReverseProxyTest do
  use ExUnit.Case
  use Plug.Test

  import Mox

  defp get_responder(status \\ 200, headers \\ [], body \\ "Success", no_chunks \\ 1) do
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
      nil
    end
  end

  defp default_responder do
    get_responder().(nil, nil, nil, nil, nil)
  end

  test "receives response" do
    ReverseProxy.HTTPClientMock
    |> expect(:request, get_responder(200, [{"host", "example.com"}], "Success", 2))

    conn =
      conn(:get, "/")
      |> ReverseProxy.call(upstream: "example.com", client: ReverseProxy.HTTPClientMock)

    assert conn.status == 200, "passes status through"
    assert {"host", "example.com"} in conn.resp_headers, "passes headers through"
    assert conn.resp_body == "Success", "passes body through"
  end

  test "sets correct chunked transfer-encoding headers" do
    ReverseProxy.HTTPClientMock
    |> expect(:request, get_responder(200, [{"content-length", "7"}]))

    conn =
      conn(:get, "/")
      |> ReverseProxy.call(upstream: "example.com", client: ReverseProxy.HTTPClientMock)

    assert {"transfer-encoding", "chunked"} in conn.resp_headers,
           "sets transfer-encoding header"

    resp_header_names =
      conn.resp_headers
      |> Enum.map(fn x -> elem(x, 0) end)

    refute "content-length" in resp_header_names,
           "deletes the content-length header"
  end

  test "handles request path and query string" do
    ReverseProxy.HTTPClientMock
    |> expect(:request, fn _method, url, _body, _headers, _options ->
      assert url == "http://example.com:80/root_upstream/root_path?query=yes"
      default_responder()
    end)

    conn(:get, "/root_path")
    |> ReverseProxy.call(
      upstream: "//example.com/root_upstream?query=yes",
      client: ReverseProxy.HTTPClientMock
    )
  end

  test "preserves trailing slash at the end of request path" do
    ReverseProxy.HTTPClientMock
    |> expect(:request, fn _method, url, _body, _headers, _options ->
      assert url == "http://example.com:80/root_path/"
      default_responder()
    end)

    conn(:get, "/root_path/")
    |> ReverseProxy.call(
      upstream: "//example.com",
      client: ReverseProxy.HTTPClientMock
    )
  end
end
