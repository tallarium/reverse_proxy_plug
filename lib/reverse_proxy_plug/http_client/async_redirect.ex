defmodule ReverseProxyPlug.HTTPClient.AsyncRedirect do
  defstruct id: nil, to: nil, headers: []
  @type t :: %__MODULE__{id: reference, to: String.t(), headers: list}
end
