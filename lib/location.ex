defmodule Location do
  @moduledoc """
  Helpers for rewriting the Location field
  """

  def rewrite_location_header(headers, status, opts) when status in [301, 302] do
    redirect_rules = Keyword.fetch!(opts, :redirect_rules)

    location =
      get_header(headers, "location")
      |> update_location(redirect_rules)

    put_header(headers, "location", location)
  end

  def rewrite_location_header(headers, _, _) do
    headers
  end

  defp update_location(location, []) do
    location
  end

  defp update_location(location, [rule | redirect_rules]) do
    {pattern, replacement} = rule

    if String.contains?(location, "//" <> pattern) do
      String.replace(location, "//" <> pattern, "//" <> replacement)
    else
      update_location(location, redirect_rules)
    end
  end

  defp get_header(headers, key) do
    headers
    |> Enum.filter(fn {k, _} -> k == key end)
    |> hd
    |> elem(1)
  end

  defp put_header(headers, key, value) do
    headers
    |> Enum.filter(fn {k, _} -> k != key end)
    |> List.insert_at(0, {key, value})
  end
end
