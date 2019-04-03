defmodule TestReuse do
  @default_opts upstream: "example.com", client: ReverseProxyPlug.HTTPClientMock

  defmacro test_stream_and_buffer(message, body) do
    quote do
      test unquote(message) <> " (buffer)" do
        var!(test_reuse_opts) = %{
          opts: [response_mode: :buffer] ++ unquote(@default_opts),
          get_responder: fn status, body, headers ->
            fn _method, _url, _body, _headers, _options ->
              {:ok, %HTTPoison.Response{body: body, headers: headers, status_code: status}}
            end
          end
        }

        unquote(body)
      end

      test unquote(message) <> " (stream)" do
        var!(test_reuse_opts) = %{
          opts: [response_mode: :stream] ++ unquote(@default_opts),
          get_responder: fn status, body, headers ->
            fn _method, _url, _body, _headers, _options ->
              send(self(), %HTTPoison.AsyncStatus{code: status})
              send(self(), %HTTPoison.AsyncHeaders{headers: headers})

              body
              |> String.codepoints()
              |> Enum.chunk_every(body |> String.length() |> div(1))
              |> Enum.map(&Enum.join/1)
              |> Enum.each(fn chunk ->
                send(self(), %HTTPoison.AsyncChunk{chunk: chunk})
              end)

              send(self(), %HTTPoison.AsyncEnd{})
              {:ok, nil}
            end
          end
        }

        unquote(body)
      end
    end
  end
end
