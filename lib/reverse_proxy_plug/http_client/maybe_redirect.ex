defmodule ReverseProxyPlug.HTTPClient.MaybeRedirect do
  @moduledoc """
  If the option `:follow_redirect` is given to a request, HTTP redirects are automatically follow if
  the method is set to `:get` or `:head` and the response's `status_code` is `301`, `302` or `307`.

  If the method is set to `:post`, then the only `status_code` that get's automatically
  followed is `303`.

  If any other method or `status_code` is returned, then this struct is returned in place of a
  `ReverseProxyPlug.HTTPClient.Response` or `ReverseProxyPlug.HTTPClient.AsyncResponse`, containing the `redirect_url` to allow you
  to optionally re-request with the method set to `:get`.
  """

  defstruct status_code: nil, request_url: nil, request: nil, redirect_url: nil, headers: []

  alias ReverseProxyPlug.HTTPClient

  @type t :: %__MODULE__{
          status_code: integer,
          headers: list,
          request: HTTPClient.Request.t(),
          request_url: HTTPClient.Request.url(),
          redirect_url: HTTPClient.Request.url()
        }
end
