defmodule ReverseProxyPlug.HTTPClient do
  @moduledoc """
  Behaviour defining the HTTP client interface needed for reverse proxying.
  """
  @callback request(atom, binary, term, HTTPoison.Base.headers(), HTTPoison.Base.options()) :: nil
end
