defmodule ReverseProxyPlug.HTTPClient.Adapters.TeslaTest do
  use ExUnit.Case, async: false

  import Tesla.Mock, only: [json: 2]
  import Mox

  alias ReverseProxyPlug.HTTPClient.Adapters.Tesla, as: TeslaClient

  alias ReverseProxyPlug.TeslaMock

  alias ReverseProxyPlug.HTTPClient.{
    Error,
    Request,
    Response
  }

  setup :verify_on_exit!

  describe "request/1" do
    for method <- [:get, :post, :put, :patch, :delete, :options, :head] do
      test "should return response for request with method #{method}" do
        path = "/my-resource"

        req = %Request{
          method: unquote(method),
          url: "http://localhost:8000#{path}",
          options: [tesla_client: client()]
        }

        expect(TeslaMock, :call, fn %Tesla.Env{}, _opts ->
          {:ok, json(%{"my" => "result"}, status: 200)}
        end)

        assert {:ok, %Response{body: ~s[{"my":"result"}], status_code: 200}} =
                 TeslaClient.request(req)
      end

      test "should return error for requests with method #{method}" do
        path = "/my-resource"

        req = %Request{
          method: unquote(method),
          url: "http://localhost:8001#{path}",
          options: [tesla_client: client()]
        }

        expect(TeslaMock, :call, fn %Tesla.Env{}, _opts ->
          {:error, :timeout}
        end)

        assert {:error, %Error{reason: :timeout}} == TeslaClient.request(req)
      end
    end
  end

  defp client do
    Tesla.client([], TeslaMock)
  end
end
