# ReverseProxyPlug

[![Module Version](https://img.shields.io/hexpm/v/reverse_proxy_plug.svg)](https://hex.pm/packages/reverse_proxy_plug)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/reverse_proxy_plug/)
[![Total Download](https://img.shields.io/hexpm/dt/reverse_proxy_plug.svg)](https://hex.pm/packages/reverse_proxy_plug)
[![License](https://img.shields.io/hexpm/l/reverse_proxy_plug.svg)](https://github.com/tallarium/reverse_proxy_plug/blob/master/LICENSE.md)
[![Last Updated](https://img.shields.io/github/last-commit/tallarium/reverse_proxy_plug.svg)](https://github.com/tallarium/reverse_proxy_plug/commits/master)

A reverse proxy plug for proxying a request to another URL using a choice of
Elixir HTTP client libraries. Perfect when you need to transparently proxy
requests to another service but also need to have full programmatic control
over the outgoing requests.

This project grew out of a fork of
[elixir-reverse-proxy](https://github.com/slogsdon/elixir-reverse-proxy).
Advantages over the original include more flexible upstreams, zero-delay
chunked transfer encoding support, HTTP2 support with Cowboy 2, several options
for HTTP client libraries and focus on being a composable Plug instead of
providing a standalone reverse proxy application.

## Installation

Add `reverse_proxy_plug` to your list of dependencies in `mix.exs`:
```elixir
def deps do
  [
    {:reverse_proxy_plug, "~> 3.0"}
  ]
end
```

Then add an HTTP client library, one of:
- [HTTPoison](https://hex.pm/packages/httpoison)
- [Tesla](https://hex.pm/packages/tesla)
- [Finch](https://hex.pm/packages/finch)
- [Req](https://hex.pm/packages/req)

and configure depending on your choice, e.g.:

```elixir
config :reverse_proxy_plug, :http_client, ReverseProxyPlug.HTTPClient.Adapters.HTTPoison
```

You can also set the config as a per-plug basis, which will override any global config.

```elixir
plug ReverseProxyPlug, client: ReverseProxyPlug.HTTPClient.Adapters.Tesla
```

Either of those must be set, otherwise the system will attempt to default to the HTTPoison
adapter or raise if it's not present.

## Usage

The plug works best when used with
[`Plug.Router.forward/2`](https://hexdocs.pm/plug/Plug.Router.html#forward/2).
Drop this line into your Plug router:

```elixir
forward("/foo", to: ReverseProxyPlug, upstream: "//example.com/bar")
```

Now all requests matching `/foo` will be proxied to the upstream. For
example, a request to `/foo/baz` made over HTTP will result in a request to
`http://example.com/bar/baz`.

You can also specify the scheme or choose a port:
```elixir
forward("/foo", to: ReverseProxyPlug, upstream: "https://example.com:4200/bar")
```

The `:upstream` option should be a well formed URI parseable by [`URI.parse/1`](https://hexdocs.pm/elixir/URI.html#parse/1),
or a function with zero or one arity which returns one. If it is a function, it will be
evaluated for every request. If the function is arity one, the `Conn` struct will be
passed to it, in order to have more flexibility in dynamic routing.

### Modifying the client request body

You can modify various aspects of the client request by simply modifying the
`Conn` struct. In case you want to modify the request body, fetch it using
`Conn.read_body/2`, make your changes, and leave it under
`Conn.assigns[:raw_body]`. ReverseProxyPlug will use that as the request body.
In case a custom raw body is not present, ReverseProxyPlug will fetch it from
the `Conn` struct directly.

## Configuration options

### Custom HTTP methods

Only standard HTTP methods in "GET", "HEAD", "POST", "PUT", "DELETE", "CONNECT", "OPTIONS",
"TRACE" and "PATCH" will be forwarded by default. You can specific define other custom
HTTP methods in keyword :custom_http_methods.

```elixir
forward("/foo", to: ReverseProxyPlug, upstream: "//example.com/bar", custom_http_methods: [:XMETHOD])
```

### Preserve host header

A reverse HTTP proxy often has to preserve the original `Host` request header
when making a request to the upstream origin. Presenting a different `Host` to
the upstream server can lead to issues related to cookies, redirects, and
incorrect routing that can become a security concern.

Some HTTP proxies send the original `Host` value in other headers, like
`Forwarded` or `X-Forwarded-Host`, but those are only useful if the upstream
application is coded to read those headers.

By default, ReverseProxyPlug does not preserve the original header nor does it
send the original header in any other form. Use `:preserve_host_header` to make
upstream requests with the same `Host` header as in the original request.

```elixir
forward("/foo", to: ReverseProxyPlug, upstream: "//example.com", preserve_host_header: true)
```

### Normalize headers for upstream request

An upstream request will downcase all request header names by default (`ReverseProxyPlug.downcase_headers/1`)

You can override this behaviour by passing your own `normalize_headers/1`, which can transform
a list of headers - a list of `{"header", "value"}` tuples - and return them in the form desired.
For instance, you may want to drop certain headers in the upstream request, beyond the usual hop-by-hop
headers.

### Response mode

`ReverseProxyPlug` supports two response modes:

- `:stream` (default) - The response from the plug will always be chunk
encoded. If the upstream server sends a chunked response, ReverseProxyPlug
will pass chunks to the clients as soon as they arrive, resulting in zero
delay. Not all adapters support the `:stream` response mode currently.

- `:buffer` - The plug will wait until the whole response is received from
the upstream server, at which point it will send it to the client using
`Conn.send_resp`. This allows for processing the response before sending it
back using `Conn.register_before_send`.

You can choose the response mode by passing a `:response_mode` option:
```elixir
forward("/foo", to: ReverseProxyPlug, response_mode: :buffer, upstream: "//example.com/bar")
```

### Response header processing mode

You can specify the behaviour of how headers from the upstream response are incorporated
into the response that is sent from `reverse_proxy_plug`:
- `:replace` - use `Conn.put_resp_header` to overwrite any existing headers present
- `:prepend` - use `Conn.prepend_resp_header` to prepend headers from the upstream to existing
response headers in `conn`.

The defaults differ per response mode - `:stream_headers_mode` defaults to `:replace`, `:buffer_headers_mode`
to `:prepend`.

### Client options

You can pass options to the configured HTTP client. Valid options depend on the HTTP client used.

```elixir
forward("/foo", to: ReverseProxyPlug, upstream: "//example.com", client_options: [timeout: 2000])
```

### Callback for connection errors

By default, `ReverseProxyPlug` will automatically respond with 502 Bad Gateway
in case of network error. To inspect the HTTPoison error that caused the
response, you can pass an `:error_callback` option.

```elixir
plug(ReverseProxyPlug,
  upstream: "example.com",
  error_callback: fn error -> Logger.error("Network error: #{inspect(error)}") end
)
```

If you wish to handle the response directly, you can provide a function with
arity 2 where the connection will be passed as the second argument:

```elixir
plug(ReverseProxyPlug,
  upstream: "example.com",
  error_callback: fn error, conn ->
    Logger.error("Network error: #{inspect(error)}")
    Plug.Conn.send_resp(conn, :internal_server_error, "something went wrong")
  end)
)
```

You can also provide a MFA (module, function, arguments) tuple, to which the
error will be inserted as the last argument:

```elixir
plug(ReverseProxyPlug,
  upstream: "example.com",
  error_callback: {MyErrorHandler, :handle_proxy_error, ["example.com"]}
)
```

If the function specified by the MFA tuple supports two additional arguments,
the error and connection will inserted as the last two arguments, respectively.

### Callbacks for responses in streaming mode

In order to add special handling for responses with particular statuses instead
of passing them on to the client as usual, provide the `:status_callbacks`
option with a map from status code to handler:

```elixir
plug(ReverseProxyPlug,
  upstream: "example.com",
  status_callbacks: %{404 => &handle_404/2}
)
```

The handler is called as soon as an `HTTPoison.AsyncStatus` message with the
given status is received, taking the `Plug.Conn` and the options given to
`ReverseProxyPlug`. It must then consume all the remaining incoming HTTPoison
asynchronous response parts, respond to the client and return the `Plug.Conn`.

`:status_callbacks` must only be given when `:response_mode` is `:stream`,
which is the default.

## Usage in Phoenix

The Phoenix default autogenerated project assumes that you'll want to
parse all request bodies coming to your Phoenix server and puts `Plug.Parsers`
directly in your `endpoint.ex`. If you're using something like ReverseProxyPlug,
this is likely not what you want — in this case you'll want to move Plug.Parsers
out of your endpoint and into specific router pipelines or routes themselves.

Or you can extract the raw request body with a
[custom body reader](https://hexdocs.pm/plug/1.6.0/Plug.Parsers.html#module-custom-body-reader)
in your `endpoint.ex`:
```elixir
plug Plug.Parsers,
  body_reader: {CacheBodyReader, :read_body, []},
  # ...
```
and store it in the `Conn` struct with custom plug `cache_body_reader.ex`:
```elixir
defmodule CacheBodyReader do
  @moduledoc """
  Inspired by https://hexdocs.pm/plug/1.6.0/Plug.Parsers.html#module-custom-body-reader
  """

  alias Plug.Conn

  @doc """
  Read the raw body and store it for later use in the connection.
  It ignores the updated connection returned by `Plug.Conn.read_body/2` to not break CSRF.
  """
  @spec read_body(Conn.t(), Plug.opts()) :: {:ok, String.t(), Conn.t()}
  def read_body(%Conn{request_path: "/api/" <> _} = conn, opts) do
    {:ok, body, _conn} = Conn.read_body(conn, opts)
    conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])
    {:ok, body, conn}
  end

  def read_body(conn, opts), do: Conn.read_body(conn, opts)
end
```
which then allows you to use the [Phoenix.Router.forward/4](https://hexdocs.pm/phoenix/Phoenix.Router.html#forward/4)
in the `router.ex`:
```elixir
  scope "/api" do
    pipe_through :api

    forward "/foo", ReverseProxyPlug,
      upstream: &Settings.foo_url/0,
      error_callback: &__MODULE__.log_reverse_proxy_error/1

    def log_reverse_proxy_error(error) do
      Logger.warn("ReverseProxyPlug network error: #{inspect(error)}")
    end
  end
```

## Copyright and License

Copyright (c) 2018 Tallarium Technologies

ReverseProxyPlug is released under the [MIT License](./LICENSE.md).
