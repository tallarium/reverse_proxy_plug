defmodule ReverseProxyPlug.HTTPClient.Error do
  defexception reason: nil, id: nil
  @type t :: %__MODULE__{id: reference | nil, reason: any}

  def message(%__MODULE__{reason: reason, id: nil}), do: inspect(reason)
  def message(%__MODULE__{reason: reason, id: id}), do: "[Reference: #{id}] - #{inspect(reason)}"
end
