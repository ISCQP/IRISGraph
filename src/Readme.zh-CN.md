# Graph 子系统 — 使用指南

一个构建在 InterSystems IRIS 之上的轻量级、**分层**属性图（property-graph）层。边存放在
`^GraphData` 全局变量中，由同一个引擎查询，并以三种方式暴露：ObjectScript（`Graph.Tools`：
单跳、多跳、最短路径、BFS）、SQL 表值函数（`Graph.SQL`）以及规范优先的 REST API（`Graph.REST`）。

**有两种方式向图中写入数据**，二者共用同一套全局变量、由**同一个**引擎查询：

- **底层数据层图**（基础） — 通过 `Graph.Store.AddEdge` / `RemoveEdge` **直接**向存储写入边。
  节点是**通用的节点键**，无需由任何类支撑（虚拟 / 合成节点类型），例如由 Knowledge / Entity
  节点构成的知识图谱（见 §1）。
- **对象投影图** — 任意持久化类继承 `Graph.Object.Base`，将选定的引用属性转化为**图的边**，
  这些边在每次插入 / 更新 / 删除时自动维护——**同时覆盖对象层和 SQL 层**（见 §2–§4）。

![Object to Graph](Object2Graph.png)

每条边都属于一个**层**——`Core`（只读）、行业**知识包**（如 `pgx`）和 `User`——读取时返回当前
视图内各层的并集（见 §5）。

**目录**

- [安装](#安装)
- [1. 概念 — 底层数据层图（基础）](#1-概念--底层数据层图基础)
- [2. 对象投影图](#2-对象投影图)
- [3. 边的方向规则](#3-边的方向规则)
- [4. 自动维护](#4-自动维护)
- [5. 分层（Layers）](#5-分层layers)
- [6. 使用 `Graph.Tools` 查询](#6-使用-graphtools-查询)
- [7. 从 SQL 查询](#7-从-sql-查询)
- [8. 从 REST（HTTP）查询](#8-从-resthttp查询)
- [9. 端到端示例](#9-端到端示例)
- [10. 分析、可视化与维护](#10-分析可视化与维护)
- [11. 限制](#11-限制)
- [12. 快速参考](#12-快速参考)

---

## 安装

1. 把 `Graph` 包的类导入到你的命名空间。核心是 `Graph.Store`、`Graph.Layer`、`Graph.Tools`、
   `Graph.SQL`、`Graph.Object.*` 和 `Graph.REST.*`；`Graph.Analysis` 和 `Graph.UI.*` 可选。
   演示类（`Graph.Demo.*`）运行时不需要。
   
   ```objectscript
   Do $SYSTEM.OBJ.LoadDir("/path/to/Graph", "ck", .err, 1)
   ```
   
2. 无需其他步骤。首次写入时会自动登记 `Core`（只读）和 `User`（可写）两个层，并为该命名空间打上
   分层标记。

3. 要使用 REST，编译 `Graph.REST.spec`（会生成 `Graph.REST.disp`），再创建一个 Web 应用，把
   `/api/graph` 分发到 `Graph.REST.disp`（见 §8）。

已经以旧的、无层布局（首个下标是节点）保存了边数据的命名空间，需要先执行一次
`##class(Graph.Layer).Migrate("User")` 原地转换。转换之前读写都会以 `LEGACY_GRAPH_LAYOUT`
失败。

---

## 1. 概念 — 底层数据层图（基础）

图的本质只是存放在Global变量中、**节点键之间**带类型的有向**边**。这一层完全不涉及对象——你可以
在没有任何 `%Persistent` 类的合成 / 虚拟节点之上构建一张完整的图。

### 节点键（Node key）
节点由一个**节点键**标识——**任意应用自定义标识**。常用约定是 `$ListBuild(id, type)`，
但键可以是任意值：

```objectscript
Set kb  = $ListBuild("KB-001", "Knowledge")
Set ent = $ListBuild("FHIR",   "Entity")
```

（§2 的对象投影图使用节点键的一种*特定*形式——OID `$ListBuild(Id, ClassName)`——但存储层本身对
每个键都一视同仁地按通用键处理。）

> **ID 的类型很重要。** `$ListBuild(10, cls)` 与 `$ListBuild("10", cls)` 是两个不同的键。
> 对象投影图始终存储字符串 ID，所以 SQL 里要写 `'10'`，ObjectScript 里写 `"10"`。直接写入的图
> 可以使用数字 ID；请使用与写入时相同的类型。

### 边（Edge）
两个节点之间有向且带类型的连接：

```
(源节点) --[Relation]--> (目标节点)
```

### 全局变量（Globals）
| 全局变量 | 结构 | 用途 |
|--------|-------|---------|
| `^GraphData.OUT` | `(Layer, Source, Target, Relation) = ""` | 边本身（正向）——用于**正向查询**。首个下标是**层**，其余为**节点键**。 |
| `^GraphData.IN` | `(Layer, Target, Source, Relation) = ""` | **入边索引**——每层内 `OUT` 的纯镜像，以目标为键；让**反向**查询降为 O(入度)。由 `Graph.Store` 自动维护，由 `Graph.Tools` 使用（见 §10）。 |
| `^GraphData.OWN` | `(Layer, Owner, Source, Relation, Target) = ""` | 持久化对象拥有的边（仅对象图），供函数索引做增删改维护。 |
| `^Graph.Layer` | `(Layer) = $lb(tier, rank, mode, enabled, desc)` | 层注册表（见 §5）。 |

你无需手工写入这些全局变量；`Graph.Store` 会自动为你维护。

### 直接写入边
当节点是合成 / 虚拟的，通过核心数据层写入器 `Graph.Store` 直接写边：

```objectscript
Do ##class(Graph.Store).AddEdge(kb, "MENTIONS", ent)             // 同时维护 OUT + IN，写入默认写入层
Do ##class(Graph.Store).AddEdge(kb, "MENTIONS", ent, 1, "pgx")   // 显式指定层
// ...稍后...
Do ##class(Graph.Store).RemoveEdge(kb, "MENTIONS", ent)          // 同时删除 OUT + IN
```

- `AddEdge(Source, Relation, Target[, pGenOut[, pLayer]])` 写正向边
  `^GraphData.OUT(Layer, Source, Target, Relation)` **并**写入边镜像
  `^GraphData.IN(Layer, Target, Source, Relation)`；`RemoveEdge` 两者一起删。
- 这类节点**没有** `^GraphData.OWN` 所有权记录、**也没有**函数索引——边由你自己增删（例如一个
  完整的 `Rebuild()` / `Clear()`）。
- 节点的描述 / 属性（`^GraphData.OUT` 存不了）请存在你自己的Global变量里，以节点键为键。
- 查询方式与任何图数据一致：`Graph.Tools` / `Graph.SQL` / REST 都只读 `^GraphData.OUT` /
  `^GraphData.IN`，与边由哪种方式写入无关。

---

## 2. 对象投影图

对象投影图从你的**持久化类**自动构建**同样**的边：把引用属性标记为图属性，边就会在每次插入 /
更新 / 删除时自动维护——无论使用对象操作还是SQL操作。

### 节点（OID）
在这里，启用图功能的类中每一条已保存的数据都是一个**节点**，由其 **OID** 标识——即 §1 中通用
节点键的特定形式：

```
NodeOID = $ListBuild(Id, ClassName)
```

例如 `$lb("2","Test.SalesOrder")`。

### 额外的Global变量
在 `^GraphData.OUT` / `^GraphData.IN`（见 §1）之上，对象投影图还使用两个**仅适用于对象图**的
Global变量：

| Global变量 | 结构 | 用途 |
|--------|-------|---------|
| `^GraphData.Dic` | `(SourceType, Relation, TargetType, Inverse) = PropName` | 图字典——在**编译时**构建。不分层。 |
| `^GraphData.OWN` | `(Layer, OwnerOID, SourceOID, Relation, TargetOID) = ""` | 记录每条边由哪个节点**拥有**——用于维护（快速删除/重建）。 |

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

编译时，一个功能索引投影（`Graph.Object.IndexProjection`）会自动注入用于维护边的函数索引。
**无需手工声明任何索引。**

### 图属性参数
定义于 `Graph.Object.PropertyParameters`：

| 参数 | 取值 | 含义 |
|-----------|--------|---------|
| `Direction` | `FROM` / `TO` | **将该属性标记为图属性**，并记录到字典中。属性**仅当设置了 `Direction`** 时才是图属性。 |
| `Relation` | 字符串 | 边的类型，例如 `"supplies"`、`"Customer-SalesOrder"`。默认取属性名。 |
| `Inverse` | `1` / `0` | 强制以反方向记录边（见 §3）。默认 `0`。 |
| `GraphUse` | `1` / `0` | 仅在 `Auto` 模式下生效：设为 `0` 可显式将某个本会被自动纳入的属性**排除**在图之外。 |

支持的属性类型（引用的目标类须为**非 `%Library.SerialObject`** 类型，即持久化引用；嵌入 / 序列化
对象不作为图属性）：

- **标量引用** — `Property X As SomeClass(Direction=...)`
- **关系（Relationship）** — `Relationship X As SomeClass(Direction=...) [ Cardinality = one/many, Inverse = ... ]`
- **集合（Collection）** — `Property X As list of SomeClass(Direction=...)` 或 `array of`

> 注意：父子关系（`Cardinality = parent`）目前因一个已知问题**暂不支持**。

### 类参数 `GRAPHLAYER`
`Parameter GRAPHLAYER = "";` 决定该类把边写入哪个层。为空表示默认写入层 `User`。它在运行时解析，
因此修改它**无需重新编译**模型类。写入只读、已停用或未登记的层会使保存失败。

### 自动模式（`Auto` 类参数）

在图类上设置类参数 `Auto = 1`，编译时投影会**自动**把符合条件的引用属性纳入图，无需在每个属性上
手写 `Direction`：

```objectscript
Class Logistics.Business.Product Extends (%Persistent, Graph.Object.Base)
{
Parameter Auto = 1;

Property Name As %String;                          // 字面量 → 忽略
Property HSCode As Logistics.Policy.HSCode;        // 持久化引用 → 自动纳入
Property Supplier As Logistics.Business.Supplier;  // 持久化引用 → 自动纳入
}
```

- 未定义 `Auto` 时**默认为 `0`**（关闭）。
- `Auto = 1` 时，投影会在**编译期把 `Direction = "TO"`、`Relation = <属性名>`、`Inverse = 0`
  显式注入**到符合条件的属性定义上（成为该类的单一事实来源）。自动纳入的判定规则：
  - **纳入**：目标为持久化类的标量引用 / 关系 / list / array 集合；
  - **排除**：字面量数据类型、`%SerialObject` 内嵌对象、一对多的"一"方（`Cardinality = one`/关系一侧）、父子关系的父方（`children`）。
- **不覆盖手工设置**：若属性已显式声明 `Direction`，或已手动设置 `Relation` / `Inverse`，这些值
  一律**保留**，`Auto` 只补齐缺失的参数。
- 设 `GraphUse = 0` 可把某个本会被自动纳入的属性**排除**在图之外。

---

## 3. 边的方向规则

存储的边通常**从当前对象指向被引用对象**：

```
(当前节点) --[Relation]--> (被引用节点)
```

当属性处于*多 / 子（many / child）*端点时，边会被**反向**（被引用节点 → 当前节点），即以下任一
情况：

- `Cardinality = one`
- `Cardinality = parent` *（目前暂不支持——见 §2）*
- `Inverse = 1`

这样可以保证边始终一致地从**"一（one）"**端指向**"多（many）"**端。示例：

| 声明 | 存储的边 |
|-------------|-------------|
| `Product.HSCode`（标量） | `Product --classified_as--> HSCode` |
| `Product.Supplier`（Cardinality one） | `Supplier --supplies--> Product` |
| `RouteSegment.PassesThrough`（list） | `RouteSegment --passes_through--> Location`（每个元素一条边） |
| `Impact.Cause`（Inverse 1） | `RiskEvent --causes--> Impact` |

边始终由**声明该属性的对象所拥有**，因此删除/更新该对象时会精确清理其自身的边。

---

## 4. 自动维护

一旦某个类启用了图功能，边会在**每一条**数据变更路径上被维护——你无需调用任何额外操作：

| 操作 | 对象层 | SQL 层 |
|-----------|--------------|-----------|
| 插入 | `obj.%Save()`（新建） | `INSERT INTO ...` |
| 更新 | `obj.%Save()`（已存在） | `UPDATE ...`（含多行） |
| 删除 | `%DeleteId()` / `%Delete()` | `DELETE FROM ...`（含多行） |

行为：
- **插入** — 读取当前属性值，为每个非空引用添加一条边（集合中每个元素一条）。
- **更新** — 先删除该行拥有的所有边（所有层），再根据当前值重建（外键变更时也安全；不会产生悬空边）。
- **删除** — 删除该行拥有的所有边（无需读取旧值）。
- **空引用** — 不产生边。

### 为已有数据重建边
如果你通过global导入更新了类数据，可以重建对应的图数据。

注入的索引支持 `BUILD INDEX`，因此你可以为数据已存在的类（重新）填充边：

```objectscript
Do ##class(%SYSTEM.OBJ).Compile("Logistics.Business.Product")   // 确保索引存在、字典已写入
Do ##class(Logistics.Business.Product).%BuildIndices()          // 重建所有索引，包括 GraphIndex*
```

`PurgeIndex`（在重建期间调用）会先清空该类现有的边，因此重建操作是幂等的。

---

## 5. 分层（Layers）

**层**用于分类管理你的图数据。例如在同一个数据库上，你有财务的图数据和电子病历的图数据，希望它们被分开管理，那么**层**会提供这种便利。

每条边只属于一个**层**——即 `OUT`、`IN`、`OWN` 的首个下标。层登记在 `^Graph.Layer`，由
`Graph.Layer` 管理。

| 层级（tier） | 典型层 | 默认模式 |
|------|---------------|--------------|
| `core` | `Core` | 只读 |
| `industry` | 行业知识包，如 `pgx` | 可写 |
| `user` | `User` | 可写 |
| `scenario` | 例如假设分析层 | 可写 |

### 读取视图
读取返回*视图*内各层的**并集**；同一条边出现在多层时只返回一次。默认视图是 `Core,User`，加上已
安装的知识包。可以这样覆盖：

```objectscript
Do ##class(Graph.Tools).SingleHop(node, "", 0, .r, "User")        // 单次调用（末尾 pLayers）
Do ##class(Graph.Layer).SetView("Core,pgx,User")                  // 进程级
Do ##class(Graph.Layer).SetDefaultView("Core,pgx,User")           // 系统默认
```

SQL 函数带末尾的 `layers` 参数（见 §7），REST 请求体带 `layers` 字段（见 §8）。

### 写入层
一次写入只进一个层。优先级：显式 `pLayer` > 类参数 `GRAPHLAYER` > `Graph.Layer.SetWriteLayer()`
> 默认写入层（`User`）。`Core` 拒绝写入，除非本进程调用了 `Graph.Layer.AllowWrite("Core")`。

### 管理层

```objectscript
Do ##class(Graph.Layer).InstallPack("pgx", "Pharmacogenomic knowledge", 50)  // 幂等；加入默认视图并排在 User 之前
Do ##class(Graph.Layer).Define("scenarioA", "scenario", 60, "rw", "What-if edges")
Do ##class(Graph.Layer).Enable("scenarioA", 0)      // 停用的层既不读也不写
Write ##class(Graph.Layer).List().%ToJSON()          // 按 rank 返回 name、tier、rank、mode、enabled、desc
Write ##class(Graph.Layer).Digest("pgx").%ToJSON()   // {"OUT":[条数,字节数],"IN":[..],"OWN":[..]}
Do ##class(Graph.Layer).Drop("scenarioA")            // 删除整层：OUT、IN 和 OWN
```

也可以用下标级全局映射把某一层映射到独立数据库，例如只读的 `Core` 库。

### 需要了解的行为
- 层与层之间不互相覆盖：读取就是简单并集。
- 如果你在使用旧版本的Graph, `Migrate("User")` 原地转换旧的无层命名空间并用摘要校验；失败时会还原原数据。
- 读取开销按"层 × 方向"各一个扫描单元计算；热点路径上请只保留需要的层。

---

## 6. 使用 `Graph.Tools` 查询

所有查询方法都返回一个 `%DynamicArray`，其中每个跳（hop）对象的结构为：

```json
{ "OID": "<sourceOID>", "Relation": "<rel>", "TargetOID": "<targetOID>" }
```

其中每个 OID 都是一个 `$ListBuild(Id, ClassName)` 值。每个方法都带可选的末尾参数 `pLayers`
（见 §5）。

| 方法 | 用途 |
|--------|---------|
| `SingleHop(node, relation, inverse, .result [, pLayers])` | 邻居；`relation` 为空 = 全部，逗号分隔 = 多个；`inverse = 1` = 入边 |
| `MultiHop(start, relList, .result [, pLayers])` | 沿有序关系路径前进；每步是 `{"Relation":..,"Inverse":0/1}` |
| `ShortestPath(start, end, .result, .stats [, degreeAware [, pLayers]])` | 无向双向 BFS |
| `BFS(start, maxDepth, .result [, pLayers])` | 无向广度优先遍历 |
| `BFSDirected(start, maxDepth, .result, direction, relation [, pLayers])` | 带方向（0 出、1 入、2 双向）和关系过滤的 BFS |
| `BFSNodes(start, maxDepth, .nodes, direction, relation [, pLayers])` | 可达节点及最小深度 |
| `BFSParallel(start, maxDepth, .result, workers, … [, pLayers])` | 面向超大图的多进程、按层同步的 BFS |

### 单跳（Single hop）
```objectscript
Set node = $ListBuild("1", "Logistics.Business.Supplier")

// 从 node 出发的出边（所有关系）
Do ##class(Graph.Tools).SingleHop(node, "", 0, .result)

// 仅指定关系（逗号分隔）
Do ##class(Graph.Tools).SingleHop(node, "supplies,supplier_in_country", 0, .result)

// 入边（谁指向 node）-> 设置 pInverse = 1
Do ##class(Graph.Tools).SingleHop(node, "", 1, .result)
```

### 多跳（有序关系路径）
```objectscript
Set risk = $ListBuild("10", "Logistics.Risk.RiskEvent")
Set rels = [
  {"Relation":"causes","Inverse":0},
  {"Relation":"impact_affects_shipment","Inverse":0}
]
Do ##class(Graph.Tools).MultiHop(risk, rels, .result)
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
`SingleHopWithNO`、`MultiHopWithNO`、`ShortestPathWithNO`、`BFSWithNO`、`BFSParallelWithNO`
（位于 `Graph.Object.Tools`，它是 `Graph.Tools` 的子类，专门处理基于对象的图数据）接受**类名 +
业务编号**，而不是 OID，同样带末尾的 `pLayers`。它们通过一个由你的类必须实现的类方法来解析节点：

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

## 7. 从 SQL 查询

同样的遍历以 `Graph.SQL` 中的**自定义 SQL 表值函数（table-valued functions）**形式暴露。它们
直接读取图Global变量——**并不依赖任何 SQL 表**——并返回可用于 `FROM` 子句的标准结果集，也可以与
你的基础表进行连接（join）。

节点以两个参数 `(Class, Id)` 传入（等价于内部的 `$ListBuild(Id, Class)` OID），并以独立的
`Class` / `Id` 列返回。

| 函数 | 签名 | 列 |
|----------|-----------|---------|
| `Graph.SingleHop` | `(class, id, relation, inverse[, layers])` | `SourceClass, SourceId, Relation, TargetClass, TargetId` |
| `Graph.MultiHop` | `(class, id, relPath[, layers])` | 同样的 5 列（每条路径的最后一跳） |
| `Graph.BFS` | `(class, id, maxDepth[, layers])` | 同样的 5 列 |
| `Graph.BFSParallel` | `(class, id, maxDepth[, workers[, layers]])` | 同样的 5 列 |
| `Graph.BFSNodes` | `(class, id, maxDepth[, direction[, relation[, resultClass[, layers]]]])` | `NodeClass, NodeId, Depth` |
| `Graph.ShortestPath` | `(startClass, startId, endClass, endId[, layers])` | `StepNo, Relation, Inverse, SourceClass, SourceId, TargetClass, TargetId` |

- `layers`（可选）：逗号分隔的层名；为空 = 当前视图。
- `relation` 过滤：空 = 全部；逗号分隔 = 多个。
- `inverse`：`0` = 出边（节点为源），`1` = 入边（节点为目标）。
- `relPath`（MultiHop）：有序的 `"Relation:Inverse,Relation:Inverse,..."`，例如
  `'causes:0,impact_affects_shipment:0'`。
- `direction`（BFSNodes）：`0` 出边（默认），`1` 入边，`2` 双向。要与 `BFS` 的可达范围一致请用
  `2`。`resultClass` 只过滤输出；遍历仍可经过其他类的节点。
- 边始终按**存储时的方向**返回。对于入边跳，你的起点在 Target 一侧，到达的节点在 `SourceId` 中。
- `class` 是图中保存的类名，不一定等于 SQL 表名。请同时用 `TargetClass` 和 `TargetId` 连接。
- 只有 `SingleHop` 是流式的。其余函数在返回第一行之前就已完成遍历，因此外层的 `WHERE` 或 `TOP`
  不会剪枝遍历。没有 `ORDER BY` 时不保证行顺序。不提供快照隔离。
- 不要给函数套 `TABLE(...)`；直接写在 `FROM` 里。
- 节点键的类型规则同样适用：对象图用 `'10'`，用数字 ID 写入的图用 `10`。

示例使用物流风险追踪演示（`Logistics.Risk.RiskEvent`，id 为 `10`）。

```sql
-- 1. 节点的出边；把结果连接回基础表
SELECT s.ID, s.Name
FROM Graph.SingleHop('Logistics.Risk.RiskEvent','10','affects_segment',0) h
JOIN Logistics_Route.RouteSegment s ON s.ID = h.TargetId;

-- 2. 谁指向某节点（入边）：产品 1 的供应商
SELECT su.Name
FROM Graph.SingleHop('Logistics.Business.Product','1','supplies',1) h
JOIN Logistics_Business.Supplier su ON su.ID = h.SourceId;      -- 到达的节点在 Source 一侧

-- 3. 终点为基础表的多跳路径：风险 -> 影响 -> 货运
SELECT sh.ID, sh.ShipmentNo
FROM Graph.MultiHop('Logistics.Risk.RiskEvent','10','causes:0,impact_affects_shipment:0') h
JOIN Logistics_Transport.Shipment sh ON sh.ID = h.TargetId;

-- 4. 反向多跳：途经某航段的在途货运
--    航段 <- 航路 <- 航次 <- 船 <- 集装箱 <- 货运
SELECT sh.ID, sh.ShipmentNo
FROM Graph.MultiHop('Logistics.Route.RouteSegment','1',
     'route_contains_segment:1,uses:1,assigned_to:1,loaded_on:1,contains:1') h
JOIN Logistics_Transport.Shipment sh ON sh.ID = h.SourceId;

-- 5. 广度优先遍历，按节点类聚合
SELECT TargetClass, COUNT(*) AS Edges
FROM Graph.BFS('Logistics.Risk.RiskEvent','10',2)
GROUP BY TargetClass ORDER BY Edges DESC;

-- 6. 可达实体及其深度，只保留一个类并连接回基础表
SELECT sh.ShipmentNo, n.Depth
FROM Graph.BFSNodes('Logistics.Risk.RiskEvent','10',4,0,'','Logistics.Transport.Shipment') n
JOIN Logistics_Transport.Shipment sh ON n.NodeId = sh.ID
ORDER BY n.Depth;

-- 7. 两个节点之间的最短路径（每步一行）
SELECT StepNo, Relation, Inverse, SourceClass, SourceId, TargetClass, TargetId
FROM Graph.ShortestPath('Logistics.Risk.RiskEvent','10','Logistics.Transport.Shipment','1')
ORDER BY StepNo;
-- 1 | causes                  | RiskEvent#10 -> Impact#10
-- 2 | impact_affects_shipment | Impact#10    -> Shipment#1
```

### 一条语句同时取基础表行及其图邻居

```sql
SELECT r.ID, r.Name, r.Type, r.Severity, r.Location->Name AS Loc,
       s.ID AS SegId, s.Name AS SegName
FROM Logistics_Risk.RiskEvent r
JOIN Graph.SingleHop('Logistics.Risk.RiskEvent',
                     CAST(r.ID AS VARCHAR(20)),      -- 图中的 id 是字符串
                     'affects_segment', 0) h ON 1=1
JOIN Logistics_Route.RouteSegment s ON s.ID = h.TargetId
WHERE r.ID = 10;
```

`r.ID` 是整数列，用作节点 id 之前必须先转成字符串。想保留没有邻居的行，把 `JOIN` 换成
`LEFT JOIN`。

### 按图的可达性过滤基础表（半连接）

```sql
SELECT p.ID, p.SKU
FROM Logistics_Business.Product p
WHERE p.ID IN (
  SELECT TargetId
  FROM Graph.SingleHop('Logistics.Business.Supplier','1','supplies',0)
);
```

### 在 SQL 中选择层

```sql
-- 只看 pgx 知识层
SELECT SourceId, Relation, TargetClass, TargetId
FROM Graph.SingleHop('Entity','Warfarin','',0,'pgx');

-- 跨层：知识节点（pgx 层）经桥接边连到业务表的行
SELECT d.ID, d.Name
FROM Graph.SingleHop('Entity','Warfarin','resolves_to',0,'Core,pgx,User') h
JOIN ClinicalResearch.Drug d
  ON h.TargetClass = 'ClinicalResearch.Drug' AND d.ID = h.TargetId;
```

同一次单跳如果限定为 `'User'`，则没有任何行，因为这些边在 `pgx` 层。

### 用数字 ID 直接写入的图：接触追踪

接触追踪演示直接写入人与人之间的接触边，使用数字 ID。每条边的第三层下标是接触时刻 `Ct`，通过
`Relation` 列返回。

```sql
-- 人员 1 的直接接触（图）；Relation 即接触时刻
SELECT Relation AS Ct, TargetId
FROM Graph.SingleHop('CTBench.Person', 1, '', 0)
ORDER BY 1;

-- 关系表里的同一批事实（边集完全一致）
SELECT PersonB, Ct, LocId, Tier
FROM EMR_Test.CTContact WHERE PersonA = 1 ORDER BY Ct;

-- 2 跳以内的人员，再连接回他们的在场记录
SELECT TOP 3 b.TargetId, p.LocId, p.TStart
FROM Graph.BFS('CTBench.Person', 1, 2) b
JOIN EMR_Test.CTPresence p ON p.PersonId = b.TargetId
WHERE b.TargetClass = 'CTBench.Person'
ORDER BY b.TargetId;
```

"沿时序递增的接触链，k 代以内能波及哪些人"是一个递归问题。纯 SQL 要对接触表做 k 次自连接，每跳
加 `Ct` 单调约束（以下是从人员 1 出发的 3 代）：

```sql
SELECT COUNT(DISTINCT P) FROM (
  SELECT c1.PersonB AS P FROM EMR_Test.CTContact c1
   WHERE c1.PersonA = 1 AND c1.Ct >= 0
  UNION
  SELECT c2.PersonB FROM EMR_Test.CTContact c1
   JOIN EMR_Test.CTContact c2 ON c2.PersonA = c1.PersonB AND c2.Ct >= c1.Ct
   WHERE c1.PersonA = 1 AND c1.Ct >= 0
  UNION
  SELECT c3.PersonB FROM EMR_Test.CTContact c1
   JOIN EMR_Test.CTContact c2 ON c2.PersonA = c1.PersonB AND c2.Ct >= c1.Ct
   JOIN EMR_Test.CTContact c3 ON c3.PersonA = c2.PersonB AND c3.Ct >= c2.Ct
   WHERE c1.PersonA = 1 AND c1.Ct >= 0
) d WHERE P <> 1;
```

直接用
`Graph.BFS` 不考虑时间，返回的是范围更大的、不满足时序的可达集合。

### 从 ObjectScript 参数化SQL调用

```objectscript
Set stmt = ##class(%SQL.Statement).%New()
Set sc = stmt.%Prepare("SELECT NodeClass, NodeId, Depth FROM Graph.BFSNodes(?,?,?,?)")
If $SYSTEM.Status.IsError(sc) { Do $SYSTEM.Status.DisplayError(sc) Quit }
Set rs = stmt.%Execute("Logistics.Risk.RiskEvent", "10", 3, 0)
While rs.%Next() { Write rs.NodeClass, " ", rs.NodeId, " ", rs.Depth, ! }
```

---

## 8. 从 REST（HTTP）查询

这些遍历还以**规范优先（spec-first）的 REST API**（`%REST`）形式暴露：

- `Graph.REST.spec` — OpenAPI 2.0 定义（契约）。
- `Graph.REST.impl` — 封装 `Graph.Tools` 的业务逻辑。
- `Graph.REST.disp` — 分发类，在规范编译时**自动生成**。
- Web 应用 `/api/graph` → `Graph.REST.disp`。

所有端点均为 `POST`，接受并返回 JSON。节点表示为 `{ "class": ..., "id": ... }`（或
`{ "class": ..., "no": ... }`，通过 `<class>.GetOIDByNO` 按业务编号解析）。内部 OID 永远不会被
暴露。

| 端点 | 请求体 | 结果 |
|----------|------|--------|
| `POST /api/graph/singlehop` | `{ node, relation?, inverse?, layers? }` | `{ edges:[{source,relation,target}], count }` |
| `POST /api/graph/multihop` | `{ node, relations:[{relation,inverse?}], layers? }` | `{ endpoints:[…], count }` |
| `POST /api/graph/shortestpath` | `{ start, end, layers? }` | `{ found, length, path:[{step,relation,inverse,source,target}] }` |
| `POST /api/graph/bfs` | `{ node, maxDepth?, layers? }` | `{ maxDepth, edges:[…], count }` |
| `POST /api/graph/addedge` | `{ source, relation, target, layer? }` | `{ ok, source, relation, target }` |
| `POST /api/graph/removeedge` | `{ source, relation, target, layer? }` | `{ ok, source, relation, target }` |

- `layers`（查询）：逗号分隔的层名；为空 = 当前视图。
- `layer`（`addedge` / `removeedge`）：写入的层；为空 = 默认写入层（`User`）。
- `relation`：空 = 全部；逗号分隔 = 多个。
- `inverse`：`0` = 出边（节点为源），`1` = 入边（节点为目标）。
- 缺失 / 无效的 `node` 返回 `400`，并带有 `{ "error": ... }`。
- `addedge` / `removeedge` 通过 `Graph.Store`（见 §1）**写入**底层边——它们为数据层图维护
  `^GraphData.OUT` / `^GraphData.IN`。此处 `source` / `target` 是**通用节点键** `{ class, id }`
  （映射为 `$ListBuild(id, class)`）；**不**支持 `no` 业务编号解析。这两个端点仅用于数据层图——
  对象投影图的边由系统自动维护（见 §4）。

```bash
# 某风险事件影响的航段
curl -X POST http://<host>/api/graph/singlehop \
  -H 'Content-Type: application/json' \
  -d '{"node":{"class":"Logistics.Risk.RiskEvent","id":"10"},"relation":"affects_segment","inverse":0}'

# 谁指向这个产品（入边）
curl -X POST http://<host>/api/graph/singlehop \
  -H 'Content-Type: application/json' \
  -d '{"node":{"class":"Logistics.Business.Product","id":"1"},"relation":"supplies","inverse":1}'

# 多跳路径：风险 -> 影响 -> 货运
curl -X POST http://<host>/api/graph/multihop \
  -H 'Content-Type: application/json' \
  -d '{"node":{"class":"Logistics.Risk.RiskEvent","id":"10"},"relations":[{"relation":"causes","inverse":0},{"relation":"impact_affects_shipment","inverse":0}]}'

# 广度优先遍历，最多 2 跳
curl -X POST http://<host>/api/graph/bfs \
  -H 'Content-Type: application/json' \
  -d '{"node":{"class":"Logistics.Risk.RiskEvent","id":"10"},"maxDepth":2}'

# 最短路径
curl -X POST http://<host>/api/graph/shortestpath \
  -H 'Content-Type: application/json' \
  -d '{"start":{"class":"Logistics.Risk.RiskEvent","id":"10"},"end":{"class":"Logistics.Transport.Shipment","id":"1"}}'

# 向 pgx 层新增一条数据层边  KB-001 --MENTIONS--> FHIR
curl -X POST http://<host>/api/graph/addedge \
  -H 'Content-Type: application/json' \
  -d '{"source":{"class":"Knowledge","id":"KB-001"},"relation":"MENTIONS","target":{"class":"Entity","id":"FHIR"},"layer":"pgx"}'

# 删除该边
curl -X POST http://<host>/api/graph/removeedge \
  -H 'Content-Type: application/json' \
  -d '{"source":{"class":"Knowledge","id":"KB-001"},"relation":"MENTIONS","target":{"class":"Entity","id":"FHIR"},"layer":"pgx"}'
```

> 部署：编译 `Graph.REST.spec` 会生成 `Graph.REST.disp`；然后在你的命名空间中创建一个 Web 应用，
> 将 `/api/graph` 映射到 `Graph.REST.disp`（例如通过 `%REST.API.CreateApplication("Graph.REST")`
> 或管理门户）。

---

## 9. 端到端示例

```objectscript
// --- 创建数据（边会自动维护，写入 User 层）---
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

同样的问题用 SQL 表达，并连接到业务表：

```sql
-- 供应商 1 的产品
SELECT p.ID, p.SKU, p.Name
FROM Graph.SingleHop('Logistics.Business.Supplier','1','supplies',0) h
JOIN Logistics_Business.Product p ON p.ID = h.TargetId;

-- 产品 1 的供应商
SELECT su.Name
FROM Graph.SingleHop('Logistics.Business.Product','1','supplies',1) h
JOIN Logistics_Business.Supplier su ON su.ID = h.SourceId;
```

---

## 10. 分析、可视化与维护

### `Graph.Analysis`
`Graph.Analysis.Analyze(.report [, minMB [, sampleSize [, maxNodes [, maxScans [, layers]]]]])`
先统计图Global变量的存储量，仅当超过阈值（默认 64 MB）时才对节点抽样，估计度数统计并给出遍历设置
建议。小图返回 `decision = small-graph`，且没有建议。`Analyze` 本身从不修改设置；接受建议需要
显式调用 `AcceptSuggestion(report, .applied)`。请在图稳定、`OUT` / `IN` 一致时运行。

### `Graph.UI.Network`
可复用的 vis-network 页面组件，用于 CSP 页面：

```objectscript
Do ##class(Graph.UI.Network).Head()                                   // 放在 <head> 内
Write "<style>", ##class(Graph.UI.Network).CSS(), "</style>"
Set opts = ""
Do ##class(Graph.UI.Network).Widget("net", graphJSON, .opts)          // 渲染到 <div id='net'>
```

`graphJSON` 的结构为 `{"nodes":[{id,label,group,title}],"edges":[{from,to,label}]}`。
`BuildFromGlobal(prefix, provider, layers)` 可以从图Global变量构造它。

### 校验与摘要

```objectscript
Set miss = ##class(Graph.Store).Verify(.out, .in)   // 镜像校验
Write ##class(Graph.Layer).Digest("User").%ToJSON()  // 批量变更或迁移前后各取一次来对比
```

---

## 11. 限制与注意

- 由于一个已知的问题，父子关系（`Cardinality = parent`）目前不做Graph投影，将在后续版本中进行修订。
- 数字 ID 与字符串 ID 是不同的键；同一张图内请统一使用一种类型。
- 除 `SingleHop` 外的 SQL 遍历会先完成遍历再返回行；外层 `WHERE` / `TOP` 不会剪枝遍历，没有
  `ORDER BY` 时不保证行顺序。
- 读取不提供快照隔离。
- 在扇出极高的节点上做按关系过滤的单跳，比不过滤的遍历慢。
- 层之间不互相覆盖：读取就是简单并集。

---

## 12. 快速参考

- **启用（对象投影图）：** `Extends (%Persistent, Graph.Object.Base)` + 在引用属性上设置 `Direction` 和 `Relation`；或设类参数 `Auto = 1` 让持久化引用属性被自动纳入。`Parameter GRAPHLAYER` 指定层。
- **底层数据层图（无对象）：** 用 `##class(Graph.Store).AddEdge(src, rel, tgt[, pGenOut[, pLayer]])` / `RemoveEdge(...)` 直接写边（节点键 = `$ListBuild(id, type)`）；查询 API 相同。
- **分层：** `Core`（只读）/ 行业知识包（如 `pgx`）/ `User`（默认写入层）。读取 = 视图内各层的并集（默认 `Core,User` + 已安装的知识包；可用末尾 `pLayers`、REST `layers` 或 `Graph.Layer.SetView` 覆盖）；写入只进一层（`pLayer` > `GRAPHLAYER` > `SetWriteLayer` > `User`）。用 `Graph.Layer.Define / InstallPack / Enable / Drop / List / Migrate / Digest` 管理。
- **反转一条边：** `Inverse = 1`，或使用 `Cardinality = one` / `parent` 的 `Relationship`。
- **维护：** 在对象层与 SQL 层的插入/更新/删除时自动进行；无需调用任何东西。
- **重建已有图数据：** `%BuildIndices()`。
- **查询：** `Graph.Tools` → `SingleHop` / `MultiHop` / `ShortestPath` / `BFS` / `BFSDirected` / `BFSNodes` / `BFSParallel`（适用于任何图数据，由入边索引 `^GraphData.IN` 加速）。对于基于对象的数据，`Graph.Object.Tools` 额外提供 `*WithNO` 变体（按业务编号查询）。索引漂移时可运行 `##class(Graph.Store).BuildIN()` 重建。
- **从 SQL 查询：** `Graph.SQL` 表值函数 → `Graph.SingleHop` / `Graph.MultiHop` / `Graph.BFS` / `Graph.BFSParallel` / `Graph.BFSNodes` / `Graph.ShortestPath`（可用于 `FROM`、可连接、不依赖表；对象图的 ID 是字符串）。
- **从 REST 查询：** 位于 `/api/graph` 的规范优先 `%REST` API（`Graph.REST.spec` + `Graph.REST.impl`）。查询 → `POST /singlehop` / `/multihop` / `/shortestpath` / `/bfs`；写数据层边 → `POST /addedge` / `/removeedge`。
- **存储：** `^GraphData.OUT(Layer, …)`（正向边）、`^GraphData.IN(Layer, …)`（入边索引）、`^GraphData.OWN(Layer, …)`（所有权）、`^GraphData.Dic`（字典，不分层）；层注册表在 `^Graph.Layer`。
