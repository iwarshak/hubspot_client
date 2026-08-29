# HubspotClient

A small, read-only Elixir client for the HubSpot CRM API, built on
[Req](https://hex.pm/packages/req).

It lists and reads deals, companies, contacts, tickets, pipelines, stages,
property definitions, owners, and associations. It creates, updates, and
deletes nothing.

## Installation

This library is not published anywhere yet. Depend on it as a local path:

```elixir
def deps do
  [{:hubspot_client, path: "../hubspot_client"}]
end
```

Adjust the path to wherever this repo lives relative to the consuming project.
If you later push it to a git host, swap in `git: "<url>", tag: "v0.1.0"`; if
you publish it to Hex, add a `package/0` to `mix.exs` first.

## Getting a token

HubSpot removed API keys in 2022. For a data-only integration, create a
**service key**:

1. In HubSpot, go to **Settings → Integrations → Service Keys** (also reachable
   at **Development → Keys → Service Keys**) and click **Create a service key**.
   You need Super Admin or Developer tools access.
2. Grant the read scopes this library needs:
   `crm.objects.deals.read`, `crm.objects.companies.read`,
   `crm.objects.contacts.read`, `tickets`, `crm.pipelines.read`,
   `crm.schemas.deals.read`, `crm.objects.owners.read`.
3. Copy the key when it is shown. It is not shown again.

Legacy private app access tokens and OAuth access tokens also work — all three
are sent as `Authorization: Bearer <token>`. HubSpot stops allowing new legacy
private apps on 2026-09-28 for accounts created on or after that date, and
2026-10-26 for older accounts, so new integrations should use a service key.

## Usage

```elixir
client = HubspotClient.new(token: System.fetch_env!("HUBSPOT_TOKEN"))

# One page
{:ok, %{results: deals, after: cursor}} =
  HubspotClient.Deals.list(client, limit: 100, properties: ["dealname", "amount"])

# Every deal, lazily
client
|> HubspotClient.Deals.stream(properties: ["dealname"])
|> Stream.map(& &1.properties["dealname"])
|> Enum.take(500)

# One record
{:ok, deal} = HubspotClient.Deals.get(client, "123")

# Server-side filtering
{:ok, %{results: won}} =
  HubspotClient.Deals.search(client, %{
    "filterGroups" => [
      %{"filters" => [%{"propertyName" => "dealstage", "operator" => "EQ", "value" => "closedwon"}]}
    ],
    "properties" => ["dealname", "amount"],
    "limit" => 100
  })

# Pipelines and stages
{:ok, pipelines} = HubspotClient.Pipelines.list(client, "deals")
{:ok, stages} = HubspotClient.Pipelines.stages(client, "deals", "default")

# What properties does this portal actually have?
{:ok, properties} = HubspotClient.Properties.list(client, "deals")

# Custom objects
{:ok, page} = HubspotClient.Objects.list(client, "p12345_widget")
```

### Ask for the properties you want

HubSpot returns a small default set of properties when you do not name any, and
it frequently will not include the fields you care about. Pass `:properties`
explicitly.

### Return shapes

CRM objects normalize to atom-keyed envelopes with `properties` left
string-keyed, because property names are defined by your portal:

```elixir
%{
  id: "123",
  properties: %{"dealname" => "Acme", "amount" => "5000"},
  created_at: ~U[2026-08-29 10:00:00.000Z],
  updated_at: ~U[2026-08-29 12:00:00.000Z],
  archived: false
}
```

Metadata — pipelines, stages, properties, owners, associations — has a schema
HubSpot fixes, so its keys become atoms: `pipeline.display_order`,
`property.field_type`, `owner.first_name`.

Endpoints that paginate return `%{results: [...], after: cursor_or_nil}`.
Endpoints that do not (pipelines, stages, properties, and batch read) return a
plain list.

### Errors

Every function returns `{:ok, term}` or `{:error, term}`:

```elixir
{:error, %HubspotClient.Error{status: 404, category: "OBJECT_NOT_FOUND", correlation_id: id}}
```

Quote the `correlation_id` when contacting HubSpot support. Network failures
surface as `%Req.TransportError{}`.

The one exception is `stream/2`, which raises mid-iteration rather than yielding
error tuples as elements.

### Rate limits

190 requests per 10 seconds on Professional and Enterprise, 100 on Free and
Starter, plus a much tighter 5 requests per second shared across all `search`
endpoints. The client retries 429 and 5xx responses and honors `Retry-After`.
Override with `req_options: [retry: false]` if you want to handle it yourself.

Every response carries HubSpot's rate-limit headers. This library emits a
telemetry event so you can self-pace instead of only reacting to 429s:

```elixir
:telemetry.attach("hubspot-rate-limit", [:hubspot_client, :rate_limit], fn _e, m, meta, _ ->
  if m.remaining < 20, do: Logger.warning("HubSpot budget low")
end, nil)
```

The event measurements are `remaining`, `max`, and `interval_ms`, parsed from the
response headers when present. The metadata carries `method` (`:get` or `:post`),
`path`, and `status` (including 429s). The library does no proactive throttling —
this event is what lets a caller throttle itself.

## Read-only guarantees

Every request goes through `HubspotClient.Request`, which is the only module
that performs HTTP. It exposes `get/3` and `post/3` and nothing else — there is
no PUT, PATCH, or DELETE anywhere in the library.

HubSpot creates, updates, archives, and merges records via POST, so `post/3`
is restricted to the two read endpoints that happen to require it:
`/crm/v3/objects/{type}/search` and `/crm/v3/objects/{type}/batch/read`.
Any other path raises `ArgumentError` before a request is sent. Object types,
record IDs, and property names are percent-encoded as single path segments, so
a caller-supplied value cannot re-route a request.

`:req_options` cannot change this either: `:method`, `:json`, `:body`, and
`:form` are stripped, and the library's own request options are applied after
yours.

## Testing against this library

Pass a `Req.Test` stub through `:req_options`:

```elixir
client = HubspotClient.new(token: "test", req_options: [plug: {Req.Test, MyStub}])
```
