defmodule HubspotClient.Associations do
  @moduledoc """
  Read the records associated with a record — a deal's companies, a company's
  contacts, a ticket's deals.

  This uses the v4 associations API, which returns the associated record's ID
  plus the association types, not the record itself. Fetch the records
  themselves with `HubspotClient.Objects.batch_read/4` on the returned IDs.

      {:ok, %{results: links}} =
        HubspotClient.Associations.list(client, "deals", deal_id, "companies")

      {:ok, companies} =
        HubspotClient.Companies.batch_read(client, Enum.map(links, & &1.to_object_id))

  For a small number of associated types, passing `:associations` to
  `HubspotClient.Objects.list/3` is one request instead of two.

  This endpoint paginates.
  """

  alias HubspotClient.{Request, Response}

  @param_keys [:limit, :after]

  @doc """
  Lists the associations from one record to an object type.

  ## Options

    * `:limit` - associations per page.
    * `:after` - paging cursor from a previous call.
  """
  @spec list(HubspotClient.t(), String.t(), String.t() | integer(), String.t(), keyword()) ::
          {:ok, %{results: list(map()), after: String.t() | nil}} | {:error, Exception.t()}
  def list(client, from_type, from_id, to_type, opts \\ []) do
    path =
      "/crm/v4/objects/" <>
        segment(from_type) <>
        "/" <> segment(from_id) <> "/associations/" <> segment(to_type)

    with {:ok, body} <- Request.get(client, path, params(opts)) do
      {:ok, Response.paged(body, &Response.metadata/1)}
    end
  end

  defp params(opts) do
    opts
    |> Keyword.take(@param_keys)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp segment(value), do: value |> to_string() |> URI.encode(&URI.char_unreserved?/1)
end
