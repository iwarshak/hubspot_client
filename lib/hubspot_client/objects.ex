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

  alias HubspotClient.{Request, Response, URL}

  @param_keys [:limit, :after, :properties, :properties_with_history, :associations, :archived]
  @stream_page_size 100

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
    with {:ok, body} <-
           Request.get(client, base_path(type) <> "/" <> URL.segment(id), params(opts)) do
      {:ok, Response.object(body)}
    end
  end

  @doc """
  Searches objects.

  The query is passed to HubSpot unchanged, so it accepts the full search body:
  `"filterGroups"`, `"sorts"`, `"query"`, `"properties"`, `"limit"`, `"after"`.

  HubSpot's constraints, which this function does not paper over:

    * at most 200 records per page,
    * at most 10,000 total results per query — paging past it returns a 400,
    * at most 5 filterGroups with 6 filters each, 18 filters total,
    * a request body of at most 3,000 characters,
    * a shared burst limit of 5 requests per second across all search endpoints,
      which is far tighter than the general limit. A 429 here means that one.
  """
  @spec search(HubspotClient.t(), String.t(), map()) ::
          {:ok, %{results: list(map()), after: String.t() | nil}} | {:error, Exception.t()}
  def search(client, type, query) when is_map(query) do
    with {:ok, body} <- Request.post(client, base_path(type) <> "/search", query) do
      {:ok, Response.paged(body, &Response.object/1)}
    end
  end

  @doc """
  Reads up to 100 objects by ID in one request.

  Returns a plain list — the batch endpoint does not paginate. It also cannot
  return associations; use `get/4` or `HubspotClient.Associations.list/5` for
  those.

  ## Options

    * `:properties` - list of property names to return. Defaults to `[]`.
    * `:id_property` - read by a custom unique property instead of the record ID.
  """
  @spec batch_read(HubspotClient.t(), String.t(), [String.t() | integer()], keyword()) ::
          {:ok, list(map())} | {:error, Exception.t()}
  def batch_read(client, type, ids, opts \\ []) when is_list(ids) do
    body =
      %{
        "inputs" => Enum.map(ids, fn id -> %{"id" => to_string(id)} end),
        "properties" => Keyword.get(opts, :properties, [])
      }
      |> maybe_put("idProperty", Keyword.get(opts, :id_property))

    with {:ok, response} <- Request.post(client, base_path(type) <> "/batch/read", body) do
      {:ok, Response.collection(response, &Response.object/1)}
    end
  end

  @doc """
  Streams every object, following paging cursors until they run out.

  The stream is lazy, so `Enum.take(stream, 250)` issues three requests and
  stops. `:limit` defaults to #{@stream_page_size}, HubSpot's maximum for list
  endpoints, because the API's own default of 10 would multiply the request
  count tenfold.

  Unlike every other function here, this one **raises** — `HubspotClient.Error`
  on an API error, `Req.TransportError` on a network failure. A stream cannot
  yield `{:error, reason}` without forcing every consumer to pattern-match each
  element, which would make the common case worse to serve the rare one.

      client
      |> HubspotClient.Objects.stream("deals", properties: ["dealname", "amount"])
      |> Stream.map(& &1.properties["dealname"])
      |> Enum.take(500)
  """
  @spec stream(HubspotClient.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, type, opts \\ []) do
    opts = Keyword.put_new(opts, :limit, @stream_page_size)

    Stream.resource(
      fn -> :first_page end,
      fn
        :done ->
          {:halt, :done}

        cursor ->
          opts = if cursor == :first_page, do: opts, else: Keyword.put(opts, :after, cursor)

          case list(client, type, opts) do
            {:ok, %{results: results, after: nil}} -> {results, :done}
            {:ok, %{results: results, after: next}} -> {results, next}
            {:error, exception} -> raise exception
          end
      end,
      fn _state -> :ok end
    )
  end

  defp base_path(type), do: "/crm/v3/objects/" <> URL.segment(type)

  defp params(opts) do
    opts
    |> Keyword.take(@param_keys)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map(&encode_param/1)
  end

  defp encode_param({:properties_with_history, value}), do: {:propertiesWithHistory, join(value)}
  defp encode_param({key, value}), do: {key, join(value)}

  defp join(value) when is_list(value), do: Enum.join(value, ",")
  defp join(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
