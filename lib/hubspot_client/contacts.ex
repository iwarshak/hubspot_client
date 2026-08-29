defmodule HubspotClient.Contacts do
  @moduledoc """
  Read access to contacts.

  A thin delegation to `HubspotClient.Objects` with the `"contacts"` object
  type applied. See that module for the full option list.
  """

  alias HubspotClient.Objects

  @type_name "contacts"

  @doc "Lists one page of contacts. See `HubspotClient.Objects.list/3`."
  def list(client, opts \\ []), do: Objects.list(client, @type_name, opts)

  @doc "Reads a single contact. See `HubspotClient.Objects.get/4`."
  def get(client, id, opts \\ []), do: Objects.get(client, @type_name, id, opts)

  @doc "Searches contacts. See `HubspotClient.Objects.search/3`."
  def search(client, query), do: Objects.search(client, @type_name, query)

  @doc "Batch reads contacts by ID. See `HubspotClient.Objects.batch_read/4`."
  def batch_read(client, ids, opts \\ []), do: Objects.batch_read(client, @type_name, ids, opts)

  @doc "Streams every contact. See `HubspotClient.Objects.stream/3`."
  def stream(client, opts \\ []), do: Objects.stream(client, @type_name, opts)
end
