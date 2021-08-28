defmodule ReverseProxyPlug.HTTPClient do
  @moduledoc """
  Behaviour defining the HTTP client interface needed for reverse proxying.
  """
  @type error :: __MODULE__.Error.t()

  @callback request(__MODULE__.Request.t()) ::
              {:ok,
               __MODULE__.Response.t()
               | __MODULE__.AsyncResponse.t()
               | __MODULE__.MaybeRedirect.t()}
              | {:error, error()}

  if !Code.ensure_loaded?(HTTPoison) && !Code.ensure_loaded?(Tesla),
    do: raise("Either http_poison or tesla must be available")
end
