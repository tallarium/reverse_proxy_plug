defmodule ReverseProxyTest do
  use ExUnit.Case
  use Plug.Test

  import Mox

  defp get_responder(status \\ 200, headers \\ [], body \\ "Success", no_chunks \\ 1) do
    fn _a, _b, _c, _d, _e ->
      send(self(), %HTTPoison.AsyncStatus{code: status})
      send(self(), %HTTPoison.AsyncHeaders{headers: headers})

      body
      |> String.codepoints()
      |> Enum.chunk_every(body |> String.length() |> div(no_chunks))
      |> Enum.map(&Enum.join/1)
      |> Enum.map(fn chunk ->
        send(self(), %HTTPoison.AsyncChunk{chunk: chunk})
      end)

      send(self(), %HTTPoison.AsyncEnd{})
      nil
    end
  end

  test "receives response" do
    ReverseProxy.HTTPClientMock
    |> expect(:request, get_responder(200, [{"host", "example.com"}], "Success", 2))

    conn =
      conn(:get, "/")
      |> ReverseProxy.call(upstream: "example.com")

    assert conn.status == 200, "passes status through"
    assert {"host", "example.com"} in conn.resp_headers, "passes headers through"
    assert conn.resp_body == "Success", "passes body through"
  end

  test "sets correct chunked transfer-encoding headers" do
    ReverseProxy.HTTPClientMock
    |> expect(:request, get_responder(200, [{"content-length", "7"}]))

    conn =
      conn(:get, "/")
      |> ReverseProxy.call(upstream: "example.com")

    assert {"transfer-encoding", "chunked"} in conn.resp_headers,
           "sets transfer-encoding header"

    resp_header_names =
      conn.resp_headers
      |> Enum.map(fn x -> elem(x, 0) end)

    refute "content-length" in resp_header_names,
           "deletes the content-length header"
  end
end
