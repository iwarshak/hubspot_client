defmodule HubspotClient.Objects do
  @moduledoc """
  Read access to any HubSpot CRM object type.

  HubSpot's object API is uniform, so one module covers `deals`, `companies`,
  `contacts`, `tickets`, `line_items`, `products`, `quotes`, and custom object
  types such as `"p12345_widget"`.

  The per-resource modules (`HubspotClient.Deals` and friends) are thin
  delegations to this module and exist for discoverability. Use this module
  directly for custom objects.

  ## Options

    * `:limit` - records per page. HubSpot defaults to 10 and caps list
      endpoints at 100.
    * `:after` - the paging cursor from a previous call.
    * `:properties` - list of property names to return. HubSpot returns a small
      default set when this is omitted, which often will not include the fields
      you want; ask for them explicitly.
    * `:properties_with_history` - list of property names to return with history.
    * `:associations` - list of object types to return associated IDs for.
    * `:archived` - `true` to return archived records instead of active ones.

  Unrecognized options are ignored rather than forwarded.
  """

  alias HubspotClient.{Request, Response}

  @param_keys [:limit, :after, :properties, :properties_with_history, :associations, :archived]

  @doc """
  Lists one page of objects.
  """
  @spec list(HubspotClient.t(), String.t(), keyword()) ::
          {:ok, %{results: list(map()), after: String.t() | nil}} | {:error, Exception.t()}
  def list(client, type, opts \\ []) do
    with {:ok, body} <- Request.get(client, base_path(type), params(opts)) do
      {:ok, Response.paged(body, &Response.object/1)}
    end
  end

  @doc """
  Reads a single object by ID.
  """
  @spec get(HubspotClient.t(), String.t(), String.t() | integer(), keyword()) ::
          {:ok, map()} | {:error, Exception.t()}
  def get(client, type, id, opts \\ []) do
    with {:ok, body} <- Request.get(client, base_path(type) <> "/" <> segment(id), params(opts)) do
      {:ok, Response.object(body)}
    end
  end

  @doc false
  def base_path(type), do: "/crm/v3/objects/" <> segment(type)

  @doc false
  def params(opts) do
    opts
    |> Keyword.take(@param_keys)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map(&encode_param/1)
  end

  defp encode_param({:properties_with_history, value}), do: {:propertiesWithHistory, join(value)}
  defp encode_param({key, value}), do: {key, join(value)}

  defp join(value) when is_list(value), do: Enum.join(value, ",")
  defp join(value), do: value

  defp segment(value) do
    value |> to_string() |> URI.encode(&URI.char_unreserved?/1)
  end
end
