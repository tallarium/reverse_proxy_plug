defmodule ReverseProxyPlug.HTTPClient.AsyncResponse do
  defstruct id: nil
  @type t :: %__MODULE__{id: reference | nil}
end
