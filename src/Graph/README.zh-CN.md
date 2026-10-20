# Graph 子系统 — 使用指南

一个构建在 InterSystems IRIS 之上的轻量级属性图（property-graph）层。边存放在
`^GraphData` 全局变量中，可通过 `Graph.Tools` 遍历 API（单跳、多跳、最短路径、BFS）
查询。**有两种方式向图中写入数据**，二者共用同一套全局变量、由**同一个**引擎查询：

- **底层数据层图**（基础） — 通过 `Graph.Store.AddEdge` / `RemoveEdge` **直接**向存储
  写入边。节点是**通用的节点键**，无需由任何类支撑（虚拟 / 合成节点类型），例如 GraphRAG
  知识库图谱 `ProjectKB.KBGraph`（见 §1）。
- **对象投影图** — 任意持久化类继承 `Graph.Object.Base`，将选定的引用属性转化为
  **图的边**，这些边在每次插入 / 更新 / 删除时自动维护——**同时覆盖对象层和 SQL 层**
  （见 §2–§4）。

---

## 1. 概念 — 底层数据层图（基础）

图的本质只是存放在全局变量中、**节点键之间**带类型的有向**边**。这一层完全不涉及对象——
你可以在没有任何 `%Persistent` 类的合成 / 虚拟节点之上构建一张完整的图。

### 节点键（Node key）
节点由一个不透明的**节点键**标识——**任意应用自定义标识**。常用约定是
`$ListBuild(id, type)`，但键可以是任意值：

```objectscript
Set kb  = $ListBuild("KB-001", "Knowledge")
Set ent = $ListBuild("FHIR",   "Entity")
```

（§2 的对象投影图使用节点键的一种*特定*形式——OID `$ListBuild(Id, ClassName)`——
但存储层本身对每个键都一视同仁地按通用键处理。）

### 边（Edge）
两个节点之间有向且带类型的连接：

```
(源节点) --[Relation]--> (目标节点)
```

### 全局变量（Globals）
| 全局变量 | 结构 | 用途 |
|--------|-------|---------|
| `^GraphData.OUT` | `(Source, Target, Relation) = ""` | 边本身（正向）——用于**正向查询**。下标为**节点键** Source/Target。 |
| `^GraphData.IN` | `(Target, Source, Relation) = ""` | **入边索引**——`OUT` 的纯镜像，以目标为键；让**反向**查询降为 O(入度)。由 `Graph.Store` 自动维护，由 `Graph.Tools` 使用（见 §9）。 |

你无需手工写入这些全局变量；`Graph.Store` 会自动为你维护。

### 直接写入边
当节点是合成 / 虚拟的，通过核心数据层写入器 `Graph.Store` 直接写边：

```objectscript
Do ##class(Graph.Store).AddEdge(kb, "MENTIONS", ent)      // 同时维护 OUT + IN
// ...稍后...
Do ##class(Graph.Store).RemoveEdge(kb, "MENTIONS", ent)   // 同时删除 OUT + IN
```

- `AddEdge(Source, Relation, Target)` 写正向边 `^GraphData.OUT(Source, Target, Relation)`
  **并**写入边镜像 `^GraphData.IN(Target, Source, Relation)`；`RemoveEdge` 两者一起删。
- 这类节点**没有** `^GraphData.OWN` 所有权记录、**也没有**函数索引——边由你自己
  增删（例如一个完整的 `Rebuild()` / `Clear()`）。
- 节点的描述 / 属性（`^GraphData.OUT` 存不了）请存在你自己的全局变量里，以节点键为键。
- 查询方式与任何图数据一致：`Graph.Tools` / `Graph.SQL` / REST 都只读
  `^GraphData.OUT` / `^GraphData.IN`，与边由哪种方式写入无关。

参考用例：`ProjectKB.KBGraph`（GraphRAG 知识库图谱）完全通过 `Graph.Store` 构建
Knowledge / Entity / Capability 图——没有任何持久化节点类。

---

## 2. 对象投影图

对象投影图从你的**持久化类**自动构建**同样**的边：把引用属性标记为图属性，边就会在
每次插入 / 更新 / 删除时自动维护——同时覆盖对象层和 SQL 层。


### 节点（OID）
在这里，启用图功能的类中每一行已保存的数据都是一个**节点**，由其 **OID** 标识——
即 §1 中通用节点键的特定形式：

```
NodeOID = $ListBuild(Id, ClassName)
```

例如 `$lb("2","Test.SalesOrder")`。

### 额外的全局变量
在 `^GraphData.OUT` / `^GraphData.IN`（见 §1）之上，对象投影图还使用两个**仅适用于
对象图**的全局变量：

| 全局变量 | 结构 | 用途 |
|--------|-------|---------|
| `^GraphData.Dic` | `(SourceType, Relation, TargetType, Inverse) = PropName` | 图字典——在**编译时**构建。 |
| `^GraphData.OWN` | `(OwnerOID, SourceOID, Relation, TargetOID) = ""` | 记录每条边由哪个节点**拥有**——用于维护（快速删除/重建）。 |

### 定义图类

在继承 `%Persistent` 的同时继承 `Graph.Object.Base`，并用图参数标注引用属性。

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

到此为止。编译时，一个投影（`Graph.Object.IndexProjection`）会自动注入用于维护边的
函数索引。**无需手工声明任何索引。**

### 图属性参数
定义于 `Graph.Object.PropertyParameters`：

| 参数 | 取值 | 含义 |
|-----------|--------|---------|
| `Direction` | `FROM` / `TO` | **将该属性标记为图属性**，并记录到字典中。属性**仅当设置了 `Direction`** 时才是图属性。 |
| `Relation` | 字符串 | 边的类型，例如 `"supplies"`、`"Customer-SalesOrder"`。默认取属性名。 |
| `Inverse` | `1` / `0` | 强制以反方向记录边（见下文）。默认 `0`。 |
| `GraphUse` | `1` / `0` | 仅在 `Auto` 模式下生效：设为 `0` 可显式将某个本会被自动纳入的属性**排除**在图之外。 |

支持的属性类型（引用的目标类须为**非 `%Library.SerialObject`** 类型，即持久化引用；嵌入 / 序列化对象不作为图属性）：
- **标量引用** — `Property X As SomeClass(Direction=...)`
- **关系（Relationship）** — `Relationship X As SomeClass(Direction=...) [ Cardinality = one/many, Inverse = ... ]`
- **集合（Collection）** — `Property X As list of SomeClass(Direction=...)` 或 `array of`

> 注意：父子关系（`Cardinality = parent`）目前因一个已知问题**暂不支持**。

### 自动模式（`Auto` 类参数）

在图类上设置类参数 `Auto = 1`，编译时投影会**自动**把符合条件的引用属性纳入图，
无需在每个属性上手写 `Direction`：

```objectscript
Class Logistics.Business.Product Extends (%Persistent, Graph.Object.Base)
{
Parameter Auto = 1;

Property Name As %String;                          // 字面量 → 忽略
Property HSCode As Logistics.Policy.HSCode;        // 持久化引用 → 自动纳入
Property Supplier As Logistics.Business.Supplier;  // 持久化引用 → 自动纳入
}
```

- 未定义 `Auto` 时**默认为 `0`**（关闭，行为与旧版本一致）。
- `Auto = 1` 时，投影会在**编译期把 `Direction = "TO"`、`Relation = <属性名>`、`Inverse = 0`
  显式注入**到符合条件的属性定义上（成为该类的单一事实来源）。自动纳入的判定规则：
  - **纳入**：目标为持久化类的标量引用 / 关系 / list / array 集合；
  - **排除**：字面量数据类型、`%SerialObject` 内嵌对象、一对多的"一"方（`Cardinality = one`/关系一侧）、父子关系的父方（`children`）。
- **不覆盖手工设置**：若属性已显式声明 `Direction`，或已手动设置 `Relation` / `Inverse`，
  这些值一律**保留**，`Auto` 只补齐缺失的参数。
- 设 `GraphUse = 0` 可把某个本会被自动纳入的属性**排除**在图之外。

---

## 3. 边的方向规则

存储的边通常**从当前对象指向被引用对象**：

```
(当前节点) --[Relation]--> (被引用节点)
```

当属性处于*多 / 子（many / child）*端点时，边会被**反向**（被引用节点 → 当前节点），
即以下任一情况：

- `Cardinality = one`
- `Cardinality = parent` *（目前暂不支持——见 §2）*
- `Inverse = 1`

这样可以保证边始终一致地从**"一（one）"**端指向**"多（many）"**端。示例：

| 声明 | 存储的边 |
|-------------|-------------|
| `Product.HSCode`（标量） | `Product --classified_as--> HSCode` |
| `Product.Supplier`（Cardinality one） | `Supplier --supplies--> Product` |
| `RouteSegment.PassesThrough`（list） | `RouteSegment --passes_through--> Location`（每个元素一条边） |
| `SalesOrder.Customer`（Inverse 1） | `Customer --Customer-SalesOrder--> SalesOrder` |

边始终由**声明该属性的对象所拥有**，因此删除/更新该对象时会精确清理其自身的边。

---

## 4. 自动维护

一旦某个类启用了图功能，边会在**每一条**数据变更路径上被维护——你无需调用任何东西：

| 操作 | 对象层 | SQL 层 |
|-----------|--------------|-----------|
| 插入 | `obj.%Save()`（新建） | `INSERT INTO ...` |
| 更新 | `obj.%Save()`（已存在） | `UPDATE ...`（含多行） |
| 删除 | `%DeleteId()` / `%Delete()` | `DELETE FROM ...`（含多行） |

行为：
- **插入** — 读取当前属性值，为每个非空引用添加一条边（集合中每个元素一条）。
- **更新** — 先删除该行拥有的所有边，再根据当前值重建（外键变更时也安全；不会产生悬空边）。
- **删除** — 删除该行拥有的所有边（无需读取旧值）。
- **空引用** — 不产生边。

> 已验证：对象层和 SQL 层的插入/更新/删除（包括批量 `UPDATE … WHERE`、
> `DELETE … WHERE` 以及空外键）都能正确维护 `^GraphData.OUT` /
> `^GraphData.OWN`，包括一对多关系的*多*端。

### 为已有数据重建边
注入的索引支持 `BUILD INDEX`，因此你可以为数据已存在的类（重新）填充边：

```objectscript
Do ##class(%SYSTEM.OBJ).Compile("Logistics.Business.Product")   // 确保索引存在
Do ##class(Logistics.Business.Product).%BuildIndices()          // 重建所有索引，包括 GraphIndex*
```

`PurgeIndex`（在重建期间调用）会先清空该类现有的边，因此重建操作是幂等的。

---

## 5. 使用 `Graph.Tools` 查询

所有查询方法都返回一个 `%DynamicArray`，其中每个跳（hop）对象的结构为：

```json
{ "OID": "<sourceOID>", "Relation": "<rel>", "TargetOID": "<targetOID>" }
```

其中每个 OID 都是一个 `$ListBuild(Id, ClassName)` 值。

### 单跳（Single hop）
```objectscript
Set node = $ListBuild(customerId, "Test.Customer")

// 从 node 出发的出边（所有关系）
Do ##class(Graph.Tools).SingleHop(node, "", 0, .result)

// 仅指定关系（逗号分隔）
Do ##class(Graph.Tools).SingleHop(node, "supplies,classified_as", 0, .result)

// 入边（谁指向 node）-> 设置 pInverse = 1
Do ##class(Graph.Tools).SingleHop(node, "", 1, .result)
```

### 多跳（有序关系路径）
```objectscript
Set rels = [
  {"Relation":"Opportunity-Product","Inverse":0},
  {"Relation":"Opportunity-Sales","Inverse":1}
]
Do ##class(Graph.Tools).MultiHop(startNode, rels, .result)
```

### 最短路径（对边进行无向 BFS）
```objectscript
Do ##class(Graph.Tools).ShortestPath(startNode, endNode, .path)
// path = 有序的跳步数组，每步含 Relation / Inverse / OID / TargetOID
```

### 带深度限制的广度优先遍历
```objectscript
Do ##class(Graph.Tools).BFS(startNode, 3, .result)   // 最多 3 跳
```

### `*WithNO` 变体（按业务编号查询）
`SingleHopWithNO`、`MultiHopWithNO`、`ShortestPathWithNO`、`BFSWithNO`（位于
`Graph.Object.Tools`，它是 `Graph.Tools` 的子类，专门处理基于对象的图数据）
接受**类名 + 业务编号**，而不是 OID。它们通过一个由你的类必须实现的类方法来解析节点：

```objectscript
ClassMethod GetOIDByNO(pNO As %String) As %String
{
    // 对业务编号 = pNO 的那一行返回 $ListBuild(id, $classname())，否则返回 ""
}
```

示例：
```objectscript
Do ##class(Graph.Object.Tools).SingleHopWithNO("Logistics.Business.Product", "SKU-001", "supplies", 1, .result)
```

---

## 6. 从 SQL 查询

同样的遍历以 `Graph.SQL` 中的**自定义 SQL 表值函数（table-valued functions）**形式暴露。
它们直接读取图全局变量——**并不依赖任何 SQL 表**——并返回可用于 `FROM` 子句的标准结果集，
也可以与你的基础表进行连接（join）。

节点以两个参数 `(Class, Id)` 传入（等价于内部的 `$ListBuild(Id, Class)` OID），
并以独立的 `Class` / `Id` 列返回。

| 函数 | 签名 | 列 |
|----------|-----------|---------|
| `Graph.SingleHop` | `(class, id, relation, inverse)` | `SourceClass, SourceId, Relation, TargetClass, TargetId` |
| `Graph.MultiHop` | `(class, id, relPath)` | 同样的 5 列（每条路径的最后一跳） |
| `Graph.BFS` | `(class, id, maxDepth)` | 同样的 5 列 |
| `Graph.ShortestPath` | `(startClass, startId, endClass, endId)` | `StepNo, Relation, Inverse, SourceClass, SourceId, TargetClass, TargetId` |

- `relation` 过滤：空 = 全部；逗号分隔 = 多个。
- `inverse`：`0` = 出边（节点为源），`1` = 入边（节点为目标）。
- `relPath`（MultiHop）：有序的 `"Relation:Inverse,Relation:Inverse,..."`，例如 `'Customer-SalesOrder:0'`。

```sql
-- 某客户的出边
SELECT * FROM Graph.SingleHop('Test.Customer', 8, '', 0);

-- 谁指向这张订单（入边）
SELECT * FROM Graph.SingleHop('Test.SalesOrder', 8, '', 1);

-- 将图查询结果连接回基础表
SELECT h.TargetId AS OrderId, so.TotalAmount
FROM Graph.SingleHop('Test.Customer', 8, 'Customer-SalesOrder', 0) h
JOIN Test.SalesOrder so ON so.ID = h.TargetId;

-- 多跳路径
SELECT * FROM Graph.MultiHop('Test.Customer', 8, 'Customer-SalesOrder:0');

-- 广度优先遍历，最多 2 跳
SELECT * FROM Graph.BFS('Test.Customer', 8, 2);

-- 两个节点之间的最短路径（每步一行）
SELECT * FROM Graph.ShortestPath('Test.Customer', 8, 'Test.SalesOrder', 8);
```

---

## 7. 从 REST（HTTP）查询

这些遍历还以**规范优先（spec-first）的 REST API**（`%REST`）形式暴露：

- `Graph.REST.spec` — OpenAPI 2.0 定义（契约）。
- `Graph.REST.impl` — 封装 `Graph.Tools` 的业务逻辑。
- `Graph.REST.disp` — 分发类，在规范编译时**自动生成**。
- Web 应用 `/api/graph` → `Graph.REST.disp`（命名空间 `NEHR`）。

所有端点均为 `POST`，接受并返回 JSON。节点表示为
`{ "class": ..., "id": ... }`（或 `{ "class": ..., "no": ... }`，通过
`<class>.GetOIDByNO` 按业务编号解析）。内部 OID 永远不会被暴露。

| 端点 | 请求体 | 结果 |
|----------|------|--------|
| `POST /api/graph/singlehop` | `{ node, relation?, inverse? }` | `{ edges:[{source,relation,target}], count }` |
| `POST /api/graph/multihop` | `{ node, relations:[{relation,inverse?}] }` | `{ endpoints:[…], count }` |
| `POST /api/graph/shortestpath` | `{ start, end }` | `{ found, length, path:[{step,relation,inverse,source,target}] }` |
| `POST /api/graph/bfs` | `{ node, maxDepth? }` | `{ maxDepth, edges:[…], count }` |
| `POST /api/graph/addedge` | `{ source, relation, target }` | `{ ok, source, relation, target }` |
| `POST /api/graph/removeedge` | `{ source, relation, target }` | `{ ok, source, relation, target }` |

- `relation`：空 = 全部；逗号分隔 = 多个。
- `inverse`：`0` = 出边（节点为源），`1` = 入边（节点为目标）。
- 缺失 / 无效的 `node` 返回 `400`，并带有 `{ "error": ... }`。
- `addedge` / `removeedge` 通过 `Graph.Store`（见 §1）**写入**底层边——它们为数据层图
  维护 `^GraphData.OUT` / `^GraphData.IN`。此处 `source` / `target` 是**通用节点键**
  `{ class, id }`（映射为 `$ListBuild(id, class)`）；**不**支持 `no` 业务编号解析。
  这两个端点仅用于数据层图——对象投影图的边由系统自动维护（见 §4）。

```bash
# 某客户的出边
curl -X POST http://<host>/api/graph/singlehop \
  -H 'Content-Type: application/json' \
  -d '{"node":{"class":"Test.Customer","id":"8"},"relation":"","inverse":0}'

# 谁指向这张订单（入边）
curl -X POST http://<host>/api/graph/singlehop \
  -H 'Content-Type: application/json' \
  -d '{"node":{"class":"Test.SalesOrder","id":"8"},"inverse":1}'

# 多跳路径
curl -X POST http://<host>/api/graph/multihop \
  -H 'Content-Type: application/json' \
  -d '{"node":{"class":"Test.Customer","id":"8"},"relations":[{"relation":"Customer-SalesOrder","inverse":0}]}'

# 广度优先遍历，最多 2 跳
curl -X POST http://<host>/api/graph/bfs \
  -H 'Content-Type: application/json' \
  -d '{"node":{"class":"Test.Customer","id":"8"},"maxDepth":2}'

# 最短路径
curl -X POST http://<host>/api/graph/shortestpath \
  -H 'Content-Type: application/json' \
  -d '{"start":{"class":"Test.Customer","id":"8"},"end":{"class":"Test.SalesOrder","id":"8"}}'

# 新增一条数据层边  KB-001 --MENTIONS--> FHIR
curl -X POST http://<host>/api/graph/addedge \
  -H 'Content-Type: application/json' \
  -d '{"source":{"class":"Knowledge","id":"KB-001"},"relation":"MENTIONS","target":{"class":"Entity","id":"FHIR"}}'

# 删除该边
curl -X POST http://<host>/api/graph/removeedge \
  -H 'Content-Type: application/json' \
  -d '{"source":{"class":"Knowledge","id":"KB-001"},"relation":"MENTIONS","target":{"class":"Entity","id":"FHIR"}}'
```

> 部署：编译 `Graph.REST.spec` 会生成 `Graph.REST.disp`；然后在命名空间 `NEHR`
> 中创建一个 Web 应用，将 `/api/graph` 映射到 `Graph.REST.disp`
> （例如通过 `%REST.API.CreateApplication("Graph.REST")` 或管理门户）。

---

## 8. 端到端示例

```objectscript
// --- 创建数据（边会自动维护）---
Set sup = ##class(Logistics.Business.Supplier).%New()
Set sup.Name = "ACME"
Do sup.%Save()

Set prod = ##class(Logistics.Business.Product).%New()
Set prod.SKU = "SKU-001"
Set prod.Supplier = sup          // -> 边  Supplier --supplies--> Product
Do prod.%Save()

// --- 查询：这个供应商供应哪些产品？---
Set supNode = $ListBuild(sup.%Id(), "Logistics.Business.Supplier")
Do ##class(Graph.Tools).SingleHop(supNode, "supplies", 0, .result)
Write result.%ToJSON()

// --- 查询：谁供应这个产品？（入边）---
Set prodNode = $ListBuild(prod.%Id(), "Logistics.Business.Product")
Do ##class(Graph.Tools).SingleHop(prodNode, "supplies", 1, .result)
Write result.%ToJSON()
```

---

## 9. 快速遍历 — 入边索引

`Graph.Tools` / `Graph.Object.Tools` 是查询引擎，借助入边索引 `^GraphData.IN`
对**反向与多跳**遍历进行加速。

```objectscript
Do ##class(Graph.Tools).SingleHop(node, "", 1, .result)        // 入边
Do ##class(Graph.Object.Tools).SingleHopWithNO(class, no, "", 1, .result)
```

### 为什么快
1. **入边索引（`^GraphData.IN`）。** 朴素的反向查询（`inverse=1`）必须**全表扫描**
   `^GraphData.OUT` 中的每条边才能找出谁指向某节点——O(E)。`Graph.Tools` 改为直接读取
   `^GraphData.IN(Target, Source, Relation)`，把一次反向跳降为 **O(入度)**。
2. **基于 `$Order` 的遍历 + 去对象化的中间态。** 正向跳用 `$Order` 遍历 `OUT`，反向跳用
   `$Order` 遍历 `IN`；中间前沿保持为裸 `$ListBuild` OID（不产生 `%DynamicArray` 开销），
   直到最终结果才物化。
3. **`ShortestPath` 采用双向 BFS。** 不是从单源扇出到深度 `d`，而是**从起点和终点同时**
   逐层扩展，在中间相遇即停——探索约 O(b^(d/2)) 个节点而非 O(b^d)。（最短路径不唯一，
   存在多条等长路径时具体返回的路径可能不同。）

### 性能

在一张 1,453 条边的图上的典型延迟（每个操作平均 500 次）：

| 操作 | 延迟 |
|-----------|--------:|
| 单跳正向 | 6.6 ms |
| 单跳反向 | 3.2 ms |
| 含反向步的 MultiHop | 3.2 ms |
| BFS 深度 3（无向） | 32.4 ms |
| ShortestPath（无向） | 11.9 ms |

代价模型：

- **反向跳是 O(入度)。** 它们直接读取 `^GraphData.IN(Target, Source, Relation)`，
  无需扫描 `^GraphData.OUT`，因此 `inverse = 1` 查询在大图上依然低廉。
- **BFS 与 `ShortestPath` 是无向的**——每访问一个节点都会同时扩展其反向边，因此高度
  依赖入边索引。
- **MultiHop** 在某一步使用 `Inverse = 1` 时获得加速；纯正向路径本身已通过 `$Order`
  遍历 `^GraphData.OUT` 而很快。

### 维护 `^GraphData.IN`
`^GraphData.IN` 会自动与 `^GraphData.OUT` 保持同步——每次写边都经由 `Graph.Store`，
它同时更新这两个全局变量：

- **对象投影图** — 在插入 / 更新 / 删除时维护（见 §4）；你无需调用任何东西。
- **数据层图** — `Graph.Store.AddEdge` / `RemoveEdge` 每次调用都会连同 `OUT` 一起
  更新 `IN`。

`Graph.Store` 还提供维护辅助方法：

```objectscript
Do ##class(Graph.Store).BuildIN()          // 从 OUT 重建 IN（幂等的全量重同步）
Do ##class(Graph.Store).Verify(.out, .in)  // 一致时 out=in 且 0 条镜像缺失
```

运行 `BuildIN()` 可从既有 `^GraphData.OUT` 数据填充 `^GraphData.IN`（例如首次启用时，
或任何怀疑漂移时）；该操作幂等。

---

## 10. 快速参考

- **启用（对象投影图）：** `Extends (%Persistent, Graph.Object.Base)` + 在引用属性上设置 `Direction` 和 `Relation`；或设类参数 `Auto = 1` 让持久化引用属性被自动纳入。
- **底层数据层图（无对象）：** 用 `##class(Graph.Store).AddEdge(src, rel, tgt)` / `RemoveEdge(...)` 直接写边（节点键 = `$ListBuild(id, type)`）；查询 API 相同。参见 `ProjectKB.KBGraph`。
- **反转一条边：** `Inverse = 1`，或使用 `Cardinality = one` / `parent` 的 `Relationship`。
- **维护：** 在对象层与 SQL 层的插入/更新/删除时自动进行；无需调用任何东西。
- **重建已有数据：** `%BuildIndices()`。
- **查询：** `Graph.Tools` → `SingleHop` / `MultiHop` / `ShortestPath` / `BFS`（适用于任何图数据，反向与多跳由入边索引 `^GraphData.IN` 加速为 O(入度)）。对于基于对象的数据，`Graph.Object.Tools` 额外提供 `*WithNO` 变体（按业务编号查询）。首次为既有数据回填索引：运行一次 `##class(Graph.Store).BuildIN()`。
- **从 SQL 查询：** `Graph.SQL` 表值函数 → `Graph.SingleHop` / `Graph.MultiHop` / `Graph.BFS` / `Graph.ShortestPath`（可用于 `FROM`、可连接、不依赖表）。
- **从 REST 查询：** 位于 `/api/graph` 的规范优先 `%REST` API（`Graph.REST.spec` + `Graph.REST.impl`）。查询 → `POST /singlehop` / `/multihop` / `/shortestpath` / `/bfs`；写数据层边 → `POST /addedge` / `/removeedge`。
- **存储：** `^GraphData.OUT`（正向边）、`^GraphData.IN`（入边索引）、`^GraphData.OWN`（所有权）、`^GraphData.Dic`（字典）。

