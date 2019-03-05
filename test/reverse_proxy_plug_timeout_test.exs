defmodule ReverseProxyPlugTimeoutTest do
  use ExUnit.Case
  use Plug.Test

  import Mox

  setup :verify_on_exit!

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
