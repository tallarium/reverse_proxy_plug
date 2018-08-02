defmodule ReverseProxyTest do
  use ExUnit.Case
  use Plug.Test

  import Mox

  test "greets the world" do
    ReverseProxy.HTTPClientMock
    |> expect(:request, fn _a, _b, _c, _d, _e -> :ok end)

    conn(:get, "/")
    |> ReverseProxy.call(upstream: "example.com")
  end
end
