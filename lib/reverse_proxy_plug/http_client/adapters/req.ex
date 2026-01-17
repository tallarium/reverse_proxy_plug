if Code.ensure_loaded?(Req) do
  defmodule ReverseProxyPlug.HTTPClient.Adapters.Req do
    @moduledoc """
    Req adapter for the `ReverseProxyPlug.HTTPClient` behaviour

    Buffer resposne mode is supported for all Req versions.

    Stream response mode is supported for Req 0.5.0 and up, when using
    the Finch adapter.

    See the [Req documentation](https://hexdocs.pm/req/Req.html#new/1) for client-specific options.
    """

    alias ReverseProxyPlug.HTTPClient

    @behaviour HTTPClient

    @minimum_req_version_for_merge Version.parse!("0.4.0")
    @minimum_req_version_for_stream Version.parse!("0.5.0")
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
      def request_stream(%HTTPClient.Request{
            method: method,
            url: url,
            headers: headers,
            body: body,
            options: options
          }) do
        headers = List.keydelete(headers, "accept-encoding", 0)

        case Req.new(
               method: method,
               url: url,
               headers: headers,
               body: body,
               retry: false,
               raw: true,
               compressed: false
             )
             |> merge_options(options)
             |> Req.request(into: :self) do
          {:ok, %{status: status, headers: resp_headers, body: %Req.Response.Async{ref: ref}}} ->
            {:ok,
             Stream.concat(
               [
                 {:status, status},
                 {:headers, normalize_headers(resp_headers)}
               ],
               body_stream(ref)
             )}

          {:error, exception} ->
            reason = Map.get(exception, :reason, exception)
            {:error, %HTTPClient.Error{reason: reason}}
        end
      end

      defp body_stream(ref) do
        Stream.resource(
          fn -> nil end,
          fn acc ->
            receive do
              {^ref, {:data, data}} -> {[{:chunk, data}], acc}
              {^ref, :done} -> {:halt, acc}
            end
          end,
          fn _ -> nil end
        )
      end
    end

    defp normalize_headers(headers) do
      Enum.flat_map(headers, fn
        {"set-cookie", values} when is_list(values) ->
          Enum.map(values, &{"set-cookie", &1})

        {"set-cookie", value} ->
          [{"set-cookie", value}]

        {k, v} ->
          [{k, v |> List.wrap() |> Enum.join(", ")}]
      end)
    end
  end
end
