defmodule ReverseProxyPlug.HTTPClient do
  @moduledoc """
  Behaviour defining the HTTP client interface needed for reverse proxying.
  """
  @type error :: __MODULE__.Error.t()

  @callback request(__MODULE__.Request.t()) ::
              {:ok,
               __MODULE__.Response.t()
               | __MODULE__.MaybeRedirect.t()}
              | {:error, error()}

  @callback request_stream(__MODULE__.Request.t()) :: {:ok, Enumerable.t()} | {:error, error()}

  @optional_callbacks request_stream: 1
end
