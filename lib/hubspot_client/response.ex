defmodule HubspotClient.Response do
  @moduledoc """
  Decodes HubSpot response bodies.

  Two rules, applied by resource type:

    * **CRM objects** — `object/1` atomizes the fixed envelope (`id`,
      `createdAt`, `updatedAt`, `archived`) and leaves `properties` exactly as
      HubSpot sent it, string-keyed. Property names are defined by your portal
      and are therefore unbounded; turning them into atoms would leak.

    * **Metadata** — `metadata/1` recursively converts camelCase keys to
      snake_case atoms. Pipelines, stages, property definitions, owners, and
      associations have key sets fixed by HubSpot, so the set of atoms is
      bounded and known ahead of time.

  In short: keys HubSpot defines become atoms, keys your portal defines stay
  strings.
  """

  @timestamp_keys [:created_at, :updated_at]

  @doc """
  Normalizes one CRM object.
  """
  @spec object(map()) :: map()
  def object(raw) when is_map(raw) do
    %{
      id: raw["id"],
      properties: Map.get(raw, "properties") || %{},
      created_at: timestamp(raw["createdAt"]),
      updated_at: timestamp(raw["updatedAt"]),
      archived: Map.get(raw, "archived") || false
    }
    |> put_present(:associations, raw["associations"])
  end

  @doc """
  Recursively converts a metadata payload's keys to snake_case atoms.
  """
  @spec metadata(term()) :: term()
  def metadata(raw) when is_map(raw) and not is_struct(raw) do
    Map.new(raw, fn {key, value} ->
      key = atomize(key)
      {key, metadata_value(key, value)}
    end)
  end

  def metadata(raw) when is_list(raw), do: Enum.map(raw, &metadata/1)
  def metadata(raw), do: raw

  @doc """
  Decodes a paginated envelope into `%{results: list, after: cursor_or_nil}`.
  """
  @spec paged(map(), (map() -> term())) :: %{results: list(), after: String.t() | nil}
  def paged(body, fun) when is_map(body) and is_function(fun, 1) do
    %{
      results: body |> results() |> Enum.map(fun),
      after: get_in(body, ["paging", "next", "after"])
    }
  end

  @doc """
  Decodes a non-paginated envelope into a plain list.
  """
  @spec collection(map(), (map() -> term())) :: list()
  def collection(body, fun) when is_map(body) and is_function(fun, 1) do
    body |> results() |> Enum.map(fun)
  end

  defp results(body) do
    case Map.get(body, "results") do
      results when is_list(results) -> results
      _ -> []
    end
  end

  defp metadata_value(key, value) when key in @timestamp_keys, do: timestamp(value)
  defp metadata_value(_key, value), do: metadata(value)

  defp atomize(key) when is_binary(key),
    do: key |> Macro.underscore() |> String.to_existing_atom()

  defp atomize(key), do: key

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> value
    end
  end

  defp timestamp(value), do: value
end
