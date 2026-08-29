defmodule HubspotClient do
  @moduledoc """
  A read-only client for the HubSpot CRM API.

  Build a client once, then pass it to the resource modules:

      client = HubspotClient.new(token: System.fetch_env!("HUBSPOT_TOKEN"))

      {:ok, page} = HubspotClient.Deals.list(client, properties: ["dealname", "amount"])
      {:ok, pipelines} = HubspotClient.Pipelines.list(client, "deals")

  ## Credentials

  The `:token` is sent as `Authorization: Bearer <token>`. A HubSpot **service
  key** (Settings -> Integrations -> Service Keys) is the current credential for
  data-only integrations. Legacy private app access tokens and OAuth access
  tokens use the same header and work here unchanged.

  This library never creates, updates, or deletes anything, so read scopes are
  sufficient.
  """

  @enforce_keys [:token, :base_url, :req_options]
  defstruct [:token, :base_url, :req_options]

  @type t :: %__MODULE__{
          token: String.t(),
          base_url: String.t(),
          req_options: keyword()
        }

  @default_base_url "https://api.hubapi.com"

  @doc """
  Builds a client.

  ## Options

    * `:token` - required. The bearer credential.
    * `:base_url` - defaults to `#{@default_base_url}`.
    * `:req_options` - merged into every `Req` request, overriding this
      library's defaults. Use it to set `:plug` in tests, or to override
      `:retry` and `:receive_timeout`. The keys `:method`, `:json`, `:body`,
      and `:form` are ignored here; this library is read-only and those keys
      are stripped so no option can turn a documented read into a write.

  Raises `ArgumentError` when `:token` is not a non-empty string. This is a
  setup mistake rather than a runtime condition, so it raises; every other
  function in this library returns a tuple.
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    token = Keyword.get(opts, :token)

    if not (is_binary(token) and token != "") do
      raise ArgumentError,
            "HubspotClient.new/1 requires a :token option that is a non-empty string, got: " <>
              inspect(token)
    end

    %__MODULE__{
      token: token,
      base_url: Keyword.get(opts, :base_url, @default_base_url),
      req_options: Keyword.get(opts, :req_options, [])
    }
  end
end
