defmodule ReverseProxyBufferTest do
  use ExUnit.Case
  use Plug.Test

  import Mox

  defp get_buffer_response(status \\ 200, headers \\ [], body \\ "Success") do
    {:ok, %HTTPoison.Response{body: body, headers: headers, status_code: status}}
  end

  defp default_buffer_response do
    get_buffer_response().(nil, nil, nil)
  end

end
