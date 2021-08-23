defmodule ReverseProxyPlug.HTTPClient.Request do
  @moduledoc """
  `Request` properties:
    * `:method` - HTTP method as an atom (`:get`, `:head`, `:post`, `:put`,
      `:delete`, etc.)
    * `:url` - target url as a binary string or char list
    * `:body` - request body.
    * `:headers` - HTTP headers as an orddict (e.g., `[{"Accept", "application/json"}]`)
    * `:options` - Keyword list of options. Valid options vary with the HTTP client used.
    * `:query_params` - Query parameters as a map, keyword, or orddict

  The exact typing for each of the parameters depends on the adapter used.
  """
  @enforce_keys [:url]
  defstruct method: :get, url: nil, headers: [], body: "", query_params: %{}, options: []

  @type method :: :get | :post | :put | :patch | :delete | :options | :head
  @type headers :: [{atom, binary}] | [{binary, binary}] | %{binary => binary} | any
  @type url :: any()
  @type body :: any()
  @type query_params :: any()
  @type options :: any()

  @type t :: %__MODULE__{
          method: method,
          url: binary,
          headers: headers,
          body: body,
          query_params: query_params,
          options: options
        }
end
