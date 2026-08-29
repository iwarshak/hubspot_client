defmodule HubspotClient.Companies do
  @moduledoc """
  Read access to companies.

  A thin delegation to `HubspotClient.Objects` with the `"companies"` object
  type applied. See that module for the full option list.
  """

  alias HubspotClient.Objects

  @type_name "companies"

  @doc "Lists one page of companies. See `HubspotClient.Objects.list/3`."
  def list(client, opts \\ []), do: Objects.list(client, @type_name, opts)

  @doc "Reads a single company. See `HubspotClient.Objects.get/4`."
  def get(client, id, opts \\ []), do: Objects.get(client, @type_name, id, opts)

  @doc "Searches companies. See `HubspotClient.Objects.search/3`."
  def search(client, query), do: Objects.search(client, @type_name, query)

  @doc "Batch reads companies by ID. See `HubspotClient.Objects.batch_read/4`."
  def batch_read(client, ids, opts \\ []), do: Objects.batch_read(client, @type_name, ids, opts)

  @doc "Streams every company. See `HubspotClient.Objects.stream/3`."
  def stream(client, opts \\ []), do: Objects.stream(client, @type_name, opts)
end
