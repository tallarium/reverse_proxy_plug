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
      |> translate_response(request)
    end

    defp translate_request(%HTTPClient.Request{} = request) do
      %HTTPoison.Request{
        method: request.method,
        url: request.url,
        headers: request.headers,
        params: request.query_params,
        body: request.body,
        options: recycle_cookies(request.options, request.cookies)
      }
    end

    defp recycle_cookies(options, "") do
      options
    end

    defp recycle_cookies(options, cookies) when is_bitstring(cookies) do
      Keyword.put(options, :hackney, cookie: cookies)
    end

    defp translate_response({tag, %mod{} = response}, request)
         when tag in [:ok, :error] and mod in [HTTPoison.Response, HTTPoison.MaybeRedirect] do
      data =
        response
        |> Map.from_struct()
        |> Map.put(:request, request)

      translated_resp =
        mod
        |> translate_mod()
        |> struct(data)

      {tag, translated_resp}
    end

    defp translate_response({tag, %mod{} = response}, _request) when tag in [:ok, :error] do
      data = Map.from_struct(response)

      translated_resp =
        mod
        |> translate_mod()
        |> struct(data)

      {tag, translated_resp}
    end

    defp translate_mod(HTTPoison.AsyncResponse), do: HTTPClient.Response
    defp translate_mod(HTTPoison.Response), do: HTTPClient.Response
    defp translate_mod(HTTPoison.MaybeRedirect), do: HTTPClient.MaybeRedirect
    defp translate_mod(HTTPoison.Error), do: HTTPClient.Error

    @impl HTTPClient
    def request_stream(%HTTPClient.Request{options: options} = req) do
      case request(%{req | options: Keyword.put(options, :stream_to, self())}) do
        {:ok, _} ->
          {:ok,
           Stream.unfold(nil, fn _ ->
             receive do
               %HTTPoison.AsyncStatus{code: code} ->
                 {{:status, code}, nil}

               %HTTPoison.AsyncHeaders{headers: headers} ->
                 {{:headers, headers}, nil}

               %HTTPoison.AsyncChunk{chunk: chunk} ->
                 {{:chunk, chunk}, nil}

               %HTTPoison.Error{reason: reason} ->
                 {{:error, %HTTPClient.Error{reason: reason}}, nil}

               %HTTPoison.AsyncEnd{} ->
                 nil
             end
           end)}

        {:error, _} = error ->
          error
      end
    end
  end
end
