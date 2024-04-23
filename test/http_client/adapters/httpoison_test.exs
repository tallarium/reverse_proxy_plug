defmodule ReverseProxyPlug.HTTPClient.Adapters.HTTPoisonTest do
  use ExUnit.Case, async: false

  alias ReverseProxyPlug.HTTPClient.Adapters.HTTPoison, as: HTTPoisonClient

  alias ReverseProxyPlug.HTTPClient.{
    Error,
    Request,
    Response
  }

  setup do
    %{bypass: Bypass.open(port: 8000)}
  end

  describe "request/1" do
    for method <- [:get, :post, :put, :patch, :delete, :options, :head] do
      test "should return response for request with method #{method}", %{bypass: bypass} do
        path = "/my-resource"

        req = %Request{
          method: unquote(method),
          url: "http://localhost:8000#{path}"
        }

        Bypass.expect_once(bypass, fn %Plug.Conn{} = conn ->
          assert conn.method == req.method |> to_string() |> String.upcase()
          assert conn.request_path == path
          Plug.Conn.send_resp(conn, 204, "")
        end)

        assert {:ok, %Response{}} = HTTPoisonClient.request(req)
      end

      test "should return async responses for asynchronous request with method #{method}", %{
        bypass: bypass
      } do
        path = "/my-resource"

        req = %Request{
          method: unquote(method),
          url: "http://localhost:8000#{path}",
          options: [stream_to: self()]
        }

        Bypass.expect_once(bypass, fn %Plug.Conn{} = conn ->
          assert conn.method == req.method |> to_string() |> String.upcase()
          assert conn.request_path == path
          Plug.Conn.send_resp(conn, 204, "")
        end)

        assert {:ok, %Response{}} = HTTPoisonClient.request(req)

        assert_receive %HTTPoison.AsyncStatus{code: 204}, 1_000
        assert_receive %HTTPoison.AsyncHeaders{headers: headers}, 1_000
        assert_receive %HTTPoison.AsyncEnd{}, 1_000
        assert is_list(headers)
      end

      test "should return error for requests with method #{method}" do
        path = "/my-resource"

        req = %Request{
          method: unquote(method),
          url: "http://localhost:8001#{path}"
        }

        assert {:error, %Error{reason: :econnrefused}} == HTTPoisonClient.request(req)
      end
    end

    test "should return error when request timeout" do
      bypass = Bypass.open(port: 8002)
      on_exit({Bypass, bypass.pid}, fn -> :ok end)
      recv_timeout = 50

      path = "/my-timeout-path"

      req = %Request{
        method: :get,
        url: "http://localhost:8002#{path}",
        options: [
          recv_timeout: recv_timeout,
          stream_to: self()
        ]
      }

      Bypass.expect_once(bypass, fn %Plug.Conn{} = conn ->
        assert conn.method == req.method |> to_string() |> String.upcase()
        assert conn.request_path == path

        Process.sleep(recv_timeout + 1)
        Plug.Conn.send_resp(conn, 204, "")
      end)

      assert {:ok, %Response{}} = HTTPoisonClient.request(req)

      assert_receive %HTTPoison.Error{reason: {:closed, :timeout}}, 1_000
    end
  end
end
