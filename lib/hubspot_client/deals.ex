defmodule HubspotClient.Deals do
  @moduledoc """
  Read access to deals.

  A thin delegation to `HubspotClient.Objects` with the `"deals"` object type
  applied. See that module for the full option list.

      {:ok, page} = HubspotClient.Deals.list(client, properties: ["dealname", "amount"])
  """

  alias HubspotClient.Objects

  @type_name "deals"

  @doc "Lists one page of deals. See `HubspotClient.Objects.list/3`."
  def list(client, opts \\ []), do: Objects.list(client, @type_name, opts)

  @doc "Reads a single deal. See `HubspotClient.Objects.get/4`."
  def get(client, id, opts \\ []), do: Objects.get(client, @type_name, id, opts)

  @doc "Searches deals. See `HubspotClient.Objects.search/3`."
  def search(client, query), do: Objects.search(client, @type_name, query)

  @doc "Batch reads deals by ID. See `HubspotClient.Objects.batch_read/4`."
  def batch_read(client, ids, opts \\ []), do: Objects.batch_read(client, @type_name, ids, opts)

  @doc "Streams every deal. See `HubspotClient.Objects.stream/3`."
  def stream(client, opts \\ []), do: Objects.stream(client, @type_name, opts)
end
