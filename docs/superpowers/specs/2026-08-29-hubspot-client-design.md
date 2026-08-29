# HubspotClient Design

**Date:** 2026-08-29
**Status:** Approved for planning

## Purpose

A small, read-only Elixir client for the HubSpot CRM API, built on `req`. It is a
library: no application, no supervision tree, no global state. Other projects add it
as a dependency and call it.

It lists and reads deals, companies, contacts, tickets, pipelines, pipeline stages,
properties, owners, and associations. It creates, updates, and deletes nothing.

## Credentials

HubSpot removed API keys in 2022. For a data-only, single-account integration the
current credential is a **Service Key**:

1. **Settings -> Integrations -> Service Keys** (or **Development -> Keys -> Service
   Keys**) -> *Create a service key*. Requires Super Admin or Developer tools access.
2. Grant read scopes: `crm.objects.deals.read`, `crm.objects.companies.read`,
   `crm.objects.contacts.read`, `tickets`, `crm.pipelines.read`,
   `crm.schemas.deals.read`, `crm.objects.owners.read`.
3. Copy the key on creation; it is not shown again.

Legacy private apps are the predecessor. HubSpot disables creation of new ones on
2026-09-28 (accounts created on or after that date) and 2026-10-26 (existing
accounts); already-created private apps keep working. Service keys are preferred
regardless: account-level rather than tied to a person, rotatable in place, and
activity-logged. They do not support webhooks or UI extensions, which this library
does not need.

The library is credential-agnostic. Service keys, legacy private app tokens, and
OAuth access tokens are all sent as `Authorization: Bearer <string>`, so the option
is named `:token` and accepts any of them. Swapping credential types is an
environment variable change and nothing more.

## Transport

REST, at `https://api.hubapi.com`.

HubSpot also exposes GraphQL at `/collector/graphql`, but it targets CMS
data-driven content and UI-extension cards, caps at 500 items per query, runs on a
30,000-point budget, and does not cover pipeline, property, or owner metadata. It is
not the integration surface and this library does not use it.

## Endpoints

The CRM v3 object API is uniform across object types, which is what lets one generic
core serve every resource.

| Concern | Method and path |
|---|---|
| List objects | `GET /crm/v3/objects/{type}` |
| Read one object | `GET /crm/v3/objects/{type}/{id}` |
| Search objects | `POST /crm/v3/objects/{type}/search` |
| Batch read objects | `POST /crm/v3/objects/{type}/batch/read` |
| List pipelines | `GET /crm/v3/pipelines/{type}` |
| Read one pipeline | `GET /crm/v3/pipelines/{type}/{pipelineId}` |
| List pipeline stages | `GET /crm/v3/pipelines/{type}/{pipelineId}/stages` |
| List properties | `GET /crm/v3/properties/{type}` |
| Read one property | `GET /crm/v3/properties/{type}/{name}` |
| List owners | `GET /crm/v3/owners` |
| Read one owner | `GET /crm/v3/owners/{ownerId}` |
| List associations | `GET /crm/v4/objects/{type}/{id}/associations/{toType}` |

`search` and `batch/read` are POST requests but are strictly reads, and search is the
only way to filter server-side. Both are in scope; the read-only boundary is about
effect, not HTTP verb.

`{type}` is a HubSpot object type string: `deals`, `companies`, `contacts`,
`tickets`, `line_items`, `products`, `quotes`, or a custom object type such as
`p12345_widget`.

## Modules

```
HubspotClient              new/1 -> %HubspotClient{}
HubspotClient.Request      builds and executes Req; maps status codes to errors
HubspotClient.Response     decodes bodies into normalized maps
HubspotClient.Objects      list/3 get/4 search/3 batch_read/4 stream/3 (generic)
HubspotClient.Deals        thin delegations to Objects with "deals"
HubspotClient.Companies    thin delegations to Objects with "companies"
HubspotClient.Contacts     thin delegations to Objects with "contacts"
HubspotClient.Tickets      thin delegations to Objects with "tickets"
HubspotClient.Pipelines    list/3 get/4 stages/4
HubspotClient.Properties   list/3 get/4
HubspotClient.Owners       list/2 get/3
HubspotClient.Associations list/5
HubspotClient.Error        %Error{} exception struct
```

`HubspotClient.Request` is the only module that performs HTTP, and
`HubspotClient.Response` is the only module that decodes bodies. Splitting them
keeps decoding testable without stubbing a socket. Every other module
builds a path and options and hands them over. This keeps auth, retry, decoding, and
error mapping in one place and makes the resource modules trivial to read and test.

The resource modules are deliberately thin — roughly ten lines each, delegating to
`Objects` with their type string baked in. They exist for discoverability and
documentation, not behavior. Callers who need a custom object bypass them and call
`Objects.list(client, "p12345_widget")` directly.

## Client

```elixir
client = HubspotClient.new(token: System.fetch_env!("HUBSPOT_TOKEN"))
```

`new/1` accepts:

- `:token` (required) — bearer credential
- `:base_url` (default `"https://api.hubapi.com"`) — override for testing
- `:req_options` (default `[]`) — merged into every Req request, which is how callers
  set `:plug` for tests or override `:retry` and `:receive_timeout`

`new/1` raises `ArgumentError` when `:token` is missing or not a binary. This is
programmer error at setup time, not a runtime failure to be handled, so it raises
rather than returning a tuple. Everything after construction returns tuples.

The struct is explicit and passed to every call — no application config, no global
state. Multiple portals in one VM work without ceremony, and tests construct clients
freely.

## Data shape

Every function returns `{:ok, term}` or `{:error, term}`. The single exception is
`stream/2` and `stream/3`, which raise mid-iteration as described under Pagination.

Responses decode to plain maps under one rule: **keys HubSpot defines become
atoms; keys your portal defines stay strings.**

For CRM objects that means the envelope is atomized while `properties` stays
string-keyed, so custom properties pass through untouched and no atom is created
from portal-controlled input.

```elixir
%{
  id: "123",
  properties: %{"dealname" => "Acme", "amount" => "5000"},
  created_at: ~U[2026-08-29 10:00:00Z],
  updated_at: ~U[2026-08-29 12:00:00Z],
  archived: false
}
```

For metadata resources — pipelines, stages, property definitions, owners,
associations — the whole payload is atomized, recursively, camelCase to
snake_case: `pipeline.display_order`, `property.field_type`, `owner.first_name`.
Their key sets are fixed by HubSpot and therefore bounded, so this creates no
atom-exhaustion risk. Portal-defined property names appear in these payloads only
as string *values* (under `:name`), never as keys.

`createdAt` and `updatedAt` parse to `DateTime`. Timestamps that fail to parse pass
through as the original string rather than failing the request.

Endpoints that paginate — object lists, search, owners, and v4 associations —
return the envelope `%{results: [...], after: cursor_or_nil}`. Endpoints that do not
paginate — pipelines, pipeline stages, properties, and batch read — return a plain
list, `{:ok, [...]}`. The
shape tells the caller whether there is more to fetch, so a cursor is never invented
for an endpoint that has none.

No structs per resource. HubSpot's fields change and every portal has its own custom
properties; a struct would be stale on arrival.

Property selection is passed through, not defaulted. HubSpot returns a small default
property set when `properties` is omitted, and the library does not second-guess it.
Callers ask for what they need:

```elixir
Deals.list(client, properties: ["dealname", "amount", "dealstage"])
```

## Pagination

HubSpot returns at most 100 records per page for list endpoints (200 for search) with
a `paging.next.after` cursor. Two ways to consume it:

```elixir
# One page, cursor exposed
{:ok, %{results: [...], after: "cursor" | nil}} = Deals.list(client, limit: 100)

# Lazy stream that follows cursors until exhausted
client |> Deals.stream(properties: ["dealname"]) |> Enum.take(500)
```

`stream/2` is `Stream.resource/3` over the same list call, halting when `after` is
`nil`. Because it is lazy, `Enum.take(500)` issues five requests and stops. Errors
mid-stream raise `HubspotClient.Error` — a stream cannot return an error tuple
without corrupting its element type, and this is the one documented exception to the
no-raise rule.

Search paging is capped by HubSpot at 10,000 total results per query; paging past it
returns 400. `Objects.search/3` documents this and does not attempt to work around
it.

## Errors

Non-2xx responses become `{:error, %HubspotClient.Error{}}`:

```elixir
%HubspotClient.Error{
  status: 404,
  category: "OBJECT_NOT_FOUND",
  message: "resource not found",
  correlation_id: "aeb5f871-...",
  body: %{...}
}
```

`category` and `correlation_id` come straight from HubSpot's error body. Correlation
IDs are what HubSpot support asks for, so they are surfaced rather than buried.
`body` retains the raw decoded payload for anything not modeled.

`Error` is defined with `defexception` so it can be raised by `stream/2` and matched
as a plain struct everywhere else.

Transport-level failures (DNS, connection refused, timeout) pass through as
`{:error, %Req.TransportError{}}` unwrapped. Wrapping them would hide detail and add
nothing.

## Rate limits and retries

Limits are 190 requests per 10 seconds on Professional and Enterprise, 100 on Free
and Starter, with a separate and much tighter 5 requests per second shared across all
search endpoints.

The client sets Req's `retry: :transient`, which retries 408/429/500/502/503/504 and
derives its delay from the `Retry-After` header on 429 and 503. Req's default is
`:safe_transient`, which retries only GET and HEAD — that would leave `search` and
`batch_read` unretried, since both are POST. Every request this library issues is a
read and therefore idempotent, so retrying POSTs is safe here and `:transient` is the
correct setting. This is the one Req default the library deliberately overrides.

No custom rate limiter and no token bucket: Req's behavior covers the realistic
failure mode, and callers who need more can override `:retry` through `:req_options`.
The 5/second search limit is documented so callers driving search in a tight loop know
why they are seeing 429s.

## Testing

`Req.Test` plug stubs throughout. No live API calls, no HTTP mocking dependency, no
recorded cassettes.

- `Request` — auth header, base URL joining, query encoding, success decoding, each
  error branch, transport error passthrough
- `Objects` — path and params for each of list, get, search, batch read
- `stream/3` — follows a cursor across pages, stops on `after: nil`, raises on error
- Each resource module — asserts it targets the right object type and path
- Normalization — envelope atomization, string-keyed properties preserved,
  timestamp parsing, unparseable timestamp passthrough

Fixtures are trimmed real HubSpot response bodies.

## Dependencies

- `req ~> 0.7` — runtime (0.7.4 current as of this writing; brings in `finch`,
  `jason`, and `mime`)
- `plug ~> 1.0` — test only. `req` declares `plug` optional, and `Req.Test` needs it,
  so the test stubs do not work without adding it here.
- `ex_doc` — dev only, for docs

Nothing else. `req` requires Elixir ~> 1.15; this project targets ~> 1.20.

## Out of scope

Creates, updates, deletes, and archives. Webhooks. OAuth authorization flows and
token refresh. GenServers, supervision, connection pooling beyond Req's default,
caching, and rate limiter processes. Marketing, CMS, and automation APIs. Typed
structs per resource. If these become necessary they are separate work with their own
design.
