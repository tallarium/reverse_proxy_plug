defmodule ReverseProxyPlug.HTTPClient.Adapters.ReqTest do
  use ExUnit.Case, async: false

  alias ReverseProxyPlug.HTTPClient.Adapters.Req, as: ReqClient

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
          options: [finch: FinchTest],
          url: "http://localhost:8000#{path}"
        }

        Bypass.expect_once(bypass, fn %Plug.Conn{} = conn ->
          assert conn.method == req.method |> to_string() |> String.upcase()
          assert conn.request_path == path
          Plug.Conn.send_resp(conn, 204, "")
        end)

        assert {:ok, %Response{}} = ReqClient.request(req)
      end

      test "should return async responses for asynchronous requests with method #{method}", %{
        bypass: bypass
      } do
        path = "/my-resource"

        req = %Request{
          method: unquote(method),
          options: [finch: FinchTest],
          url: "http://localhost:8000#{path}"
        }

        Bypass.expect_once(bypass, fn %Plug.Conn{} = conn ->
          assert conn.method == req.method |> to_string() |> String.upcase()
          assert conn.request_path == path
          Plug.Conn.send_resp(conn, 204, "")
        end)

        assert {:ok, stream} = ReqClient.request_stream(req)

        assert [
                 {:status, 204},
                 {:headers, headers}
               ] = Enum.to_list(stream)

        assert is_list(headers)
      end

      test "should return error for requests with method #{method}" do
        path = "/my-resource"

        req = %Request{
          method: unquote(method),
          options: [finch: FinchTest],
          url: "http://localhost:8001#{path}"
        }

        assert {:error, %Error{reason: :econnrefused}} == ReqClient.request(req)
      end
    end
  end
end
