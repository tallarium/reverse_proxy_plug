defmodule ReverseProxyTest do
  use ExUnit.Case

  test "greets the world" do
    ReverseProxy.call("a", upstream: "someupstream")
    assert 1 == 1
  end
end
