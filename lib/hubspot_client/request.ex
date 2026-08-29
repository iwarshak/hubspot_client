defmodule HubspotClient.Request do
  @moduledoc """
  The only module in this library that performs HTTP.

  Every other module builds a path plus options and hands them here, which keeps
  authentication, retry policy, and error mapping in exactly one place.

  ## Rate limits

  HubSpot returns rate-limit information in response headers. This library emits
  a telemetry event carrying those values so callers can self-pace instead of only
  reacting to 429s after being throttled:

      :telemetry.attach("hubspot-rate-limit", [:hubspot_client, :rate_limit], fn _e, m, meta, _ ->
        if m.remaining < 20, do: Logger.warning("HubSpot budget low")
      end, nil)

  The library still performs no proactive throttling — it retries 429s honoring
  `Retry-After`, and this event is what lets a caller throttle itself.
  """

  alias HubspotClient.Error

  # :req_options is an escape hatch for transport concerns — :plug in tests,
  # :retry, :receive_timeout. It must never be able to reshape the request
  # itself: this library is read-only, and a :method smuggled in here would
  # turn a documented read into a write that still reports {:ok, _}.
  @reserved_options [:method, :json, :body, :form]

  @doc """
  Issues a GET and returns the raw decoded body.
  """
  @spec get(HubspotClient.t(), String.t(), keyword()) :: {:ok, term()} | {:error, Exception.t()}
  def get(%HubspotClient{} = client, path, params \\ []) do
    client
    |> build(method: :get, url: path, params: params)
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
    |> Keyword.merge(Keyword.drop(client.req_options, @reserved_options))
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
      {:ok, %Req.Response{status: status, body: body} = response}
      when status in 200..299 ->
        emit_rate_limit_telemetry(request, response)
        if is_map(body), do: {:ok, body}, else: {:error, Error.from_response(status, body)}

      {:ok, %Req.Response{} = response} ->
        emit_rate_limit_telemetry(request, response)
        {:error, Error.from_response(response.status, response.body)}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp emit_rate_limit_telemetry(request, response) do
    measurements = parse_rate_limit_headers(response.headers)

    if not (measurements == %{}) do
      :telemetry.execute(
        [:hubspot_client, :rate_limit],
        measurements,
        %{
          method: request.method,
          path: request.url.path,
          status: response.status
        }
      )
    end
  end

  defp parse_rate_limit_headers(headers) do
    measurements = %{}

    measurements =
      case get_header_as_integer(headers, "x-hubspot-ratelimit-remaining") do
        {:ok, remaining} -> Map.put(measurements, :remaining, remaining)
        :error -> measurements
      end

    measurements =
      case get_header_as_integer(headers, "x-hubspot-ratelimit-max") do
        {:ok, max} -> Map.put(measurements, :max, max)
        :error -> measurements
      end

    measurements =
      case get_header_as_integer(headers, "x-hubspot-ratelimit-interval-milliseconds") do
        {:ok, interval_ms} -> Map.put(measurements, :interval_ms, interval_ms)
        :error -> measurements
      end

    measurements
  end

  defp get_header_as_integer(headers, header_name) do
    case Map.get(headers, header_name) do
      [value] when is_binary(value) ->
        case Integer.parse(value) do
          {num, ""} -> {:ok, num}
          _ -> :error
        end

      _ ->
        :error
    end
  end
end
