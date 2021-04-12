defmodule TestReuse do
  @moduledoc false
  @default_opts upstream: "example.com", client: ReverseProxyPlug.HTTPClientMock

  alias ReverseProxyPlug.HTTPClient

  def get_buffer_responder(response_args) do
    fn _request ->
      {:ok, make_response(response_args)}
    end
  end

  def get_stream_responder(response_args) do
    %{status_code: code, headers: headers, body: body} = make_response(response_args)

    fn _request ->
      send(self(), %HTTPoison.AsyncStatus{code: code})
      send(self(), %HTTPoison.AsyncHeaders{headers: headers})

      body
      |> String.codepoints()
      |> Enum.chunk_every(body |> String.length() |> div(3))
      |> Enum.map(&Enum.join/1)
      |> Enum.each(fn chunk ->
        send(self(), %HTTPoison.AsyncChunk{chunk: chunk})
      end)

      send(self(), %HTTPoison.AsyncEnd{})
      {:ok, nil}
    end
  end

  defmacro test_stream_and_buffer(message, body) do
    quote do
      test unquote(message) <> " (stream)" do
        var!(test_reuse_opts) = %{
          opts: [response_mode: :stream] ++ unquote(@default_opts),
          get_responder: &TestReuse.get_stream_responder/1
        }

        unquote(body)
      end

      test unquote(message) <> " (buffer)" do
        var!(test_reuse_opts) = %{
          opts: [response_mode: :buffer] ++ unquote(@default_opts),
          get_responder: &TestReuse.get_buffer_responder/1
        }

        unquote(body)
      end
    end
  end

  defp make_response(%{} = args) do
    %HTTPClient.Response{
      status_code: args[:status_code] || 200,
      headers: args[:headers] || [],
      body: args[:body] || "Success"
    }
  end
end
