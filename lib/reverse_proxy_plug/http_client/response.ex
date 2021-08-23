defmodule ReverseProxyPlug.HTTPClient.Response do
  @moduledoc """
  HTTP Client response model
  """
  defstruct status_code: nil,
            body: nil,
            headers: [],
            request_url: nil,
            request: nil

  @type t :: %__MODULE__{
          status_code: integer,
          body: term,
          headers: list,
          request: ReverseProxyPlug.HTTPClient.Request.t(),
          request_url: ReverseProxyPlug.HTTPClient.Request.url()
        }
end
