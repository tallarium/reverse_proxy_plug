if Code.ensure_loaded?(HTTPoison) do
  defmodule ReverseProxyPlug.HTTPClient.Adapters.HTTPoison do
    @moduledoc """
    HTTPoison adapter for the `ReverseProxyPlug.HTTPClient` behaviour
    """

    alias ReverseProxyPlug.HTTPClient

    @behaviour HTTPClient

    @impl HTTPClient
    def request(%HTTPClient.Request{} = request) do
      request
      |> translate_request()
      |> HTTPoison.request()
      |> translate_response()
    end

    defp translate_request(%HTTPClient.Request{} = request) do
      %HTTPoison.Request{
        method: request.method,
        url: request.url,
        headers: request.headers,
        params: request.query_params,
        body: request.body,
        options: request.options
      }
    end

    defp translate_request(%HTTPoison.Request{} = request) do
      %HTTPClient.Request{
        method: request.method,
        url: request.url,
        headers: request.headers,
        query_params: request.params,
        body: request.body,
        options: request.options
      }
    end

    defp translate_response({tag, %mod{request: request} = response})
         when tag in [:ok, :error] and mod in [HTTPoison.Response, HTTPoison.MaybeRedirect] do
      data =
        response
        |> Map.from_struct()
        |> Map.put(:request, translate_request(request))

      translated_resp =
        mod
        |> translate_mod()
        |> struct(data)

      {tag, translated_resp}
    end

    defp translate_response({tag, %mod{} = response}) when tag in [:ok, :error] do
      data = Map.from_struct(response)

      translated_resp =
        mod
        |> translate_mod()
        |> struct(data)

      {tag, translated_resp}
    end

    defp translate_mod(HTTPoison.Response), do: HTTPClient.Response
    defp translate_mod(HTTPoison.AsyncResponse), do: HTTPClient.AsyncResponse
    defp translate_mod(HTTPoison.MaybeRedirect), do: HTTPClient.MaybeRedirect
    defp translate_mod(HTTPoison.Error), do: HTTPClient.Error
  end
end
