defmodule ReverseProxy.HTTPClient do
  @callback request(atom, binary, term, HTTPoison.Base.headers(), HTTPoison.Base.options()) :: nil
end
