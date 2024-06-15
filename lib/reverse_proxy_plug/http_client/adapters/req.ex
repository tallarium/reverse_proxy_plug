if Code.ensure_loaded?(Req) do
  defmodule ReverseProxyPlug.HTTPClient.Adapters.Req do
    @moduledoc """
    Req adapter for the `ReverseProxyPlug.HTTPClient` behaviour

    Buffer resposne mode is supported for all Req versions.

    Stream response mode is supported for Req 0.4.0 and up, when using
    the Finch adapter.

    See the [Req documentation](https://hexdocs.pm/req/Req.html#new/1) for client-specific options.
    """

    alias ReverseProxyPlug.HTTPClient

    @behaviour HTTPClient

    @minimum_req_version_for_merge Version.parse!("0.4.0")
    @minimum_req_version_for_stream Version.parse!("0.4.0")
    @req_version Application.spec(:req, :vsn) |> to_string() |> Version.parse!()

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
      case Req.new(
             method: method,
             url: url,
             headers: headers,
             body: body,
             retry: false,
             raw: true
           )
           |> merge_options(options)
           |> Req.request() do
        {:ok, resp} ->
          {:ok,
           %HTTPClient.Response{
             status_code: resp.status,
             body: resp.body,
             headers: normalize_headers(resp.headers),
             request_url: url,
             request: request
           }}

        {:error, %{reason: reason}} ->
          {:error, %HTTPClient.Error{reason: reason}}
      end
    end

    if Version.compare(@req_version, @minimum_req_version_for_merge) in [:gt, :eq] do
      defp merge_options(request, options), do: Req.merge(request, options)
    else
      defp merge_options(request, options), do: Req.update(request, options)
    end

    if Version.compare(@req_version, @minimum_req_version_for_stream) in [:gt, :eq] do
      @impl HTTPClient
      def request_stream(%HTTPClient.Request{headers: headers, options: options} = req) do
        headers = List.keydelete(headers, "accept-encoding", 0)
        parent = self()

        options =
          Keyword.merge(options,
            # Versions >= 0.4.0 and < 0.4.12 specify a compressed body automatically, but
            # streaming decompression is not correctly handled.
            compressed: false,
            into: fn {:data, data}, {req, resp} ->
              send(parent, {:data, data})
              {:cont, {req, resp}}
            end
          )

        case async_request(%{req | headers: headers, options: options}, parent) do
          {:ok, %{status_code: status_code, headers: resp_headers}} ->
            {:ok,
             Stream.concat(
               [
                 {:status, status_code},
                 {:headers, normalize_headers(resp_headers)}
               ],
               body_stream()
             )}

          {:error, _} = error ->
            error
        end
      end

      defp async_request(req, parent) do
        fn ->
          ret = request(req)
          send(parent, :eof)
          ret
        end
        |> Task.async()
        |> Task.await()
      end

      defp body_stream do
        Stream.resource(
          fn -> nil end,
          fn acc ->
            receive do
              {:data, data} -> {[{:chunk, data}], acc}
              :eof -> {:halt, acc}
            end
          end,
          fn _ -> nil end
        )
      end
    end

    defp normalize_headers(headers) do
      Enum.map(headers, fn {k, v} -> {k, v |> List.wrap() |> Enum.join(", ")} end)
    end
  end
end
