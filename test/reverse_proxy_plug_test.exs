defmodule ReverseProxyPlugTest do
  use ExUnit.Case
  doctest ReverseProxyPlug

  test "greets the world" do
    assert ReverseProxyPlug.hello() == :world
  end
end
