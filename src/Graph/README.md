# Graph Subsystem — Usage Guide

A lightweight property-graph layer on InterSystems IRIS. Edges live in the
`^GraphData` globals and are queryable with the `Graph.Tools` traversal APIs
(single-hop, multi-hop, shortest path, BFS). There are **two ways to populate
the graph** — both feed the same globals and are queried by the **same** engine:

- **Low-level data-layer graph** (the foundation) — write edges **directly** to
  the store with `Graph.Store.AddEdge` / `RemoveEdge`. Nodes are **generic node
  keys** and need not be backed by any class (virtual / synthetic node types),
  e.g. the GraphRAG knowledge graph `ProjectKB.KBGraph` (§1).
- **Object-projected graph** — any persistent class extends `Graph.Object.Base`
  and turns selected reference properties into **graph edges** that are
  maintained automatically on every insert / update / delete, through **both the
  object layer and SQL** (§2–§4).

---

## 1. Concepts — the data-layer graph (foundation)

At its core the graph is just typed, directed **edges between node keys**,
stored in globals. This layer knows nothing about objects — you can build a
complete graph over synthetic / virtual nodes that have **no `%Persistent`
class** at all.

### Node key
A node is identified by an opaque **node key** — **any application-defined
identifier**. A convenient convention is `$ListBuild(id, type)`, but the key can
be any value:

```objectscript
Set kb  = $ListBuild("KB-001", "Knowledge")
Set ent = $ListBuild("FHIR",   "Entity")
```

(The object-projected graph in §2 uses a *specific* form of node key — the OID
`$ListBuild(Id, ClassName)` — but the store itself treats every key generically.)

### Edge
A directed, typed link between two nodes:

```
(SourceNode) --[Relation]--> (TargetNode)
```

### Globals
| Global | Shape | Purpose |
|--------|-------|---------|
| `^GraphData.OUT` | `(Source, Target, Relation) = ""` | The edges — used for **querying** (forward). Subscripts are **node keys**. |
| `^GraphData.IN` | `(Target, Source, Relation) = ""` | **In-edge index** — a pure mirror of `OUT` keyed by target; makes **reverse** queries O(in-degree). Maintained automatically by `Graph.Store`; consumed by `Graph.Tools` (§9). |

You never write these globals by hand; `Graph.Store` maintains them for you.

### Writing edges directly
When the nodes are synthetic / virtual, write edges through the core data-layer
writer `Graph.Store`:

```objectscript
Do ##class(Graph.Store).AddEdge(kb, "MENTIONS", ent)      // OUT + IN maintained
// ... later ...
Do ##class(Graph.Store).RemoveEdge(kb, "MENTIONS", ent)   // removes OUT + IN
```

- `AddEdge(Source, Relation, Target)` writes the forward edge
  `^GraphData.OUT(Source, Target, Relation)` **and** the in-edge mirror
  `^GraphData.IN(Target, Source, Relation)`; `RemoveEdge` removes both.
- These nodes have **no** `^GraphData.OWN` ownership rows and **no** functional
  index — you add/remove edges yourself (e.g. a full `Rebuild()` / `Clear()`).
- Node descriptions/attributes (which `^GraphData.OUT` cannot hold) go in your
  own global, keyed by node key.
- Querying works the same as for any graph data: `Graph.Tools` / `Graph.SQL` /
  REST all read `^GraphData.OUT` / `^GraphData.IN`, whichever way the edges were
  written.

Reference use case: `ProjectKB.KBGraph` (GraphRAG knowledge graph) builds a
Knowledge / Entity / Capability graph entirely via `Graph.Store` — no persistent
node classes.

---

## 2. The object-projected graph

The object-projected graph builds the **same** edges automatically from your
**persistent classes**: mark reference properties as graph properties and the
edges are maintained on every insert / update / delete, through both the object
layer and SQL.

### Node (OID)
Here every saved row of a graph-enabled class is a **node**, identified by its
**OID** — the object graph's specific form of the generic node key from §1:

```
NodeOID = $ListBuild(Id, ClassName)
```

e.g. `$lb("2","Test.SalesOrder")`.

### Additional globals
On top of `^GraphData.OUT` / `^GraphData.IN` (§1), the object-projected graph
uses two more globals, **specific to the object graph**:

| Global | Shape | Purpose |
|--------|-------|---------|
| `^GraphData.Dic` | `(SourceType, Relation, TargetType, Inverse) = PropName` | Graph dictionary — built at **compile time**. |
| `^GraphData.OWN` | `(OwnerOID, SourceOID, Relation, TargetOID) = ""` | Which node **owns** each edge — used for maintenance (fast delete/rebuild). |

### Defining a graph class

Extend `Graph.Object.Base` (in addition to `%Persistent`) and mark reference
properties with the graph parameters.

```objectscript
Class Logistics.Business.Product Extends (%Persistent, Graph.Object.Base)
{

Property SKU As %String;
Property Name As %String;

/// classified_as : Product -> HSCode
Property HSCode As Logistics.Policy.HSCode(Direction = "FROM", Relation = "classified_as");

/// supplies : Supplier -> Product  (many Products belong to one Supplier)
Relationship Supplier As Logistics.Business.Supplier(Direction = "FROM", Relation = "supplies") [ Cardinality = one, Inverse = Products ];

}
```

That is all. On compile, a projection (`Graph.Object.IndexProjection`) automatically
injects the functional indexes that maintain the edges. **No manual index
declaration is needed.**

### Graph property parameters
Defined in `Graph.Object.PropertyParameters`:

| Parameter | Values | Meaning |
|-----------|--------|---------|
| `Direction` | `FROM` / `TO` | **Marks the property as a graph property** and is recorded in the dictionary. A property is a graph property **only if `Direction` is set**. |
| `Relation` | string | The edge type, e.g. `"supplies"`, `"Customer-SalesOrder"`. Defaults to the property name. |
| `Inverse` | `1` / `0` | Force the edge to be recorded in the reverse direction (see below). Default `0`. |
| `GraphUse` | `1` / `0` | Only relevant in `Auto` mode: set to `0` to explicitly **exclude** a property that would otherwise be auto-included. |

Supported property kinds (the referenced target class must be a
**non-`%Library.SerialObject`** type — i.e. a persistent reference; embedded /
serial objects are not graph properties):
- **Scalar reference** — `Property X As SomeClass(Direction=...)`
- **Relationship** — `Relationship X As SomeClass(Direction=...) [ Cardinality = one/many, Inverse = ... ]`
- **Collection** — `Property X As list of SomeClass(Direction=...)` or `array of`

> Note: parent-child relationships (`Cardinality = parent`) are currently **not
> supported** due to a known issue.

### Auto mode (`Auto` class parameter)

Set the class parameter `Auto = 1` on a graph class and the projection will
**automatically** include qualifying reference properties in the graph at compile
time, without hand-writing `Direction` on each one:

```objectscript
Class Logistics.Business.Product Extends (%Persistent, Graph.Object.Base)
{
Parameter Auto = 1;

Property Name As %String;                          // literal → ignored
Property HSCode As Logistics.Policy.HSCode;        // persistent reference → auto-included
Property Supplier As Logistics.Business.Supplier;  // persistent reference → auto-included
}
```

- When `Auto` is undefined it **defaults to `0`** (off; identical to prior behavior).
- With `Auto = 1`, the projection **physically injects `Direction = "TO"`,
  `Relation = <PropertyName>`, `Inverse = 0`** onto qualifying property definitions
  at compile time (becoming the single source of truth for the class). Qualification rules:
  - **Included**: scalar reference / relationship / list / array collection whose target is a persistent class;
  - **Excluded**: literal datatypes, `%SerialObject` embedded objects, the "one" side of a one-to-many (`Cardinality = one` / relationship one side), and the parent side of a parent-child relationship (`children`).
- **User settings are never overwritten**: if a property already declares `Direction`,
  or already has a manually set `Relation` / `Inverse`, those values are **preserved** —
  `Auto` only fills in the missing parameters.
- Set `GraphUse = 0` to **exclude** a property that would otherwise be auto-included.

---

## 3. Edge direction rules

The stored edge normally goes **from this object to the referenced object**:

```
(thisNode) --[Relation]--> (referencedNode)
```

The edge is **reversed** (referenced → this) when the property is the *many /
child* endpoint, i.e. any of:

- `Cardinality = one`
- `Cardinality = parent` *(currently unsupported — see §2)*
- `Inverse = 1`

This keeps edges pointing consistently from the **"one"** side to the
**"many"** side. Examples:

| Declaration | Stored edge |
|-------------|-------------|
| `Product.HSCode` (scalar) | `Product --classified_as--> HSCode` |
| `Product.Supplier` (Cardinality one) | `Supplier --supplies--> Product` |
| `RouteSegment.PassesThrough` (list) | `RouteSegment --passes_through--> Location` (one edge per element) |
| `SalesOrder.Customer` (Inverse 1) | `Customer --Customer-SalesOrder--> SalesOrder` |

The edge is always **owned by the object that declares the property**, so
deleting/updating that object cleans up exactly its edges.

---

## 4. Automatic maintenance

Once a class is graph-enabled, edges are maintained on **every** data-change
path — you do not call anything:

| Operation | Object layer | SQL layer |
|-----------|--------------|-----------|
| Insert | `obj.%Save()` (new) | `INSERT INTO ...` |
| Update | `obj.%Save()` (existing) | `UPDATE ...` (incl. multi-row) |
| Delete | `%DeleteId()` / `%Delete()` | `DELETE FROM ...` (incl. multi-row) |

Behavior:
- **Insert** — reads current property values and adds one edge per non-null reference (one per collection element).
- **Update** — removes all edges owned by the row, then rebuilds from current values (safe when the foreign key changes; no dangling edges).
- **Delete** — removes all edges owned by the row (no need to read old values).
- **Null reference** — produces no edge.

> Verified: object and SQL insert/update/delete (including bulk `UPDATE … WHERE`
> and `DELETE … WHERE` and null foreign keys) all maintain `^GraphData.OUT` /
> `^GraphData.OWN` correctly, including on the *many* side of a one-to-many
> relationship.

### Rebuilding edges for existing data
The injected indexes support `BUILD INDEX`, so you can (re)populate edges for a
class whose data already exists:

```objectscript
Do ##class(%SYSTEM.OBJ).Compile("Logistics.Business.Product")   // ensures index exists
Do ##class(Logistics.Business.Product).%BuildIndices()          // rebuilds all indices incl. GraphIndex*
```

`PurgeIndex` (called during rebuild) clears the class's existing edges first, so
rebuilds are idempotent.

---

## 5. Querying with `Graph.Tools`

All query methods return a `%DynamicArray` of hop objects shaped as:

```json
{ "OID": "<sourceOID>", "Relation": "<rel>", "TargetOID": "<targetOID>" }
```

where each OID is a `$ListBuild(Id, ClassName)` value.

### Single hop
```objectscript
Set node = $ListBuild(customerId, "Test.Customer")

// Outgoing edges from node (all relations)
Do ##class(Graph.Tools).SingleHop(node, "", 0, .result)

// Only specific relations (comma-separated)
Do ##class(Graph.Tools).SingleHop(node, "supplies,classified_as", 0, .result)

// Incoming edges (who points AT node) -> set pInverse = 1
Do ##class(Graph.Tools).SingleHop(node, "", 1, .result)
```

### Multi hop (ordered relation path)
```objectscript
Set rels = [
  {"Relation":"Opportunity-Product","Inverse":0},
  {"Relation":"Opportunity-Sales","Inverse":1}
]
Do ##class(Graph.Tools).MultiHop(startNode, rels, .result)
```

### Shortest path (undirected BFS over edges)
```objectscript
Do ##class(Graph.Tools).ShortestPath(startNode, endNode, .path)
// path = ordered array of hop steps, each with Relation / Inverse / OID / TargetOID
```

### Breadth-first traversal with depth limit
```objectscript
Do ##class(Graph.Tools).BFS(startNode, 3, .result)   // up to 3 hops
```

### `*WithNO` variants (query by business number)
`SingleHopWithNO`, `MultiHopWithNO`, `ShortestPathWithNO`, `BFSWithNO` (in
`Graph.Object.Tools`, a subclass of `Graph.Tools` for object-backed graph data)
accept a **class name + business number** instead of an OID. They resolve the
node via a class method your class must implement:

```objectscript
ClassMethod GetOIDByNO(pNO As %String) As %String
{
    // return $ListBuild(id, $classname()) for the row whose business number = pNO, else ""
}
```

Example:
```objectscript
Do ##class(Graph.Object.Tools).SingleHopWithNO("Logistics.Business.Product", "SKU-001", "supplies", 1, .result)
```

---

## 6. Querying from SQL

The same traversals are exposed as **custom SQL table-valued functions** in
`Graph.SQL`. They read the graph globals directly — **they are not backed by any
SQL table** — and return standard result sets usable in the `FROM` clause,
including joins back to your base tables.

Nodes are passed as two arguments `(Class, Id)` (equivalent to the internal
`$ListBuild(Id, Class)` OID) and returned as separate `Class` / `Id` columns.

| Function | Signature | Columns |
|----------|-----------|---------|
| `Graph.SingleHop` | `(class, id, relation, inverse)` | `SourceClass, SourceId, Relation, TargetClass, TargetId` |
| `Graph.MultiHop` | `(class, id, relPath)` | same 5 columns (final hop of each path) |
| `Graph.BFS` | `(class, id, maxDepth)` | same 5 columns |
| `Graph.ShortestPath` | `(startClass, startId, endClass, endId)` | `StepNo, Relation, Inverse, SourceClass, SourceId, TargetClass, TargetId` |

- `relation` filter: empty = all; comma-separated = multiple.
- `inverse`: `0` = outgoing edges (node is source), `1` = incoming edges (node is target).
- `relPath` (MultiHop): ordered `"Relation:Inverse,Relation:Inverse,..."`, e.g. `'Customer-SalesOrder:0'`.

```sql
-- outgoing edges from a customer
SELECT * FROM Graph.SingleHop('Test.Customer', 8, '', 0);

-- who points AT this order (incoming)
SELECT * FROM Graph.SingleHop('Test.SalesOrder', 8, '', 1);

-- join the graph result back to the base table
SELECT h.TargetId AS OrderId, so.TotalAmount
FROM Graph.SingleHop('Test.Customer', 8, 'Customer-SalesOrder', 0) h
JOIN Test.SalesOrder so ON so.ID = h.TargetId;

-- multi-hop path
SELECT * FROM Graph.MultiHop('Test.Customer', 8, 'Customer-SalesOrder:0');

-- breadth-first traversal, up to 2 hops
SELECT * FROM Graph.BFS('Test.Customer', 8, 2);

-- shortest path between two nodes (one row per step)
SELECT * FROM Graph.ShortestPath('Test.Customer', 8, 'Test.SalesOrder', 8);
```

---

## 7. Querying from REST (HTTP)

The traversals are also exposed as a **spec-first REST API** (`%REST`):

- `Graph.REST.spec` — OpenAPI 2.0 definition (the contract).
- `Graph.REST.impl` — business logic wrapping `Graph.Tools`.
- `Graph.REST.disp` — dispatch class, **auto-generated** when the spec compiles.
- Web application `/api/graph` → `Graph.REST.disp` (namespace `NEHR`).

All endpoints are `POST`, accept and return JSON. Nodes are expressed as
`{ "class": ..., "id": ... }` (or `{ "class": ..., "no": ... }` to resolve by
business number via `<class>.GetOIDByNO`). The internal OID is never exposed.

| Endpoint | Body | Result |
|----------|------|--------|
| `POST /api/graph/singlehop` | `{ node, relation?, inverse? }` | `{ edges:[{source,relation,target}], count }` |
| `POST /api/graph/multihop` | `{ node, relations:[{relation,inverse?}] }` | `{ endpoints:[…], count }` |
| `POST /api/graph/shortestpath` | `{ start, end }` | `{ found, length, path:[{step,relation,inverse,source,target}] }` |
| `POST /api/graph/bfs` | `{ node, maxDepth? }` | `{ maxDepth, edges:[…], count }` |
| `POST /api/graph/addedge` | `{ source, relation, target }` | `{ ok, source, relation, target }` |
| `POST /api/graph/removeedge` | `{ source, relation, target }` | `{ ok, source, relation, target }` |

- `relation`: empty = all; comma-separated = multiple.
- `inverse`: `0` = outgoing (node is source), `1` = incoming (node is target).
- Missing / invalid `node` returns `400` with `{ "error": ... }`.
- `addedge` / `removeedge` **write** low-level edges via `Graph.Store` (§1) —
  they maintain `^GraphData.OUT` / `^GraphData.IN` for the data-layer graph.
  Here `source` / `target` are **generic node keys** `{ class, id }` (mapped to
  `$ListBuild(id, class)`); the `no` business-number resolution does **not**
  apply. Use them only for the data-layer graph — object-projected edges are
  maintained automatically (§4).

```bash
# outgoing edges from a customer
curl -X POST http://<host>/api/graph/singlehop \
  -H 'Content-Type: application/json' \
  -d '{"node":{"class":"Test.Customer","id":"8"},"relation":"","inverse":0}'

# who points AT this order (incoming)
curl -X POST http://<host>/api/graph/singlehop \
  -H 'Content-Type: application/json' \
  -d '{"node":{"class":"Test.SalesOrder","id":"8"},"inverse":1}'

# multi-hop path
curl -X POST http://<host>/api/graph/multihop \
  -H 'Content-Type: application/json' \
  -d '{"node":{"class":"Test.Customer","id":"8"},"relations":[{"relation":"Customer-SalesOrder","inverse":0}]}'

# breadth-first traversal, up to 2 hops
curl -X POST http://<host>/api/graph/bfs \
  -H 'Content-Type: application/json' \
  -d '{"node":{"class":"Test.Customer","id":"8"},"maxDepth":2}'

# shortest path
curl -X POST http://<host>/api/graph/shortestpath \
  -H 'Content-Type: application/json' \
  -d '{"start":{"class":"Test.Customer","id":"8"},"end":{"class":"Test.SalesOrder","id":"8"}}'

# add a data-layer edge  KB-001 --MENTIONS--> FHIR
curl -X POST http://<host>/api/graph/addedge \
  -H 'Content-Type: application/json' \
  -d '{"source":{"class":"Knowledge","id":"KB-001"},"relation":"MENTIONS","target":{"class":"Entity","id":"FHIR"}}'

# remove that edge
curl -X POST http://<host>/api/graph/removeedge \
  -H 'Content-Type: application/json' \
  -d '{"source":{"class":"Knowledge","id":"KB-001"},"relation":"MENTIONS","target":{"class":"Entity","id":"FHIR"}}'
```

> Deploy: compiling `Graph.REST.spec` generates `Graph.REST.disp`; then create a
> web application mapping `/api/graph` to `Graph.REST.disp` in namespace `NEHR`
> (e.g. via `%REST.API.CreateApplication("Graph.REST")` or the Management Portal).

---

## 8. End-to-end example

```objectscript
// --- create data (edges are maintained automatically) ---
Set sup = ##class(Logistics.Business.Supplier).%New()
Set sup.Name = "ACME"
Do sup.%Save()

Set prod = ##class(Logistics.Business.Product).%New()
Set prod.SKU = "SKU-001"
Set prod.Supplier = sup          // -> edge  Supplier --supplies--> Product
Do prod.%Save()

// --- query: which products does this supplier supply? ---
Set supNode = $ListBuild(sup.%Id(), "Logistics.Business.Supplier")
Do ##class(Graph.Tools).SingleHop(supNode, "supplies", 0, .result)
Write result.%ToJSON()

// --- query: who supplies this product? (incoming edge) ---
Set prodNode = $ListBuild(prod.%Id(), "Logistics.Business.Product")
Do ##class(Graph.Tools).SingleHop(prodNode, "supplies", 1, .result)
Write result.%ToJSON()
```

---

## 9. Fast traversal — the in-edge index

`Graph.Tools` / `Graph.Object.Tools` are the query engine, accelerated for
**reverse and multi-hop** traversal by the in-edge index `^GraphData.IN`.

```objectscript
Do ##class(Graph.Tools).SingleHop(node, "", 1, .result)        // incoming edges
Do ##class(Graph.Object.Tools).SingleHopWithNO(class, no, "", 1, .result)
```

### What makes it fast
1. **In-edge index (`^GraphData.IN`).** A naive reverse query (`inverse=1`)
   would have to **full-scan** every edge in `^GraphData.OUT` to find who points
   *at* a node — O(E). `Graph.Tools` instead reads `^GraphData.IN(Target,
   Source, Relation)` directly, making a reverse hop **O(in-degree)**.
2. **`$Order`-based traversal + de-objectified intermediates.** Forward hops use
   `$Order` over `OUT`, reverse hops use `$Order` over `IN`; intermediate
   frontiers are kept as raw `$ListBuild` OIDs (no `%DynamicArray` churn) until
   the final result is materialized.
3. **Bidirectional BFS for `ShortestPath`.** Instead of a single-source BFS that
   fans out to depth `d`, `ShortestPath` expands **from both the start and the
   end simultaneously**, one level at a time, and stops when the two frontiers
   meet in the middle — exploring roughly O(b^(d/2)) nodes instead of O(b^d).
   (Shortest paths are not unique, so the specific path may differ when several
   equally-short paths exist.)

### Performance

Typical latencies on a 1,453-edge graph (each operation averaged over 500 runs):

| Operation | Latency |
|-----------|--------:|
| Single-hop forward | 6.6 ms |
| Single-hop reverse | 3.2 ms |
| MultiHop with a reverse step | 3.2 ms |
| BFS depth 3 (undirected) | 32.4 ms |
| ShortestPath (undirected) | 11.9 ms |

Cost model:

- **Reverse hops are O(in-degree).** They read `^GraphData.IN(Target, Source,
  Relation)` directly instead of scanning `^GraphData.OUT`, so `inverse = 1`
  queries stay cheap even on large graphs.
- **BFS and `ShortestPath` are undirected** — every visited node also expands its
  reverse edges, so they lean heavily on the in-edge index.
- **MultiHop** is accelerated whenever a step uses `Inverse = 1`; a pure-forward
  path is already fast via `$Order` over `^GraphData.OUT`.

### Maintaining `^GraphData.IN`
`^GraphData.IN` is kept in sync with `^GraphData.OUT` automatically — every edge
write goes through `Graph.Store`, which updates both globals together:

- **Object-projected graph** — maintained on insert / update / delete (§4); you
  do not call anything.
- **Data-layer graph** — `Graph.Store.AddEdge` / `RemoveEdge` update `IN`
  alongside `OUT` on every call.

`Graph.Store` also provides maintenance helpers:

```objectscript
Do ##class(Graph.Store).BuildIN()          // rebuild IN from OUT (idempotent full resync)
Do ##class(Graph.Store).Verify(.out, .in)  // consistent when out=in and 0 mirrors missing
```

Run `BuildIN()` to populate `^GraphData.IN` from existing `^GraphData.OUT` data
(e.g. the first time you enable it, or any time you suspect drift); it is
idempotent.

---

## 10. Quick reference

- **Enable (object-projected graph):** `Extends (%Persistent, Graph.Object.Base)` + set `Direction` & `Relation` on reference properties; or set the class parameter `Auto = 1` to auto-include persistent reference properties.
- **Data-layer graph (no objects):** write edges directly with `##class(Graph.Store).AddEdge(src, rel, tgt)` / `RemoveEdge(...)` (node key = `$ListBuild(id, type)`); same query APIs. See `ProjectKB.KBGraph`.
- **Reverse an edge:** `Inverse = 1`, or use a `Relationship` with `Cardinality = one` / `parent`.
- **Maintenance:** automatic on object & SQL insert/update/delete; nothing to call.
- **Rebuild existing data:** `%BuildIndices()`.
- **Query:** `Graph.Tools` → `SingleHop` / `MultiHop` / `ShortestPath` / `BFS` (works on any graph data, accelerated by the `^GraphData.IN` in-edge index for O(in-degree) reverse & multi-hop). For object-backed data, `Graph.Object.Tools` adds the `*WithNO` variants (query by business number). Run `##class(Graph.Store).BuildIN()` once to backfill the index for pre-existing data.
- **Query from SQL:** `Graph.SQL` table-valued functions → `Graph.SingleHop` / `Graph.MultiHop` / `Graph.BFS` / `Graph.ShortestPath` (usable in `FROM`, joinable, not table-backed).
- **Query from REST:** spec-first `%REST` API at `/api/graph` (`Graph.REST.spec` + `Graph.REST.impl`). Query → `POST /singlehop` / `/multihop` / `/shortestpath` / `/bfs`; write data-layer edges → `POST /addedge` / `/removeedge`.
- **Storage:** `^GraphData.OUT` (edges), `^GraphData.IN` (in-edge index), `^GraphData.OWN` (ownership), `^GraphData.Dic` (dictionary).

