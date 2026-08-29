defmodule HubspotClient.Pipelines do
  @moduledoc """
  Read access to pipelines and their stages.

  A pipeline belongs to an object type — `"deals"` and `"tickets"` are the
  common ones — so every function takes that type as its second argument.

  These endpoints do not paginate, so they return plain lists. Keys are atoms:
  HubSpot fixes this schema, unlike CRM object properties.

      {:ok, pipelines} = HubspotClient.Pipelines.list(client, "deals")
      Enum.map(pipelines, & &1.label)

  A deal's `dealstage` property holds a stage ID. Join it against
  `stages/4` to turn it into a human-readable label.
  """

  alias HubspotClient.{Request, Response}

  @doc """
  Lists every pipeline for an object type.
  """
  @spec list(HubspotClient.t(), String.t(), keyword()) ::
          {:ok, list(map())} | {:error, Exception.t()}
  def list(client, object_type, _opts \\ []) do
    with {:ok, body} <- Request.get(client, base_path(object_type)) do
      {:ok, Response.collection(body, &Response.metadata/1)}
    end
  end

  @doc """
  Reads a single pipeline.
  """
  @spec get(HubspotClient.t(), String.t(), String.t() | integer(), keyword()) ::
          {:ok, map()} | {:error, Exception.t()}
  def get(client, object_type, pipeline_id, _opts \\ []) do
    with {:ok, body} <- Request.get(client, base_path(object_type) <> "/" <> segment(pipeline_id)) do
      {:ok, Response.metadata(body)}
    end
  end

  @doc """
  Lists the stages of a single pipeline.
  """
  @spec stages(HubspotClient.t(), String.t(), String.t() | integer(), keyword()) ::
          {:ok, list(map())} | {:error, Exception.t()}
  def stages(client, object_type, pipeline_id, _opts \\ []) do
    path = base_path(object_type) <> "/" <> segment(pipeline_id) <> "/stages"

    with {:ok, body} <- Request.get(client, path) do
      {:ok, Response.collection(body, &Response.metadata/1)}
    end
  end

  defp base_path(object_type), do: "/crm/v3/pipelines/" <> segment(object_type)

  defp segment(value), do: value |> to_string() |> URI.encode(&URI.char_unreserved?/1)
end
