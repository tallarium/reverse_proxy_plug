defmodule ReverseProxyPlugErrorTest do
  use ExUnit.Case
  use Plug.Test

  import Mox

  test "returns bad gateway on error" do
    error = {:error, :some_reason}

    ReverseProxyPlug.HTTPClientMock
    |> expect(:request, fn _method, _url, _body, _headers, _options ->
      error
    end)

    opts = ReverseProxyPlug.init(client: ReverseProxyPlug.HTTPClientMock)

    conn = conn(:get, "/") |> ReverseProxyPlug.call(opts)

    assert conn.status === 502

    ReverseProxyPlug.HTTPClientMock |> verify!
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

    ReverseProxyPlug.HTTPClientMock |> verify!
  end
end
