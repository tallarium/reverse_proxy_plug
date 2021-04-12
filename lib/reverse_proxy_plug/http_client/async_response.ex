defmodule ReverseProxyPlug.HTTPClient.AsyncResponse do
  @moduledoc "Carries the reference to be used for parsing an asynchronous response"
  defstruct id: nil
  @type t :: %__MODULE__{id: reference | nil}
end
