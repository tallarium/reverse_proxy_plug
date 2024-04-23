defmodule TestReuse do
  @moduledoc false
  @default_opts upstream: "example.com", client: ReverseProxyPlug.HTTPClientMock

  alias ReverseProxyPlug.HTTPClient

  def get_buffer_responder(response_args) do
    fn request ->
      {:ok, make_response(response_args, request)}
    end
  end

  def get_stream_responder(response_args) do
    fn request ->
      %{status_code: code, headers: headers, body: body} = make_response(response_args, request)

      body_chunks =
        body
        |> String.codepoints()
        |> Enum.chunk_every(body |> String.length() |> div(3))
        |> Enum.map(&Enum.join/1)
        |> Enum.map(&{:chunk, &1})

      {:ok,
       [
         {:status, code},
         {:headers, headers}
       ] ++ body_chunks}
    end
  end

  defmacro test_stream_and_buffer(message, body) do
    quote do
      test unquote(message) <> " (stream)" do
        var!(test_reuse_opts) = %{
          opts: [response_mode: :stream] ++ unquote(@default_opts),
          get_responder: &TestReuse.get_stream_responder/1,
          req_function: :request_stream
        }

        unquote(body)
      end

      test unquote(message) <> " (buffer)" do
        var!(test_reuse_opts) = %{
          opts: [response_mode: :buffer] ++ unquote(@default_opts),
          get_responder: &TestReuse.get_buffer_responder/1,
          req_function: :request
        }

        unquote(body)
      end
    end
  end

  def make_response(%{} = args, request) do
    %HTTPClient.Response{
      status_code: args[:status_code] || 200,
      headers: args[:headers] || [],
      body: args[:body] || "Success",
      request: request
    }
  end
end
