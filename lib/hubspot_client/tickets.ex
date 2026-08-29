defmodule HubspotClient.Tickets do
  @moduledoc """
  Read access to tickets.

  A thin delegation to `HubspotClient.Objects` with the `"tickets"` object
  type applied. See that module for the full option list.

  Tickets use the legacy `tickets` scope rather than a `crm.objects.tickets.read`
  scope. If ticket calls return 403 while deals and companies work, that scope is
  the thing to check.
  """

  alias HubspotClient.Objects

  @type_name "tickets"

  @doc "Lists one page of tickets. See `HubspotClient.Objects.list/3`."
  def list(client, opts \\ []), do: Objects.list(client, @type_name, opts)

  @doc "Reads a single ticket. See `HubspotClient.Objects.get/4`."
  def get(client, id, opts \\ []), do: Objects.get(client, @type_name, id, opts)

  @doc "Searches tickets. See `HubspotClient.Objects.search/3`."
  def search(client, query), do: Objects.search(client, @type_name, query)

  @doc "Batch reads tickets by ID. See `HubspotClient.Objects.batch_read/4`."
  def batch_read(client, ids, opts \\ []), do: Objects.batch_read(client, @type_name, ids, opts)

  @doc "Streams every ticket. See `HubspotClient.Objects.stream/3`."
  def stream(client, opts \\ []), do: Objects.stream(client, @type_name, opts)
end
