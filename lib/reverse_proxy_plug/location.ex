defmodule ReverseProxyPlug.Location do
  @moduledoc """
  Helpers for rewriting the Location field
  """

  def rewrite_location_header(headers, status, opts) when status in [301, 302] do
    redirect_rules = Keyword.fetch!(opts, :redirect_rules)

    location =
      get_header(headers, "location")
      |> update_location(opts, redirect_rules)

    put_header(headers, "location", location)
  end

  def rewrite_location_header(headers, _, _), do: headers

  defp update_location(location, opts, []) do
    URI.parse(location) |> Map.put(:host, opts[:upstream]) |> to_string()
  end

  defp update_location(location, opts, [{pattern, replacement} | redirect_rules]) do
    if String.contains?(location, pattern) do
      String.replace(location, pattern, replacement)
    else
      update_location(location, opts, redirect_rules)
    end
  end

  defp get_header(headers, key),
    do: List.keyfind(headers, key, 0) |> then(fn {_, value} -> value end)

  defp put_header(headers, key, value), do: List.keyreplace(headers, key, 0, {key, value})
end
