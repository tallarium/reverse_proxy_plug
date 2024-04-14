if Code.ensure_loaded?(Finch) do
  defmodule ReverseProxyPlug.HTTPClient.Adapters.Finch do
    @moduledoc """
    Finch adapter for the `ReverseProxyPlug.HTTPClient` behaviour

    Only synchronous responses are supported.

    ## Options

    * `:finch_client` - Finch client available in the supervision tree.
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
      {name, opts} = Keyword.pop(options, :finch_client)

      unless name do
        raise ":finch_client option is required"
      end

      case Finch.build(method, url, headers, body, opts)
           |> Finch.request(name) do
        {:ok, env} ->
          {:ok,
           %HTTPClient.Response{
             status_code: env.status,
             body: env.body,
             headers: env.headers,
             request_url: url,
             request: request
           }}

        {:error, %{reason: reason}} ->
          {:error, %HTTPClient.Error{reason: reason}}
      end
    end
  end
end
