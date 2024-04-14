defmodule ReverseProxyPlug.HTTPClient.Adapters.FinchTest do
  use ExUnit.Case, async: false

  alias ReverseProxyPlug.HTTPClient.Adapters.Finch, as: FinchClient

  alias ReverseProxyPlug.HTTPClient.{
    Error,
    Request,
    Response
  }

  setup do
    start_supervised!({Finch, name: FinchTest})

    %{bypass: Bypass.open(port: 8000)}
  end

  describe "request/1" do
    for method <- [:get, :post, :put, :patch, :delete, :options, :head] do
      test "should return response for request with method #{method}", %{bypass: bypass} do
        path = "/my-resource"

        req = %Request{
          method: unquote(method),
          options: [finch_client: FinchTest],
          url: "http://localhost:8000#{path}"
        }

        Bypass.expect_once(bypass, fn %Plug.Conn{} = conn ->
          assert conn.method == req.method |> to_string() |> String.upcase()
          assert conn.request_path == path
          Plug.Conn.send_resp(conn, 204, "")
        end)

        assert {:ok, %Response{}} = FinchClient.request(req)
      end

      test "should return error for requests with method #{method}" do
        path = "/my-resource"

        req = %Request{
          method: unquote(method),
          options: [finch_client: FinchTest],
          url: "http://localhost:8001#{path}"
        }

        assert {:error, %Error{reason: :econnrefused}} == FinchClient.request(req)
      end
    end
  end
end
