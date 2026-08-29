defmodule HubspotClient.Request do
  @moduledoc """
  The only module in this library that performs HTTP.

  Every other module builds a path plus options and hands them here, which keeps
  authentication, retry policy, and error mapping in exactly one place.
  """

  alias HubspotClient.Error

  @doc """
  Issues a GET and returns the raw decoded body.
  """
  @spec get(HubspotClient.t(), String.t(), keyword()) :: {:ok, term()} | {:error, Exception.t()}
  def get(%HubspotClient{} = client, path, params \\ []) do
    client
    |> build(url: path, params: params)
    |> run()
  end

  @doc """
  Issues a POST with a JSON body and returns the raw decoded body.

  Used only for HubSpot's read endpoints that require POST: object search and
  batch read.
  """
  @spec post(HubspotClient.t(), String.t(), map()) :: {:ok, term()} | {:error, Exception.t()}
  def post(%HubspotClient{} = client, path, body) when is_map(body) do
    client
    |> build(method: :post, url: path, json: body)
    |> run()
  end

  defp build(client, options) do
    defaults(client)
    |> Keyword.merge(client.req_options)
    |> Keyword.merge(options)
    |> Req.new()
  end

  defp defaults(client) do
    [
      base_url: client.base_url,
      auth: {:bearer, client.token},
      # Req defaults to :safe_transient, which retries GET and HEAD only. Every
      # request this library issues is a read and therefore idempotent, so the
      # search and batch-read POSTs are safe to retry too. Req derives the delay
      # from Retry-After on 429 and 503, which is what HubSpot sends when you
      # exceed the rate limit.
      retry: :transient
    ]
  end

  defp run(request) do
    case Req.request(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, exception} ->
        {:error, exception}
    end
  end
end
