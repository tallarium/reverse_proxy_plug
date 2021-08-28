if Code.ensure_loaded?(Tesla) do
  defmodule ReverseProxyPlug.HTTPClient.Adapters.Tesla do
    @moduledoc """
    Tesla adapter for the `ReverseProxyPlug.HTTPClient` behaviour

    Only synchronous responses are supported.

    ## Options

    * `:tesla_client` - mandatory definition for the `Tesla.Client`
                        to be used.
    """

    alias ReverseProxyPlug.HTTPClient

    @behaviour HTTPClient

    @impl HTTPClient
    def request(%HTTPClient.Request{options: options} = request) do
      {client, opts} = Keyword.pop(options, :tesla_client)

      unless client do
        raise ":tesla_client option is required"
      end

      tesla_opts =
        request
        |> Map.take([:url, :method, :body, :headers])
        |> Map.put(:query, request.query_params)
        |> Map.put(:opts, opts)
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)

      case Tesla.request(client, tesla_opts) do
        {:ok, %Tesla.Env{} = env} ->
          {:ok,
           %HTTPClient.Response{
             status_code: env.status,
             body: env.body,
             headers: env.headers,
             request_url: env.url,
             request: request
           }}

        {:error, error} ->
          {:error, %HTTPClient.Error{reason: error}}
      end
    end
  end
end
