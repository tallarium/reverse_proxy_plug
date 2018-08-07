# ReverseProxyPlug

A reverse proxy plug for proxying a request to another URL using [HTTPoison](https://github.com/edgurgel/httpoison).
Perfect when you need to transparently proxy requests to another service but
also need to have full programmatic control over the outgoing requests.

This project grew out of a fork of
[elixir-reverse-proxy](https://github.com/slogsdon/elixir-reverse-proxy).
Advantages over the original include more flexible upstreams, zero-delay
chunked transfer encoding support, HTTP2 support with Cowboy 2 and focus on
being a composable Plug instead of providing a standalone reverse proxy
application.

## Installation

Add `reverse_proxy_plug` to your list of dependencies in `mix.exs`:
```elixir
def deps do
  [
    {:reverse_proxy_plug, "~> 0.1.0"}
  ]
end
```

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

In general, the `:upstream` option should be a well formed URI parseable by
[`URI.parse/1`](https://hexdocs.pm/elixir/URI.html#parse/1).

## Chunked transfer encoding

`ReverseProxyPlug` supports chunked transfer encoding and by default the
responses are not buffered. This means that when a proxied server starts a
chunk transfer encoded response, `ReverseProxyPlug` will pass chunks back
to the client as soon as they arrive, resulting in zero delay.

Currently `ReverseProxyPlug` chunk transfer encodes all its responses, to
support this behaviour.

## License

ReverseProxyPlug is released under the MIT License.
