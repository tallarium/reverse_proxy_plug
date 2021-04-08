defmodule ReverseProxyPlug.HTTPClient.AsyncStatus do
  defstruct id: nil, code: nil
  @type t :: %__MODULE__{id: reference, code: integer}
end
