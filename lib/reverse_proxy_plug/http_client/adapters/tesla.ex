if Code.ensure_loaded?(Tesla) do
  defmodule ReverseProxyPlug.HTTPClient.Adapters.Tesla do
    @moduledoc """
    Tesla adapter for the `ReverseProxyPlug.HTTPClient` behaviour

    Buffer response mode is supported for all Tesla versions.

    Stream response mode is supported for Tesla 1.9.0 and up when using
    the Finch adapter.

    ## Options

    * `:tesla_client` - mandatory definition for the `Tesla.Client`
                        to be used.
    """

    alias ReverseProxyPlug.HTTPClient

    @behaviour HTTPClient

    @minimum_tesla_version_for_stream Version.parse!("1.9.0")
    @tesla_version Application.spec(:tesla, :vsn) |> to_string() |> Version.parse!()

    @impl HTTPClient
    def request(%HTTPClient.Request{options: options} = request) do
      {client, opts} = Keyword.pop(options, :tesla_client)

      unless client do
        raise ":tesla_client option is required"
      end

      query =
        if is_map(request.query_params),
          do: Map.to_list(request.query_params),
          else: request.query_params

      tesla_opts =
        request
        |> Map.take([:url, :method, :body, :headers])
        |> Map.put(:query, query)
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

    if Version.compare(@tesla_version, @minimum_tesla_version_for_stream) in [:gt, :eq] do
      @impl HTTPClient
      def request_stream(%HTTPClient.Request{options: options} = req) do
        case request(%{req | options: Keyword.merge(options, adapter: [response: :stream])}) do
          {:ok, %HTTPClient.Response{status_code: status_code, headers: headers, body: body}} ->
            {:ok,
             Stream.concat(
               [
                 {:status, status_code},
                 {:headers, headers}
               ],
               Stream.map(body, &{:chunk, &1})
             )}

          {:error, _} = error ->
            error
        end
      end
    end
  end
end
