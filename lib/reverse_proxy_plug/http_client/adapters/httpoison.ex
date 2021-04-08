defmodule ReverseProxyPlug.HTTPClient.Adapters.HTTPoison do
  @moduledoc """
  HTTPoison adapter for the `ReverseProxyPlug.HTTPClient` behaviour
  """

  alias ReverseProxyPlug.HTTPClient

  @behaviour HTTPClient

  @impl HTTPClient
  def request(%HTTPClient.Request{} = request) do
    HTTPoison.request(%HTTPoison.Request{
      method: request.method,
      url: request.url,
      headers: request.headers,
      params: request.query_params,
      body: request.body,
      options: request.options
    })
  end
end
