defmodule ReverseProxyTest do
  use ExUnit.Case
  use Plug.Test

  import Mox

  defp get_responder(status, headers, body, no_chunks \\ 1) do
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

    assert conn.status == 200
    assert Enum.member?(conn.resp_headers, {"host", "example.com"})
    assert conn.resp_body == "Success"
  end
end
