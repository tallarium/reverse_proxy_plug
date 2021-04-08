defmodule ReverseProxyPlug.HTTPClient.AsyncHeaders do
  defstruct id: nil, headers: []
  @type t :: %__MODULE__{id: reference, headers: list}
end
