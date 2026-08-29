defmodule HubspotClient.Error do
  @moduledoc """
  A non-2xx response from the HubSpot API.

  `:category` and `:correlation_id` come straight from HubSpot's error body.
  Quote the correlation ID when contacting HubSpot support — it is the first
  thing they ask for. `:body` keeps the raw decoded payload for anything not
  modeled here.
  """

  defexception [:status, :category, :message, :correlation_id, :body]

  @type t :: %__MODULE__{
          status: pos_integer() | nil,
          category: String.t() | nil,
          message: String.t() | nil,
          correlation_id: String.t() | nil,
          body: term()
        }

  @default_message "unexpected HubSpot response"

  @doc """
  Builds an error from a response status and decoded body.
  """
  @spec from_response(integer(), term()) :: t()
  def from_response(status, body) when is_map(body) do
    %__MODULE__{
      status: status,
      category: body["category"],
      message: body["message"] || @default_message,
      correlation_id: body["correlationId"],
      body: body
    }
  end

  def from_response(status, body) do
    %__MODULE__{status: status, message: @default_message, body: body}
  end

  @impl true
  def message(%__MODULE__{status: status, category: category, message: message}) do
    category_part = if category, do: ", category #{category}", else: ""
    "HubSpot API error (status #{inspect(status)}#{category_part}): #{message}"
  end
end
