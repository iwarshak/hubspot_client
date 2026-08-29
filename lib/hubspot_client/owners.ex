defmodule HubspotClient.Owners do
  @moduledoc """
  Read access to owners — the HubSpot users records can be assigned to.

  A record's `hubspot_owner_id` property holds an owner ID; join it against this
  list to get a name or email.

  Unlike pipelines and properties, this endpoint paginates, so `list/2` returns
  the `%{results: ..., after: ...}` envelope.
  """

  alias HubspotClient.{Request, Response}

  @param_keys [:limit, :after, :archived, :email]

  @doc """
  Lists one page of owners.

  ## Options

    * `:limit` - records per page.
    * `:after` - paging cursor from a previous call.
    * `:archived` - `true` to list deactivated owners.
    * `:email` - filter to the owner with this email address.
  """
  @spec list(HubspotClient.t(), keyword()) ::
          {:ok, %{results: list(map()), after: String.t() | nil}} | {:error, Exception.t()}
  def list(client, opts \\ []) do
    with {:ok, body} <- Request.get(client, "/crm/v3/owners", params(opts)) do
      {:ok, Response.paged(body, &Response.metadata/1)}
    end
  end

  @doc """
  Reads a single owner by ID.
  """
  @spec get(HubspotClient.t(), String.t() | integer(), keyword()) ::
          {:ok, map()} | {:error, Exception.t()}
  def get(client, owner_id, opts \\ []) do
    path = "/crm/v3/owners/" <> (owner_id |> to_string() |> URI.encode(&URI.char_unreserved?/1))

    with {:ok, body} <- Request.get(client, path, params(opts)) do
      {:ok, Response.metadata(body)}
    end
  end

  defp params(opts) do
    opts
    |> Keyword.take(@param_keys)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end
end
