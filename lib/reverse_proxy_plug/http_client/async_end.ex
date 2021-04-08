defmodule ReverseProxyPlug.HTTPClient.AsyncEnd do
  defstruct id: nil
  @type t :: %__MODULE__{id: reference}
end
