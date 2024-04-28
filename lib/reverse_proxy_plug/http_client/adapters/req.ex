if Code.ensure_loaded?(Req) do
  defmodule ReverseProxyPlug.HTTPClient.Adapters.Req do
    @moduledoc """
    Req adapter for the `ReverseProxyPlug.HTTPClient` behaviour

    Only synchronous responses are supported.

    See the [Req documentation](https://hexdocs.pm/req/Req.html#new/1) for client-specific options.
    """

    alias ReverseProxyPlug.HTTPClient

    @behaviour HTTPClient

    @impl HTTPClient
    def request(
          %HTTPClient.Request{
            method: method,
            url: url,
            headers: headers,
            body: body,
            options: options
          } = request
        ) do
      case Req.new(method: method, url: url, headers: headers, body: body, retry: false)
           |> Req.update(options)
           |> Req.request() do
        {:ok, resp} ->
          {:ok,
           %HTTPClient.Response{
             status_code: resp.status,
             body: resp.body,
             headers: resp.headers,
             request_url: url,
             request: request
           }}

        {:error, %{reason: reason}} ->
          {:error, %HTTPClient.Error{reason: reason}}
      end
    end
  end
end
