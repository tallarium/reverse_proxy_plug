defmodule ReverseProxyPlug.HTTPClient.AsyncChunk do
  defstruct id: nil, chunk: nil
  @type t :: %__MODULE__{id: reference, chunk: binary}
end
