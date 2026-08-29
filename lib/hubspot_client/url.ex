defmodule HubspotClient.URL do
  @moduledoc false

  # Object types, record IDs, pipeline IDs, and property names all reach the URL
  # through here, so a value containing a slash or a space cannot re-shape the
  # path it is spliced into.
  @spec segment(String.t() | integer()) :: String.t()
  def segment(value), do: value |> to_string() |> URI.encode(&URI.char_unreserved?/1)
end
