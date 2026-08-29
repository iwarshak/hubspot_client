# HubspotClient Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a read-only Elixir client for the HubSpot CRM REST API on top of `req`, covering deals, companies, contacts, tickets, pipelines, stages, properties, owners, and associations.

**Architecture:** One module (`HubspotClient.Request`) performs all HTTP; one module (`HubspotClient.Response`) performs all decoding. A generic `HubspotClient.Objects` covers every CRM object type, and per-resource modules are ~6-line delegations over it. An explicit `%HubspotClient{}` struct carries the token — no global state.

**Tech Stack:** Elixir ~> 1.20, `req` ~> 0.7 (Finch/Jason under the hood), `Req.Test` plug stubs for testing, `ex_doc` for docs.

**Spec:** `docs/superpowers/specs/2026-08-29-hubspot-client-design.md`

## Refinements to the spec

Two things resolved while planning. Both are reflected below and should be
folded back into the spec:

1. **`HubspotClient.Response` is a new module** not named in the spec's module
   list. The spec assigned normalization to `Request`. Splitting it out keeps
   `Request` purely about HTTP and makes decoding testable without stubbing a
   socket. `Request` still performs all HTTP; it just calls `Response` to decode.

2. **Two normalization rules, not one.** The spec said "envelope keys are
   atomized, `properties` stays string-keyed." Generalized, the rule is: **keys
   HubSpot defines become atoms; keys your portal defines stay strings.** So CRM
   object envelopes normalize to `%{id:, properties:, created_at:, ...}` with
   `properties` left string-keyed, while metadata resources (pipelines, stages,
   properties, owners, associations) — whose key sets are fixed by HubSpot and
   therefore bounded — get recursive camelCase-to-snake_case atom keys. This is
   what makes `pipeline.label` and `property.field_type` work without risking
   unbounded atom creation from portal-defined property names.

3. **Associations paginate.** The spec listed v4 associations among the
   non-paginating endpoints. `GET /crm/v4/objects/{type}/{id}/associations/{toType}`
   returns a `paging.next.after` cursor, so it returns the paged envelope.

## Global Constraints

- Elixir `~> 1.20`; `req` requires `~> 1.15`, so the floor is satisfied.
- Dependencies are exactly: `{:req, "~> 0.7"}`, `{:plug, "~> 1.0", only: :test}`, `{:ex_doc, "~> 0.34", only: :dev, runtime: false}`. Nothing else.
- `plug` is an **optional** dependency of `req`. `Req.Test` does not work without adding it explicitly.
- Read-only. No function in this library may issue a request that creates, updates, archives, or deletes. `search` and `batch/read` are POST but are reads and are in scope.
- Every public function returns `{:ok, term}` or `{:error, term}`. The only exception is `stream/2` and `stream/3`, which raise mid-iteration.
- No structs per resource. Decoded data is plain maps.
- `unless/2` is soft-deprecated as of Elixir 1.17. Use `if not (...)`.
- Base URL default: `"https://api.hubapi.com"`.
- Retry is `:transient`, not Req's `:safe_transient` default, so POST reads retry too.
- Run `mix format` before every commit.

---

### Task 1: Project setup and the client struct

**Files:**
- Modify: `mix.exs`
- Modify: `lib/hubspot_client.ex` (replace scaffold `hello/0` entirely)
- Test: `test/hubspot_client_test.exs` (replace scaffold test entirely)

**Interfaces:**
- Consumes: nothing
- Produces: `%HubspotClient{token: String.t(), base_url: String.t(), req_options: keyword()}` and `HubspotClient.new(keyword()) :: t()`. Every later task takes this struct as its first argument.

- [ ] **Step 1: Add dependencies to `mix.exs`**

Replace the `deps/0` function and add a description and docs config:

```elixir
  def project do
    [
      app: :hubspot_client,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A read-only Elixir client for the HubSpot CRM API.",
      docs: [main: "HubspotClient", extras: ["README.md"]]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.7"},
      {:plug, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
```

- [ ] **Step 2: Fetch dependencies**

Run: `mix deps.get`
Expected: resolves `req`, `finch`, `jason`, `mime`, `plug`, `ex_doc` and writes `mix.lock`.

- [ ] **Step 3: Write the failing test**

Replace the entire contents of `test/hubspot_client_test.exs`:

```elixir
defmodule HubspotClientTest do
  use ExUnit.Case, async: true

  describe "new/1" do
    test "builds a client with the given token" do
      client = HubspotClient.new(token: "pat-na1-secret")

      assert %HubspotClient{
               token: "pat-na1-secret",
               base_url: "https://api.hubapi.com",
               req_options: []
             } = client
    end

    test "allows overriding base_url and req_options" do
      client =
        HubspotClient.new(
          token: "t",
          base_url: "http://localhost:4000",
          req_options: [retry: false]
        )

      assert client.base_url == "http://localhost:4000"
      assert client.req_options == [retry: false]
    end

    test "raises when the token is missing" do
      assert_raise ArgumentError, ~r/:token/, fn -> HubspotClient.new([]) end
    end

    test "raises when the token is not a non-empty string" do
      assert_raise ArgumentError, ~r/:token/, fn -> HubspotClient.new(token: "") end
      assert_raise ArgumentError, ~r/:token/, fn -> HubspotClient.new(token: nil) end
      assert_raise ArgumentError, ~r/:token/, fn -> HubspotClient.new(token: 123) end
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `mix test test/hubspot_client_test.exs`
Expected: FAIL — `HubspotClient.new/1 is undefined`.

- [ ] **Step 5: Write the implementation**

Replace the entire contents of `lib/hubspot_client.ex`:

```elixir
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
      `:retry` and `:receive_timeout`.

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
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `mix test`
Expected: PASS, 4 tests, 0 failures.

- [ ] **Step 7: Commit**

```bash
mix format
git add mix.exs mix.lock lib/hubspot_client.ex test/hubspot_client_test.exs
git commit -m "feat: add HubspotClient struct and new/1"
```

---

### Task 2: Error struct

**Files:**
- Create: `lib/hubspot_client/error.ex`
- Test: `test/hubspot_client/error_test.exs`

**Interfaces:**
- Consumes: nothing
- Produces: `%HubspotClient.Error{status: pos_integer() | nil, category: String.t() | nil, message: String.t() | nil, correlation_id: String.t() | nil, body: term()}` and `HubspotClient.Error.from_response(status :: integer(), body :: term()) :: t()`. Task 4 calls `from_response/2`; Task 7 raises the struct.

- [ ] **Step 1: Write the failing test**

Create `test/hubspot_client/error_test.exs`:

```elixir
defmodule HubspotClient.ErrorTest do
  use ExUnit.Case, async: true

  alias HubspotClient.Error

  describe "from_response/2" do
    test "extracts HubSpot's error fields" do
      body = %{
        "status" => "error",
        "message" => "resource not found",
        "correlationId" => "aeb5f871-1111-2222",
        "category" => "OBJECT_NOT_FOUND"
      }

      assert %Error{
               status: 404,
               category: "OBJECT_NOT_FOUND",
               message: "resource not found",
               correlation_id: "aeb5f871-1111-2222",
               body: ^body
             } = Error.from_response(404, body)
    end

    test "tolerates a map missing every known field" do
      assert %Error{status: 500, category: nil, correlation_id: nil, message: message, body: %{}} =
               Error.from_response(500, %{})

      assert is_binary(message)
    end

    test "tolerates a non-map body such as an HTML error page" do
      assert %Error{status: 502, body: "<html>bad gateway</html>", message: message} =
               Error.from_response(502, "<html>bad gateway</html>")

      assert is_binary(message)
    end
  end

  describe "Exception behaviour" do
    test "message/1 includes the status and category" do
      error = Error.from_response(429, %{"message" => "too many", "category" => "RATE_LIMIT"})
      formatted = Exception.message(error)

      assert formatted =~ "429"
      assert formatted =~ "RATE_LIMIT"
      assert formatted =~ "too many"
    end

    test "is raisable" do
      error = Error.from_response(404, %{"message" => "nope"})
      assert_raise Error, fn -> raise error end
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/hubspot_client/error_test.exs`
Expected: FAIL — `HubspotClient.Error is not available`.

- [ ] **Step 3: Write the implementation**

Create `lib/hubspot_client/error.ex`:

```elixir
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test`
Expected: PASS, all tests green.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/hubspot_client/error.ex test/hubspot_client/error_test.exs
git commit -m "feat: add HubspotClient.Error"
```

---

### Task 3: Response decoding

**Files:**
- Create: `lib/hubspot_client/response.ex`
- Test: `test/hubspot_client/response_test.exs`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `HubspotClient.Response.object(map()) :: map()` — CRM object envelope
  - `HubspotClient.Response.metadata(term()) :: term()` — recursive atom-key conversion
  - `HubspotClient.Response.paged(map(), (map() -> map())) :: %{results: list(), after: String.t() | nil}`
  - `HubspotClient.Response.collection(map(), (map() -> map())) :: list()`

  Tasks 5, 6, 7, 9, 10, and 11 call these.

- [ ] **Step 1: Write the failing test**

Create `test/hubspot_client/response_test.exs`:

```elixir
defmodule HubspotClient.ResponseTest do
  use ExUnit.Case, async: true

  alias HubspotClient.Response

  describe "object/1" do
    test "atomizes the envelope and leaves properties string-keyed" do
      raw = %{
        "id" => "123",
        "properties" => %{"dealname" => "Acme", "amount" => "5000"},
        "createdAt" => "2026-08-29T10:00:00.000Z",
        "updatedAt" => "2026-08-29T12:00:00.000Z",
        "archived" => false
      }

      assert %{
               id: "123",
               properties: %{"dealname" => "Acme", "amount" => "5000"},
               created_at: ~U[2026-08-29 10:00:00.000Z],
               updated_at: ~U[2026-08-29 12:00:00.000Z],
               archived: false
             } = Response.object(raw)
    end

    test "defaults properties and archived when absent" do
      assert %{id: "1", properties: %{}, archived: false, created_at: nil, updated_at: nil} =
               Response.object(%{"id" => "1"})
    end

    test "passes an unparseable timestamp through unchanged" do
      assert %{created_at: "not-a-date"} = Response.object(%{"createdAt" => "not-a-date"})
    end

    test "includes associations only when present" do
      refute Map.has_key?(Response.object(%{"id" => "1"}), :associations)

      raw = %{"id" => "1", "associations" => %{"companies" => %{"results" => []}}}
      assert %{associations: %{"companies" => %{"results" => []}}} = Response.object(raw)
    end
  end

  describe "metadata/1" do
    test "converts camelCase keys to snake_case atoms, recursively" do
      raw = %{
        "id" => "default",
        "label" => "Sales Pipeline",
        "displayOrder" => 0,
        "stages" => [
          %{"id" => "1", "label" => "Appointment", "metadata" => %{"isClosed" => "false"}}
        ]
      }

      assert %{
               id: "default",
               label: "Sales Pipeline",
               display_order: 0,
               stages: [%{id: "1", label: "Appointment", metadata: %{is_closed: "false"}}]
             } = Response.metadata(raw)
    end

    test "parses created_at and updated_at but leaves other strings alone" do
      raw = %{"createdAt" => "2026-08-29T10:00:00Z", "label" => "2026-08-29T10:00:00Z"}
      decoded = Response.metadata(raw)

      assert decoded.created_at == ~U[2026-08-29 10:00:00Z]
      assert decoded.label == "2026-08-29T10:00:00Z"
    end

    test "leaves scalars and lists of scalars alone" do
      assert Response.metadata("plain") == "plain"
      assert Response.metadata(7) == 7
      assert Response.metadata(["a", "b"]) == ["a", "b"]
    end
  end

  describe "paged/2" do
    test "maps results and extracts the cursor" do
      body = %{
        "results" => [%{"id" => "1"}, %{"id" => "2"}],
        "paging" => %{"next" => %{"after" => "NTI1Cg", "link" => "https://..."}}
      }

      assert %{results: [%{id: "1"}, %{id: "2"}], after: "NTI1Cg"} =
               Response.paged(body, &Response.object/1)
    end

    test "returns a nil cursor on the last page" do
      assert %{results: [], after: nil} =
               Response.paged(%{"results" => []}, &Response.object/1)
    end
  end

  describe "collection/2" do
    test "maps results to a plain list" do
      body = %{"results" => [%{"label" => "A"}, %{"label" => "B"}]}
      assert [%{label: "A"}, %{label: "B"}] = Response.collection(body, &Response.metadata/1)
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/hubspot_client/response_test.exs`
Expected: FAIL — `HubspotClient.Response is not available`.

- [ ] **Step 3: Write the implementation**

Create `lib/hubspot_client/response.ex`:

```elixir
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

  defp atomize(key) when is_binary(key), do: key |> Macro.underscore() |> String.to_atom()
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test`
Expected: PASS, all tests green.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/hubspot_client/response.ex test/hubspot_client/response_test.exs
git commit -m "feat: add response decoding"
```

---

### Task 4: HTTP request layer

**Files:**
- Create: `lib/hubspot_client/request.ex`
- Test: `test/hubspot_client/request_test.exs`

**Interfaces:**
- Consumes: `%HubspotClient{}` (Task 1), `HubspotClient.Error.from_response/2` (Task 2)
- Produces:
  - `HubspotClient.Request.get(client, path :: String.t(), params :: keyword()) :: {:ok, term()} | {:error, Exception.t()}` (params defaults to `[]`)
  - `HubspotClient.Request.post(client, path :: String.t(), body :: map()) :: {:ok, term()} | {:error, Exception.t()}`

  These return the **raw decoded body**. Decoding into normalized shapes is the caller's job. Tasks 5, 6, 9, 10, 11 call these.

- [ ] **Step 1: Write the failing test**

Create `test/hubspot_client/request_test.exs`:

```elixir
defmodule HubspotClient.RequestTest do
  use ExUnit.Case, async: true

  alias HubspotClient.{Error, Request}

  setup do
    client =
      HubspotClient.new(
        token: "test-token",
        req_options: [plug: {Req.Test, HubspotClient}, retry: false]
      )

    {:ok, client: client}
  end

  describe "get/3" do
    test "sends a bearer token and hits the expected path", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/crm/v3/objects/deals"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-token"]
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, %{"results" => []}} = Request.get(client, "/crm/v3/objects/deals")
    end

    test "encodes query params", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["limit"] == "100"
        assert conn.query_params["properties"] == "dealname,amount"
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, _} =
               Request.get(client, "/crm/v3/objects/deals",
                 limit: 100,
                 properties: "dealname,amount"
               )
    end

    test "returns an Error struct on a 4xx", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{
          "message" => "resource not found",
          "category" => "OBJECT_NOT_FOUND",
          "correlationId" => "abc-123"
        })
      end)

      assert {:error, %Error{status: 404, category: "OBJECT_NOT_FOUND", correlation_id: "abc-123"}} =
               Request.get(client, "/crm/v3/objects/deals/nope")
    end

    test "returns an Error struct on a 5xx", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"message" => "boom"})
      end)

      assert {:error, %Error{status: 500, message: "boom"}} =
               Request.get(client, "/crm/v3/objects/deals")
    end

    test "passes transport errors through unwrapped", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, %Req.TransportError{reason: :econnrefused}} =
               Request.get(client, "/crm/v3/objects/deals")
    end

    test "req_options override library defaults" do
      client =
        HubspotClient.new(
          token: "t",
          req_options: [plug: {Req.Test, HubspotClient}, retry: false, headers: [{"x-custom", "1"}]]
        )

      Req.Test.stub(HubspotClient, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-custom") == ["1"]
        Req.Test.json(conn, %{})
      end)

      assert {:ok, _} = Request.get(client, "/crm/v3/objects/deals")
    end
  end

  describe "post/3" do
    test "sends a JSON body", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/crm/v3/objects/deals/search"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"limit" => 10}
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, %{"results" => []}} =
               Request.post(client, "/crm/v3/objects/deals/search", %{"limit" => 10})
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/hubspot_client/request_test.exs`
Expected: FAIL — `HubspotClient.Request is not available`.

- [ ] **Step 3: Write the implementation**

Create `lib/hubspot_client/request.ex`:

```elixir
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test`
Expected: PASS, all tests green.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/hubspot_client/request.ex test/hubspot_client/request_test.exs
git commit -m "feat: add HTTP request layer"
```

---

### Task 5: Generic object list and get

**Files:**
- Create: `lib/hubspot_client/objects.ex`
- Test: `test/hubspot_client/objects_test.exs`

**Interfaces:**
- Consumes: `Request.get/3` (Task 4), `Response.paged/2` and `Response.object/1` (Task 3)
- Produces:
  - `HubspotClient.Objects.list(client, type :: String.t(), opts :: keyword()) :: {:ok, %{results: list(), after: String.t() | nil}} | {:error, Exception.t()}`
  - `HubspotClient.Objects.get(client, type :: String.t(), id :: String.t() | integer(), opts :: keyword()) :: {:ok, map()} | {:error, Exception.t()}`

  Accepted opts for both: `:limit`, `:after`, `:properties`, `:properties_with_history`, `:associations`, `:archived`. List-valued opts are comma-joined. Tasks 7, 8 build on these.

- [ ] **Step 1: Write the failing test**

Create `test/hubspot_client/objects_test.exs`:

```elixir
defmodule HubspotClient.ObjectsTest do
  use ExUnit.Case, async: true

  alias HubspotClient.Objects

  setup do
    client =
      HubspotClient.new(
        token: "t",
        req_options: [plug: {Req.Test, HubspotClient}, retry: false]
      )

    {:ok, client: client}
  end

  describe "list/3" do
    test "requests the object collection and decodes the page", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/deals"

        Req.Test.json(conn, %{
          "results" => [
            %{"id" => "1", "properties" => %{"dealname" => "Acme"}},
            %{"id" => "2", "properties" => %{"dealname" => "Globex"}}
          ],
          "paging" => %{"next" => %{"after" => "NTI1"}}
        })
      end)

      assert {:ok, %{results: results, after: "NTI1"}} = Objects.list(client, "deals")
      assert [%{id: "1", properties: %{"dealname" => "Acme"}}, %{id: "2"}] = results
    end

    test "comma-joins list-valued params and camelCases propertiesWithHistory", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["properties"] == "dealname,amount"
        assert conn.query_params["associations"] == "companies,contacts"
        assert conn.query_params["propertiesWithHistory"] == "dealstage"
        assert conn.query_params["limit"] == "50"
        assert conn.query_params["after"] == "NTI1"
        assert conn.query_params["archived"] == "false"
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, _} =
               Objects.list(client, "deals",
                 properties: ["dealname", "amount"],
                 associations: ["companies", "contacts"],
                 properties_with_history: ["dealstage"],
                 limit: 50,
                 after: "NTI1",
                 archived: false
               )
    end

    test "omits params that were not given", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.query_string == ""
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, _} = Objects.list(client, "deals")
    end

    test "ignores unknown options rather than forwarding them", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.query_string == ""
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, _} = Objects.list(client, "deals", nonsense: "value")
    end

    test "works for custom object types", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/p12345_widget"
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, _} = Objects.list(client, "p12345_widget")
    end

    test "propagates errors", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"message" => "no scope"})
      end)

      assert {:error, %HubspotClient.Error{status: 403}} = Objects.list(client, "deals")
    end
  end

  describe "get/4" do
    test "requests a single object and decodes it", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/deals/123"
        Req.Test.json(conn, %{"id" => "123", "properties" => %{"dealname" => "Acme"}})
      end)

      assert {:ok, %{id: "123", properties: %{"dealname" => "Acme"}}} =
               Objects.get(client, "deals", "123")
    end

    test "accepts an integer id", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/deals/123"
        Req.Test.json(conn, %{"id" => "123"})
      end)

      assert {:ok, _} = Objects.get(client, "deals", 123)
    end

    test "percent-encodes ids that need it", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/contacts/a%20b"
        Req.Test.json(conn, %{"id" => "a b"})
      end)

      assert {:ok, _} = Objects.get(client, "contacts", "a b")
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/hubspot_client/objects_test.exs`
Expected: FAIL — `HubspotClient.Objects is not available`.

- [ ] **Step 3: Write the implementation**

Create `lib/hubspot_client/objects.ex`:

```elixir
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

  alias HubspotClient.{Request, Response}

  @param_keys [:limit, :after, :properties, :properties_with_history, :associations, :archived]

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
    with {:ok, body} <- Request.get(client, base_path(type) <> "/" <> segment(id), params(opts)) do
      {:ok, Response.object(body)}
    end
  end

  @doc false
  def base_path(type), do: "/crm/v3/objects/" <> segment(type)

  @doc false
  def params(opts) do
    opts
    |> Keyword.take(@param_keys)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map(&encode_param/1)
  end

  defp encode_param({:properties_with_history, value}), do: {:propertiesWithHistory, join(value)}
  defp encode_param({key, value}), do: {key, join(value)}

  defp join(value) when is_list(value), do: Enum.join(value, ",")
  defp join(value), do: value

  defp segment(value) do
    value |> to_string() |> URI.encode(&URI.char_unreserved?/1)
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test`
Expected: PASS, all tests green.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/hubspot_client/objects.ex test/hubspot_client/objects_test.exs
git commit -m "feat: add generic object list and get"
```

---

### Task 6: Object search and batch read

**Files:**
- Modify: `lib/hubspot_client/objects.ex`
- Test: `test/hubspot_client/objects_test.exs` (append describe blocks)

**Interfaces:**
- Consumes: `Request.post/3` (Task 4), `Response.paged/2` and `Response.collection/2` (Task 3)
- Produces:
  - `HubspotClient.Objects.search(client, type :: String.t(), query :: map()) :: {:ok, %{results: list(), after: String.t() | nil}} | {:error, Exception.t()}`
  - `HubspotClient.Objects.batch_read(client, type :: String.t(), ids :: [String.t() | integer()], opts :: keyword()) :: {:ok, list(map())} | {:error, Exception.t()}`

  Task 8 delegates to both.

- [ ] **Step 1: Write the failing test**

Append to `test/hubspot_client/objects_test.exs`, inside the module:

```elixir
  describe "search/3" do
    test "posts the query and decodes a page", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/crm/v3/objects/deals/search"
        {:ok, raw, conn} = Plug.Conn.read_body(conn)

        assert Jason.decode!(raw) == %{
                 "filterGroups" => [
                   %{
                     "filters" => [
                       %{"propertyName" => "dealstage", "operator" => "EQ", "value" => "closedwon"}
                     ]
                   }
                 ],
                 "properties" => ["dealname"],
                 "limit" => 100
               }

        Req.Test.json(conn, %{
          "total" => 1,
          "results" => [%{"id" => "9", "properties" => %{"dealname" => "Won"}}]
        })
      end)

      query = %{
        "filterGroups" => [
          %{
            "filters" => [
              %{"propertyName" => "dealstage", "operator" => "EQ", "value" => "closedwon"}
            ]
          }
        ],
        "properties" => ["dealname"],
        "limit" => 100
      }

      assert {:ok, %{results: [%{id: "9"}], after: nil}} = Objects.search(client, "deals", query)
    end

    test "surfaces the 400 HubSpot returns past the 10,000 result cap", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{
          "message" => "The paging limit is 10000",
          "category" => "VALIDATION_ERROR"
        })
      end)

      assert {:error, %HubspotClient.Error{status: 400, category: "VALIDATION_ERROR"}} =
               Objects.search(client, "deals", %{"after" => "10001"})
    end
  end

  describe "batch_read/4" do
    test "posts ids as inputs and returns a plain list", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/deals/batch/read"
        {:ok, raw, conn} = Plug.Conn.read_body(conn)

        assert Jason.decode!(raw) == %{
                 "inputs" => [%{"id" => "1"}, %{"id" => "2"}],
                 "properties" => ["dealname"]
               }

        Req.Test.json(conn, %{
          "results" => [
            %{"id" => "1", "properties" => %{"dealname" => "A"}},
            %{"id" => "2", "properties" => %{"dealname" => "B"}}
          ]
        })
      end)

      assert {:ok, [%{id: "1"}, %{id: "2"}]} =
               Objects.batch_read(client, "deals", [1, "2"], properties: ["dealname"])
    end

    test "reads by a custom unique property when id_property is given", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)

        assert Jason.decode!(raw) == %{
                 "inputs" => [%{"id" => "acme@example.com"}],
                 "properties" => [],
                 "idProperty" => "email"
               }

        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, []} =
               Objects.batch_read(client, "contacts", ["acme@example.com"], id_property: "email")
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/hubspot_client/objects_test.exs`
Expected: FAIL — `Objects.search/3 is undefined`.

- [ ] **Step 3: Write the implementation**

Add to `lib/hubspot_client/objects.ex`, after `get/4`:

```elixir
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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test`
Expected: PASS, all tests green.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/hubspot_client/objects.ex test/hubspot_client/objects_test.exs
git commit -m "feat: add object search and batch read"
```

---

### Task 7: Streaming pagination

**Files:**
- Modify: `lib/hubspot_client/objects.ex`
- Test: `test/hubspot_client/objects_stream_test.exs`

**Interfaces:**
- Consumes: `Objects.list/3` (Task 5), `HubspotClient.Error` (Task 2)
- Produces: `HubspotClient.Objects.stream(client, type :: String.t(), opts :: keyword()) :: Enumerable.t()`. Lazy; raises on error. Task 8 delegates to it.

- [ ] **Step 1: Write the failing test**

Create `test/hubspot_client/objects_stream_test.exs`:

```elixir
defmodule HubspotClient.ObjectsStreamTest do
  use ExUnit.Case, async: true

  alias HubspotClient.Objects

  setup do
    client =
      HubspotClient.new(
        token: "t",
        req_options: [plug: {Req.Test, HubspotClient}, retry: false]
      )

    {:ok, client: client}
  end

  defp stub_pages(pages) do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(HubspotClient, fn conn ->
      index = Agent.get_and_update(counter, fn n -> {n, n + 1} end)
      Req.Test.json(conn, Enum.at(pages, index))
    end)

    counter
  end

  test "follows the cursor across pages and stops on a nil cursor", %{client: client} do
    stub_pages([
      %{"results" => [%{"id" => "1"}], "paging" => %{"next" => %{"after" => "c1"}}},
      %{"results" => [%{"id" => "2"}], "paging" => %{"next" => %{"after" => "c2"}}},
      %{"results" => [%{"id" => "3"}]}
    ])

    assert [%{id: "1"}, %{id: "2"}, %{id: "3"}] =
             client |> Objects.stream("deals") |> Enum.to_list()
  end

  test "sends the cursor from the previous page as the after param", %{client: client} do
    {:ok, seen} = Agent.start_link(fn -> [] end)

    Req.Test.stub(HubspotClient, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      cursor = conn.query_params["after"]
      Agent.update(seen, fn list -> list ++ [cursor] end)

      case cursor do
        nil -> Req.Test.json(conn, %{"results" => [], "paging" => %{"next" => %{"after" => "c1"}}})
        "c1" -> Req.Test.json(conn, %{"results" => []})
      end
    end)

    client |> Objects.stream("deals") |> Enum.to_list()

    assert Agent.get(seen, & &1) == [nil, "c1"]
  end

  test "defaults limit to 100 and lets the caller override it", %{client: client} do
    {:ok, seen} = Agent.start_link(fn -> [] end)

    Req.Test.stub(HubspotClient, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      Agent.update(seen, fn list -> list ++ [conn.query_params["limit"]] end)
      Req.Test.json(conn, %{"results" => []})
    end)

    client |> Objects.stream("deals") |> Enum.to_list()
    client |> Objects.stream("deals", limit: 25) |> Enum.to_list()

    assert Agent.get(seen, & &1) == ["100", "25"]
  end

  test "is lazy — Enum.take/2 stops requesting once satisfied", %{client: client} do
    counter = stub_pages(Enum.map(1..10, fn n ->
      %{"results" => [%{"id" => to_string(n)}], "paging" => %{"next" => %{"after" => "c#{n}"}}}
    end))

    assert [%{id: "1"}, %{id: "2"}] = client |> Objects.stream("deals") |> Enum.take(2)
    assert Agent.get(counter, & &1) == 2
  end

  test "raises when a page request fails", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"message" => "bad token"})
    end)

    assert_raise HubspotClient.Error, ~r/bad token/, fn ->
      client |> Objects.stream("deals") |> Enum.to_list()
    end
  end

  test "raises on a transport error", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    assert_raise Req.TransportError, fn ->
      client |> Objects.stream("deals") |> Enum.to_list()
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/hubspot_client/objects_stream_test.exs`
Expected: FAIL — `Objects.stream/2 is undefined`.

- [ ] **Step 3: Write the implementation**

Add the page-size attribute beside the existing `@param_keys` at the top of the
module — this task is its first and only consumer, so it is introduced here
rather than earlier:

```elixir
  @stream_page_size 100
```

Then add to `lib/hubspot_client/objects.ex`, after `batch_read/4`:

```elixir
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test`
Expected: PASS, all tests green.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/hubspot_client/objects.ex test/hubspot_client/objects_stream_test.exs
git commit -m "feat: add lazy pagination stream"
```

---

### Task 8: Per-resource object modules

**Files:**
- Create: `lib/hubspot_client/deals.ex`
- Create: `lib/hubspot_client/companies.ex`
- Create: `lib/hubspot_client/contacts.ex`
- Create: `lib/hubspot_client/tickets.ex`
- Test: `test/hubspot_client/resources_test.exs`

**Interfaces:**
- Consumes: all of `HubspotClient.Objects` (Tasks 5, 6, 7)
- Produces: for each of `Deals`, `Companies`, `Contacts`, `Tickets` — `list/2`, `get/3`, `search/2`, `batch_read/3`, `stream/2`, each delegating with its object type baked in.

Written out rather than generated by a `__using__` macro. Four six-line modules are easier to read, and each one's `@moduledoc` is what shows up in the docs.

- [ ] **Step 1: Write the failing test**

Create `test/hubspot_client/resources_test.exs`:

```elixir
defmodule HubspotClient.ResourcesTest do
  use ExUnit.Case, async: true

  setup do
    client =
      HubspotClient.new(
        token: "t",
        req_options: [plug: {Req.Test, HubspotClient}, retry: false]
      )

    {:ok, client: client}
  end

  @resources [
    {HubspotClient.Deals, "deals"},
    {HubspotClient.Companies, "companies"},
    {HubspotClient.Contacts, "contacts"},
    {HubspotClient.Tickets, "tickets"}
  ]

  for {module, type} <- @resources do
    test "#{inspect(module)}.list/2 targets #{type}", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/#{unquote(type)}"
        Req.Test.json(conn, %{"results" => [%{"id" => "1"}]})
      end)

      assert {:ok, %{results: [%{id: "1"}]}} = unquote(module).list(client)
    end

    test "#{inspect(module)}.get/3 targets #{type}", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/#{unquote(type)}/7"
        Req.Test.json(conn, %{"id" => "7"})
      end)

      assert {:ok, %{id: "7"}} = unquote(module).get(client, "7")
    end

    test "#{inspect(module)}.search/2 targets #{type}", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/#{unquote(type)}/search"
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, %{results: []}} = unquote(module).search(client, %{"limit" => 1})
    end

    test "#{inspect(module)}.batch_read/3 targets #{type}", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/#{unquote(type)}/batch/read"
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, []} = unquote(module).batch_read(client, ["1"])
    end

    test "#{inspect(module)}.stream/2 targets #{type}", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/#{unquote(type)}"
        Req.Test.json(conn, %{"results" => [%{"id" => "1"}]})
      end)

      assert [%{id: "1"}] = client |> unquote(module).stream() |> Enum.to_list()
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/hubspot_client/resources_test.exs`
Expected: FAIL — `HubspotClient.Deals is not available`.

- [ ] **Step 3: Write the four modules**

Create `lib/hubspot_client/deals.ex`:

```elixir
defmodule HubspotClient.Deals do
  @moduledoc """
  Read access to deals.

  A thin delegation to `HubspotClient.Objects` with the `"deals"` object type
  applied. See that module for the full option list.

      {:ok, page} = HubspotClient.Deals.list(client, properties: ["dealname", "amount"])
  """

  alias HubspotClient.Objects

  @type_name "deals"

  @doc "Lists one page of deals. See `HubspotClient.Objects.list/3`."
  def list(client, opts \\ []), do: Objects.list(client, @type_name, opts)

  @doc "Reads a single deal. See `HubspotClient.Objects.get/4`."
  def get(client, id, opts \\ []), do: Objects.get(client, @type_name, id, opts)

  @doc "Searches deals. See `HubspotClient.Objects.search/3`."
  def search(client, query), do: Objects.search(client, @type_name, query)

  @doc "Batch reads deals by ID. See `HubspotClient.Objects.batch_read/4`."
  def batch_read(client, ids, opts \\ []), do: Objects.batch_read(client, @type_name, ids, opts)

  @doc "Streams every deal. See `HubspotClient.Objects.stream/3`."
  def stream(client, opts \\ []), do: Objects.stream(client, @type_name, opts)
end
```

Create `lib/hubspot_client/companies.ex`, the same five functions with:

```elixir
defmodule HubspotClient.Companies do
  @moduledoc """
  Read access to companies.

  A thin delegation to `HubspotClient.Objects` with the `"companies"` object
  type applied. See that module for the full option list.
  """

  alias HubspotClient.Objects

  @type_name "companies"

  @doc "Lists one page of companies. See `HubspotClient.Objects.list/3`."
  def list(client, opts \\ []), do: Objects.list(client, @type_name, opts)

  @doc "Reads a single company. See `HubspotClient.Objects.get/4`."
  def get(client, id, opts \\ []), do: Objects.get(client, @type_name, id, opts)

  @doc "Searches companies. See `HubspotClient.Objects.search/3`."
  def search(client, query), do: Objects.search(client, @type_name, query)

  @doc "Batch reads companies by ID. See `HubspotClient.Objects.batch_read/4`."
  def batch_read(client, ids, opts \\ []), do: Objects.batch_read(client, @type_name, ids, opts)

  @doc "Streams every company. See `HubspotClient.Objects.stream/3`."
  def stream(client, opts \\ []), do: Objects.stream(client, @type_name, opts)
end
```

Create `lib/hubspot_client/contacts.ex` with `@type_name "contacts"` and the
same five functions, `@moduledoc` reading "Read access to contacts."

Create `lib/hubspot_client/tickets.ex` with `@type_name "tickets"` and the same
five functions, `@moduledoc` reading "Read access to tickets." Add this note to
its `@moduledoc`:

```
Tickets use the legacy `tickets` scope rather than a `crm.objects.tickets.read`
scope. If ticket calls return 403 while deals and companies work, that scope is
the thing to check.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test`
Expected: PASS, 20 resource tests plus everything prior.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/hubspot_client/deals.ex lib/hubspot_client/companies.ex \
        lib/hubspot_client/contacts.ex lib/hubspot_client/tickets.ex \
        test/hubspot_client/resources_test.exs
git commit -m "feat: add deals, companies, contacts, and tickets modules"
```

---

### Task 9: Pipelines and stages

**Files:**
- Create: `lib/hubspot_client/pipelines.ex`
- Test: `test/hubspot_client/pipelines_test.exs`

**Interfaces:**
- Consumes: `Request.get/3` (Task 4), `Response.collection/2` and `Response.metadata/1` (Task 3)
- Produces:
  - `HubspotClient.Pipelines.list(client, object_type :: String.t(), opts :: keyword()) :: {:ok, list(map())} | {:error, Exception.t()}`
  - `HubspotClient.Pipelines.get(client, object_type, pipeline_id, opts) :: {:ok, map()} | {:error, Exception.t()}`
  - `HubspotClient.Pipelines.stages(client, object_type, pipeline_id, opts) :: {:ok, list(map())} | {:error, Exception.t()}`

  All three return metadata-normalized maps with atom keys. None paginate.

- [ ] **Step 1: Write the failing test**

Create `test/hubspot_client/pipelines_test.exs`:

```elixir
defmodule HubspotClient.PipelinesTest do
  use ExUnit.Case, async: true

  alias HubspotClient.Pipelines

  setup do
    client =
      HubspotClient.new(
        token: "t",
        req_options: [plug: {Req.Test, HubspotClient}, retry: false]
      )

    {:ok, client: client}
  end

  test "list/3 returns a plain list with atom keys", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/pipelines/deals"

      Req.Test.json(conn, %{
        "results" => [
          %{
            "id" => "default",
            "label" => "Sales Pipeline",
            "displayOrder" => 0,
            "createdAt" => "2026-01-01T00:00:00Z",
            "stages" => [
              %{
                "id" => "appointmentscheduled",
                "label" => "Appointment Scheduled",
                "displayOrder" => 0,
                "metadata" => %{"isClosed" => "false", "probability" => "0.2"}
              }
            ]
          }
        ]
      })
    end)

    assert {:ok, [pipeline]} = Pipelines.list(client, "deals")
    assert pipeline.id == "default"
    assert pipeline.label == "Sales Pipeline"
    assert pipeline.display_order == 0
    assert pipeline.created_at == ~U[2026-01-01 00:00:00Z]
    assert [stage] = pipeline.stages
    assert stage.label == "Appointment Scheduled"
    assert stage.metadata.is_closed == "false"
  end

  test "list/3 works for tickets", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/pipelines/tickets"
      Req.Test.json(conn, %{"results" => []})
    end)

    assert {:ok, []} = Pipelines.list(client, "tickets")
  end

  test "get/4 reads a single pipeline", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/pipelines/deals/default"
      Req.Test.json(conn, %{"id" => "default", "label" => "Sales Pipeline"})
    end)

    assert {:ok, %{id: "default", label: "Sales Pipeline"}} =
             Pipelines.get(client, "deals", "default")
  end

  test "stages/4 lists a pipeline's stages", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/pipelines/deals/default/stages"
      Req.Test.json(conn, %{"results" => [%{"id" => "1", "label" => "Appointment"}]})
    end)

    assert {:ok, [%{id: "1", label: "Appointment"}]} =
             Pipelines.stages(client, "deals", "default")
  end

  test "propagates errors", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"message" => "missing scope"})
    end)

    assert {:error, %HubspotClient.Error{status: 403}} = Pipelines.list(client, "deals")
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/hubspot_client/pipelines_test.exs`
Expected: FAIL — `HubspotClient.Pipelines is not available`.

- [ ] **Step 3: Write the implementation**

Create `lib/hubspot_client/pipelines.ex`:

```elixir
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
```

The `_opts` arguments are accepted and ignored: these endpoints take no query
parameters today, and keeping the arity stable means adding one later is not a
breaking change.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test`
Expected: PASS, all tests green.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/hubspot_client/pipelines.ex test/hubspot_client/pipelines_test.exs
git commit -m "feat: add pipelines and stages"
```

---

### Task 10: Properties and owners

**Files:**
- Create: `lib/hubspot_client/properties.ex`
- Create: `lib/hubspot_client/owners.ex`
- Test: `test/hubspot_client/properties_test.exs`
- Test: `test/hubspot_client/owners_test.exs`

**Interfaces:**
- Consumes: `Request.get/3` (Task 4), `Response.collection/2`, `Response.paged/2`, `Response.metadata/1` (Task 3)
- Produces:
  - `HubspotClient.Properties.list(client, object_type, opts) :: {:ok, list(map())} | {:error, Exception.t()}`
  - `HubspotClient.Properties.get(client, object_type, property_name, opts) :: {:ok, map()} | {:error, Exception.t()}`
  - `HubspotClient.Owners.list(client, opts) :: {:ok, %{results: list(map()), after: String.t() | nil}} | {:error, Exception.t()}`
  - `HubspotClient.Owners.get(client, owner_id, opts) :: {:ok, map()} | {:error, Exception.t()}`

  Properties do not paginate and return a plain list. Owners **do** paginate and return the paged envelope.

- [ ] **Step 1: Write the failing tests**

Create `test/hubspot_client/properties_test.exs`:

```elixir
defmodule HubspotClient.PropertiesTest do
  use ExUnit.Case, async: true

  alias HubspotClient.Properties

  setup do
    client =
      HubspotClient.new(
        token: "t",
        req_options: [plug: {Req.Test, HubspotClient}, retry: false]
      )

    {:ok, client: client}
  end

  test "list/3 returns property definitions with atom keys", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/properties/deals"

      Req.Test.json(conn, %{
        "results" => [
          %{
            "name" => "dealname",
            "label" => "Deal Name",
            "type" => "string",
            "fieldType" => "text",
            "groupName" => "dealinformation"
          }
        ]
      })
    end)

    assert {:ok, [property]} = Properties.list(client, "deals")
    assert property.name == "dealname"
    assert property.field_type == "text"
    assert property.group_name == "dealinformation"
  end

  test "list/3 keeps portal-defined property names as string values", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      Req.Test.json(conn, %{"results" => [%{"name" => "custom_locum_specialty"}]})
    end)

    assert {:ok, [%{name: "custom_locum_specialty"}]} = Properties.list(client, "deals")
  end

  test "get/4 reads a single property definition", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/properties/deals/dealstage"

      Req.Test.json(conn, %{
        "name" => "dealstage",
        "options" => [%{"label" => "Won", "value" => "closedwon", "displayOrder" => 1}]
      })
    end)

    assert {:ok, %{name: "dealstage", options: [option]}} =
             Properties.get(client, "deals", "dealstage")

    assert option.value == "closedwon"
    assert option.display_order == 1
  end
end
```

Create `test/hubspot_client/owners_test.exs`:

```elixir
defmodule HubspotClient.OwnersTest do
  use ExUnit.Case, async: true

  alias HubspotClient.Owners

  setup do
    client =
      HubspotClient.new(
        token: "t",
        req_options: [plug: {Req.Test, HubspotClient}, retry: false]
      )

    {:ok, client: client}
  end

  test "list/2 returns a paged envelope", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/owners"

      Req.Test.json(conn, %{
        "results" => [
          %{
            "id" => "77",
            "email" => "rep@example.com",
            "firstName" => "Alex",
            "lastName" => "Kim",
            "userId" => 991,
            "createdAt" => "2026-01-01T00:00:00Z",
            "archived" => false
          }
        ],
        "paging" => %{"next" => %{"after" => "c1"}}
      })
    end)

    assert {:ok, %{results: [owner], after: "c1"}} = Owners.list(client)
    assert owner.email == "rep@example.com"
    assert owner.first_name == "Alex"
    assert owner.user_id == 991
    assert owner.created_at == ~U[2026-01-01 00:00:00Z]
  end

  test "list/2 forwards limit, after, and archived", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["limit"] == "50"
      assert conn.query_params["after"] == "c1"
      assert conn.query_params["archived"] == "true"
      Req.Test.json(conn, %{"results" => []})
    end)

    assert {:ok, _} = Owners.list(client, limit: 50, after: "c1", archived: true)
  end

  test "get/3 reads a single owner", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/owners/77"
      Req.Test.json(conn, %{"id" => "77", "email" => "rep@example.com"})
    end)

    assert {:ok, %{id: "77", email: "rep@example.com"}} = Owners.get(client, "77")
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/hubspot_client/properties_test.exs test/hubspot_client/owners_test.exs`
Expected: FAIL — modules not available.

- [ ] **Step 3: Write the implementations**

Create `lib/hubspot_client/properties.ex`:

```elixir
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
```

Create `lib/hubspot_client/owners.ex`:

```elixir
defmodule HubspotClient.Owners do
  @moduledoc """
  Read access to owners — the HubSpot users records can be assigned to.

  A record's `hubspot_owner_id` property holds an owner ID; join it against this
  list to get a name or email.

  Unlike pipelines and properties, this endpoint paginates, so `list/2` returns
  the `%{results: ..., after: ...}` envelope.
  """

  alias HubspotClient.{Request, Response}

  @param_keys [:limit, :after, :archived, :email]

  @doc """
  Lists one page of owners.

  ## Options

    * `:limit` - records per page.
    * `:after` - paging cursor from a previous call.
    * `:archived` - `true` to list deactivated owners.
    * `:email` - filter to the owner with this email address.
  """
  @spec list(HubspotClient.t(), keyword()) ::
          {:ok, %{results: list(map()), after: String.t() | nil}} | {:error, Exception.t()}
  def list(client, opts \\ []) do
    with {:ok, body} <- Request.get(client, "/crm/v3/owners", params(opts)) do
      {:ok, Response.paged(body, &Response.metadata/1)}
    end
  end

  @doc """
  Reads a single owner by ID.
  """
  @spec get(HubspotClient.t(), String.t() | integer(), keyword()) ::
          {:ok, map()} | {:error, Exception.t()}
  def get(client, owner_id, opts \\ []) do
    path = "/crm/v3/owners/" <> (owner_id |> to_string() |> URI.encode(&URI.char_unreserved?/1))

    with {:ok, body} <- Request.get(client, path, params(opts)) do
      {:ok, Response.metadata(body)}
    end
  end

  defp params(opts) do
    opts
    |> Keyword.take(@param_keys)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test`
Expected: PASS, all tests green.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/hubspot_client/properties.ex lib/hubspot_client/owners.ex \
        test/hubspot_client/properties_test.exs test/hubspot_client/owners_test.exs
git commit -m "feat: add properties and owners"
```

---

### Task 11: Associations

**Files:**
- Create: `lib/hubspot_client/associations.ex`
- Test: `test/hubspot_client/associations_test.exs`

**Interfaces:**
- Consumes: `Request.get/3` (Task 4), `Response.paged/2`, `Response.metadata/1` (Task 3)
- Produces: `HubspotClient.Associations.list(client, from_type :: String.t(), from_id :: String.t() | integer(), to_type :: String.t(), opts :: keyword()) :: {:ok, %{results: list(map()), after: String.t() | nil}} | {:error, Exception.t()}`

- [ ] **Step 1: Write the failing test**

Create `test/hubspot_client/associations_test.exs`:

```elixir
defmodule HubspotClient.AssociationsTest do
  use ExUnit.Case, async: true

  alias HubspotClient.Associations

  setup do
    client =
      HubspotClient.new(
        token: "t",
        req_options: [plug: {Req.Test, HubspotClient}, retry: false]
      )

    {:ok, client: client}
  end

  test "list/5 hits the v4 associations path and decodes a page", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v4/objects/deals/123/associations/companies"

      Req.Test.json(conn, %{
        "results" => [
          %{
            "toObjectId" => 456,
            "associationTypes" => [
              %{"category" => "HUBSPOT_DEFINED", "typeId" => 5, "label" => nil}
            ]
          }
        ],
        "paging" => %{"next" => %{"after" => "c1"}}
      })
    end)

    assert {:ok, %{results: [association], after: "c1"}} =
             Associations.list(client, "deals", 123, "companies")

    assert association.to_object_id == 456
    assert [%{category: "HUBSPOT_DEFINED", type_id: 5}] = association.association_types
  end

  test "list/5 forwards limit and after", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["limit"] == "500"
      assert conn.query_params["after"] == "c1"
      Req.Test.json(conn, %{"results" => []})
    end)

    assert {:ok, %{results: [], after: nil}} =
             Associations.list(client, "deals", "123", "contacts", limit: 500, after: "c1")
  end

  test "propagates errors", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "no such deal"})
    end)

    assert {:error, %HubspotClient.Error{status: 404}} =
             Associations.list(client, "deals", "nope", "companies")
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/hubspot_client/associations_test.exs`
Expected: FAIL — `HubspotClient.Associations is not available`.

- [ ] **Step 3: Write the implementation**

Create `lib/hubspot_client/associations.ex`:

```elixir
defmodule HubspotClient.Associations do
  @moduledoc """
  Read the records associated with a record — a deal's companies, a company's
  contacts, a ticket's deals.

  This uses the v4 associations API, which returns the associated record's ID
  plus the association types, not the record itself. Fetch the records
  themselves with `HubspotClient.Objects.batch_read/4` on the returned IDs.

      {:ok, %{results: links}} =
        HubspotClient.Associations.list(client, "deals", deal_id, "companies")

      {:ok, companies} =
        HubspotClient.Companies.batch_read(client, Enum.map(links, & &1.to_object_id))

  For a small number of associated types, passing `:associations` to
  `HubspotClient.Objects.list/3` is one request instead of two.

  This endpoint paginates.
  """

  alias HubspotClient.{Request, Response}

  @param_keys [:limit, :after]

  @doc """
  Lists the associations from one record to an object type.

  ## Options

    * `:limit` - associations per page.
    * `:after` - paging cursor from a previous call.
  """
  @spec list(HubspotClient.t(), String.t(), String.t() | integer(), String.t(), keyword()) ::
          {:ok, %{results: list(map()), after: String.t() | nil}} | {:error, Exception.t()}
  def list(client, from_type, from_id, to_type, opts \\ []) do
    path =
      "/crm/v4/objects/" <>
        segment(from_type) <>
        "/" <> segment(from_id) <> "/associations/" <> segment(to_type)

    with {:ok, body} <- Request.get(client, path, params(opts)) do
      {:ok, Response.paged(body, &Response.metadata/1)}
    end
  end

  defp params(opts) do
    opts
    |> Keyword.take(@param_keys)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp segment(value), do: value |> to_string() |> URI.encode(&URI.char_unreserved?/1)
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test`
Expected: PASS, all tests green.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/hubspot_client/associations.ex test/hubspot_client/associations_test.exs
git commit -m "feat: add associations"
```

---

### Task 12: README and final verification

**Files:**
- Modify: `README.md` (replace the generated scaffold entirely)

**Interfaces:**
- Consumes: every public module
- Produces: nothing consumed by code

- [ ] **Step 1: Replace `README.md`**

````markdown
# HubspotClient

A small, read-only Elixir client for the HubSpot CRM API, built on
[Req](https://hex.pm/packages/req).

It lists and reads deals, companies, contacts, tickets, pipelines, stages,
property definitions, owners, and associations. It creates, updates, and
deletes nothing.

## Installation

```elixir
def deps do
  [{:hubspot_client, "~> 0.1.0"}]
end
```

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
Endpoints that do not (pipelines, stages, properties) return a plain list.

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

## Testing against this library

Pass a `Req.Test` stub through `:req_options`:

```elixir
client = HubspotClient.new(token: "test", req_options: [plug: {Req.Test, MyStub}])
```
````

- [ ] **Step 2: Verify the whole suite**

Run: `mix test`
Expected: PASS, 0 failures.

- [ ] **Step 3: Verify formatting is clean**

Run: `mix format --check-formatted`
Expected: no output, exit status 0.

- [ ] **Step 4: Verify compilation is warning-free**

Run: `mix compile --force --warnings-as-errors`
Expected: compiles with no warnings.

- [ ] **Step 5: Verify docs build**

Run: `mix docs`
Expected: writes `doc/index.html` with no warnings about broken references.

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: write README with setup, usage, and credential guidance"
```

---

## Verification checklist

Run after Task 12. Every line must pass before the library is considered done.

- [ ] `mix test` — 0 failures
- [ ] `mix format --check-formatted` — clean
- [ ] `mix compile --force --warnings-as-errors` — clean
- [ ] `mix docs` — builds, no broken reference warnings
- [ ] `grep -rn "Req.post\|Req.patch\|Req.delete\|Req.put" lib/` — no results outside `Request.post/3`, confirming the read-only boundary
- [ ] `grep -rn "hello" lib/ test/` — no results, confirming the scaffold is gone

### Optional smoke test against a real portal

Not part of the suite — no test should require network access. Run by hand once
a service key exists:

```bash
HUBSPOT_TOKEN=... mix run -e '
client = HubspotClient.new(token: System.fetch_env!("HUBSPOT_TOKEN"))
{:ok, pipelines} = HubspotClient.Pipelines.list(client, "deals")
IO.inspect(Enum.map(pipelines, & &1.label), label: "pipelines")
{:ok, %{results: deals}} = HubspotClient.Deals.list(client, limit: 3, properties: ["dealname"])
IO.inspect(Enum.map(deals, & &1.properties["dealname"]), label: "deals")
'
```

A 403 here means a missing scope; the `HubspotClient.Error` message names the
category.
