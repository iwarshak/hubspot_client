defmodule HubspotClient.Properties do
  @moduledoc """
  Read access to property definitions — the schema behind a CRM object's
  `properties` map.

  Use this to discover what a portal actually stores, and to turn an enumeration
  property's stored value into its display label via the `:options` list.

      {:ok, properties} = HubspotClient.Properties.list(client, "deals")
      Enum.map(properties, &{&1.name, &1.label})

  Keys are atoms because HubSpot fixes this schema. Portal-defined property
  names appear as string **values** under `:name`, never as keys.

  This endpoint does not paginate.
  """

  alias HubspotClient.{Request, Response}

  @doc """
  Lists every property defined for an object type.
  """
  @spec list(HubspotClient.t(), String.t(), keyword()) ::
          {:ok, list(map())} | {:error, Exception.t()}
  def list(client, object_type, _opts \\ []) do
    with {:ok, body} <- Request.get(client, base_path(object_type)) do
      {:ok, Response.collection(body, &Response.metadata/1)}
    end
  end

  @doc """
  Reads a single property definition by name.
  """
  @spec get(HubspotClient.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Exception.t()}
  def get(client, object_type, property_name, _opts \\ []) do
    with {:ok, body} <-
           Request.get(client, base_path(object_type) <> "/" <> segment(property_name)) do
      {:ok, Response.metadata(body)}
    end
  end

  defp base_path(object_type), do: "/crm/v3/properties/" <> segment(object_type)

  defp segment(value), do: value |> to_string() |> URI.encode(&URI.char_unreserved?/1)
end
