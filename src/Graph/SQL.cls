Include %occInclude

/// Opt-in SQL TVFs over Graph.Tools; original Graph SQL procedures are unchanged.
/// 中文：GraphEx SQL 表值函数，复用现有 SQL 行结构，不修改 Graph SQL。
/// 使用前先加载 Graph.Store、Graph.Tools、Graph.SQL，再编译 GraphEx 包。
/// SQL 名称为 Graph.SingleHop / MultiHop / BFS / BFSParallel / ShortestPath / BFSNodes，
/// 可放入 SELECT 的 FROM 子句并与业务表 JOIN；不是持久化物化视图。
/// pClass 是图中保存的 ObjectScript 类名，不一定等于 SQL 表名；pId 遵循字符串输入约定。
/// 内部节点键为 $ListBuild(pId,pClass)；数字型与字符串型二进制 ID 不可随意互换。
/// 示例中的患者 ID、关系名、业务表和主键仅为示意，必须替换为实际定义。
/// 需要边/关系时用 BFS；只需可达实体及最短跳数时优先用 BFSNodes。
/// SingleHop 在 Fetch 时流式读边；其余查询在 Execute 时完成遍历，再逐行返回内存结果。
/// 外层 WHERE/TOP 不会自动下推为遍历剪枝；没有 ORDER BY 时不保证 SQL 行顺序。
/// 不提供图快照隔离；一致性要求较高时请在图稳定期间查询。
/// BFSParallel/ShortestPath 读取 AcceptSuggestion 保存的 GraphEx 配置，原 Graph SQL 不受影响。
/// English: Load Graph.Store, Graph.Tools and Graph.SQL before compiling Graph.
/// Use GraphEx TVFs in FROM/JOIN; these are not persistent materialized views.
/// Class names identify stored graph nodes, not necessarily SQL tables. Preserve the string-ID contract.
/// Replace all illustrative IDs, relations, table names and primary keys with actual schema values.
/// Prefer BFSNodes for entity joins and depths; use edge queries when relationships are required.
/// Only SingleHop streams traversal. Other queries finish traversal before Fetch; no automatic predicate pushdown.
/// No snapshot or implicit SQL row order is guaranteed. Configured policies affect parallel BFS and shortest path.
/// SQL 示例 / Example:
///   SELECT NodeClass, NodeId, Depth FROM Graph.BFSNodes('EMR.Patient','123',3,2) ORDER BY Depth, NodeClass, NodeId
/// ObjectScript 参数化调用 / Parameterized call (check Prepare and execution errors):
///   Set stmt = ##class(%SQL.Statement).%New()
///   Set sc = stmt.%Prepare("SELECT NodeClass,NodeId,Depth FROM Graph.BFSNodes(?,?,?,?)")
///   If $SYSTEM.Status.IsError(sc) Do $SYSTEM.Status.DisplayError(sc)
///   If $SYSTEM.Status.IsOK(sc) {
///       Set rs = stmt.%Execute("EMR.Patient","123",3,2)
///       While rs.%Next() { Write rs.NodeClass," ",rs.NodeId," ",rs.Depth,! }
///       If rs.%SQLCODE<0 Write rs.%Message,!
///   }
Class Graph.SQL [ System = 3 ]
{

/// 中文：单跳邻接边；pClass/pId 为起点，pRelation 空=全部关系，也支持逗号分隔多关系。
/// pInverse：0 出边（默认），1 入边。返回 SourceClass/SourceId/Relation/TargetClass/TargetId。
/// 输出始终保留边在存储中的实际方向；查入边时起点出现在 Target 端。
/// 同一节点对的不同关系分别返回；Fetch 按需读取，不预先构造整批边结果。
/// English: One-hop edges, optionally filtered by comma-separated relations; empty means all.
/// pInverse=0 follows outgoing edges; 1 follows incoming edges. Rows retain stored source/target orientation.
/// Returns the five edge columns; different relations on the same pair are separate rows. Streaming Fetch.
/// SQL 示例 / Examples (all outgoing edges; selected incoming relations):
///   SELECT * FROM Graph.SingleHop('EMR.Patient','123','',0)
///   SELECT * FROM Graph.SingleHop('EMR.Drug','drug-id','prescribed,administered',1)
Query SingleHop(pClass As %String, pId As %String, pRelation As %String = "", pInverse As %Integer = 0, pLayers As %String = "") As %Query(ROWSPEC = "SourceClass:%String,SourceId:%String,Relation:%String,TargetClass:%String,TargetId:%String") [ SqlName = SingleHop, SqlProc ]
{
}

/// 中文：沿指定的有序关系路径遍历；pClass/pId 为起点，pRelPath 格式为 "关系:方向,关系:方向,..."。
/// 每步方向 0=出边、1=入边；例如先沿 prescribed 出边，再沿 interactsWith 出边。
/// 返回完成全部步骤后的末步边（五个边字段），不是完整路径列表，也不包含路径条数。
/// 每一步对节点去重；合法的重复关系和环路仍可跨步骤访问，因此可能与旧 Graph.MultiHop 不同。
/// English: Follow an ordered relation:direction path; each direction is 0 outgoing or 1 incoming.
/// Returns terminal-hop edges, not full paths or path multiplicities. Deduplication is per step.
/// Valid repeated/cyclic paths can differ from the original Graph.MultiHop behavior. Results are computed before Fetch.
/// SQL 示例 / Example:
///   SELECT * FROM Graph.MultiHop('EMR.Patient','123','prescribed:0,interactsWith:0')
Query MultiHop(pClass As %String, pId As %String, pRelPath As %String, pLayers As %String = "") As %Query(ROWSPEC = "SourceClass:%String,SourceId:%String,Relation:%String,TargetClass:%String,TargetId:%String") [ SqlName = MultiHop, SqlProc ]
{
}

/// 中文：从 pClass/pId 起点进行双向（忽略边方向的可达性）广度优先遍历。
/// pMaxDepth 为非负整数最大跳数；0 返回空边集。当前 SQL 接口没有关系或方向过滤参数。
/// 输出发现树的五列边记录，每个新节点一条边，不是所有可达边；边仍保留实际存储方向。
/// 在稳定图中，可达 N 个节点（含起点）时返回 N-1 条边；起点没有独立行，也没有 Depth 列。
/// English: Undirected BFS up to a nonnegative integer depth; depth 0 returns no edges.
/// Returns discovery-tree edges in stored orientation, not all reachable edges or standalone seed/depth rows.
/// For N reachable nodes including the seed, returns N-1 edges on a stable graph. No relation/direction arguments.
/// SQL 示例 / Example:
///   SELECT * FROM Graph.BFS('EMR.Patient','123',3)
/// 对应节点结果 / Equivalent reachability as nodes (direction=2):
///   SELECT * FROM Graph.BFSNodes('EMR.Patient','123',3,2)
Query BFS(pClass As %String, pId As %String, pMaxDepth As %Integer, pLayers As %String = "") As %Query(ROWSPEC = "SourceClass:%String,SourceId:%String,Relation:%String,TargetClass:%String,TargetId:%String") [ SqlName = BFS, SqlProc ]
{
}

/// 中文：双向并行 BFS，起点、深度及五列边输出与 BFS 相同；用于较大的遍历前沿。
/// pWorkers 为工作分片数；<=0 使用 Graph.Tools 默认值（当前为 8），示例显式使用 4。
/// 小前沿/浅层可能串行执行；并行不保证更快，发现树父节点和输出顺序可能不同。
/// 读取已接受的缓存、均衡、拆分和方向优化配置；方向优化是调度策略，不是出边/入边选择。
/// English: Parallel undirected BFS with the same edge schema and reachability/depth semantics as BFS.
/// pWorkers<=0 uses the current default of 8. Small frontiers/shallow traversals may run serially.
/// Discovery parents/order may differ. Uses accepted cache/balance/split/direction-optimization settings.
/// Direction optimization selects traversal strategy, not directed reachability. Parallelism is not always faster.
/// SQL 示例 / Example:
///   SELECT * FROM Graph.BFSParallel('EMR.Patient','123',3,4)
Query BFSParallel(pClass As %String, pId As %String, pMaxDepth As %Integer, pWorkers As %Integer = 0, pLayers As %String = "") As %Query(ROWSPEC = "SourceClass:%String,SourceId:%String,Relation:%String,TargetClass:%String,TargetId:%String") [ SqlName = BFSParallel, SqlProc ]
{
}

/// 中文：从 pStartClass/pStartId 到 pEndClass/pEndId 的双向无权最短路径（最少跳数）。
/// 输出 StepNo（从 1 开始）、Relation、Inverse、SourceClass/SourceId、TargetClass/TargetId。
/// Source/Target 是实际存储边方向；Inverse=1 表示本步沿 Target 到 Source 反向行走。
/// 按 ORDER BY StepNo 展示路径。无路径或起终点相同时均返回零行，不返回所有等长路径。
/// 读取已接受的度数感知配置；SQL 接口没有最大深度或关系过滤参数。
/// English: One minimum-hop undirected path, not a weighted path or all equal-length alternatives.
/// StepNo starts at 1; Inverse=1 traverses a stored edge from target to source. Order by StepNo for display.
/// No path and identical endpoints both return zero rows. Uses configured degree awareness; no depth/filter arguments.
/// SQL 示例 / Example:
///   SELECT * FROM Graph.ShortestPath('EMR.Patient','123','EMR.Drug','drug-id') ORDER BY StepNo
Query ShortestPath(pStartClass As %String, pStartId As %String, pEndClass As %String, pEndId As %String, pLayers As %String = "") As %Query(ROWSPEC = "StepNo:%Integer,Relation:%String,Inverse:%Integer,SourceClass:%String,SourceId:%String,TargetClass:%String,TargetId:%String") [ SqlName = ShortestPath, SqlProc ]
{
}

/// 中文：将已计算的边行数组封装到 SQL 游标句柄中，并初始化行位置和结果类型。
/// 入参：pRows 是边结果数组，pKind 标识行类型；qHandle 输出游标。
/// 示例：Do ..EdgeHandle(edges,.cursor,"edge")
///
/// English: Store a computed edge-row array in a SQL cursor handle with position and result-kind metadata.
/// Parameters: pRows contains edge rows, pKind labels the row type and qHandle receives the cursor.
/// Example: Do ..EdgeHandle(edges,.cursor,"edge")
ClassMethod EdgeHandle(pRows As %DynamicArray, Output qHandle As %Binary, pKind As %String = "edge") [ Private ]
{
    Set qHandle = {"kind":(pKind),"pos":0,"cnt":(pRows.%Size()),"rows":(pRows)}
}

/// 中文：从单跳查询游标读取下一条邻边；邻接扫描按需进行，不预先物化全部结果。
/// AtEnd=1 表示没有更多行；返回行保持图中边的存储方向。
/// 入参：qHandle 保存游标状态；Row 输出 SQL 列表行，AtEnd 输出是否结束。
/// 示例：Do ##class(Graph.SQL).SingleHopFetch(.cursor,.row,.atEnd)
///
/// English: Fetch the next one-hop edge on demand without materializing the complete adjacency result.
/// AtEnd=1 signals exhaustion; returned endpoints retain stored edge orientation.
/// Parameters: qHandle carries cursor state; Row receives a SQL row and AtEnd signals exhaustion.
/// Example: Do ##class(Graph.SQL).SingleHopFetch(.cursor,.row,.atEnd)
ClassMethod SingleHopFetch(ByRef qHandle As %Binary, ByRef Row As %List, ByRef AtEnd As %Integer) As %Status
{
    Set Row = "", AtEnd = 1
    Try {
        Set neighbor = qHandle.nbr, relation = qHandle.rel, relationIndex = qHandle.ri
        // 多层并集已在 Execute 中物化为边游标 | the multi-layer union is materialized as an edge cursor in Execute
        If qHandle.kind = "edge" Return ..HopFetch(.qHandle,.Row,.AtEnd)
        If '##class(Graph.Tools).SingleHopNext(qHandle.gref,qHandle.node,qHandle.rels,.neighbor,.relation,.relationIndex) Return $$$OK
        Set source = $Select(qHandle.inv:neighbor,1:qHandle.node), target = $Select(qHandle.inv:qHandle.node,1:neighbor)
        Set Row = $ListBuild($ListGet(source,2),$ListGet(source,1),relation,$ListGet(target,2),$ListGet(target,1))
        Set qHandle.nbr = neighbor, qHandle.rel = relation, qHandle.ri = relationIndex, AtEnd = 0
    } Catch exception { Return exception.AsStatus() }
    Return $$$OK
}

/// 中文：解析关系路径参数，调用 Graph.Tools.MultiHop 并把结果写入 SQL 游标。
/// 执行错误以 %Status 返回，并清空游标句柄。
/// 入参：qHandle 输出游标，pClass/pId 指定起点，pRelPath 是逗号分隔的关系:方向序列。
/// 示例：Set sc=##class(Graph.SQL).MultiHopExecute(.cursor,"EMR.Patient","123","takes:0,interactsWith:0")
///
/// English: Parse the relation-path argument, invoke Graph.Tools.MultiHop and populate the SQL cursor.
/// Returns execution errors as %Status and clears the cursor handle on failure.
/// Parameters: qHandle receives the cursor, pClass/pId identify the seed and pRelPath is a comma-separated relation:direction path.
/// Example: Set sc=##class(Graph.SQL).MultiHopExecute(.cursor,"EMR.Patient","123","takes:0,interactsWith:0")
ClassMethod MultiHopExecute(ByRef qHandle As %Binary, pClass As %String, pId As %String, pRelPath As %String, pLayers As %String = "") As %Status
{
    Set qHandle = ""
    Try {
        Set path = [], parts = $ListFromString(pRelPath,",")
        For index = 1:1:$ListLength(parts) {
            Set item = $List(parts,index)
            Continue:item=""
            Do path.%Push({"Relation":($Piece(item,":",1)),"Inverse":(+$Piece(item,":",2))})
        }
        $$$ThrowOnError(##class(Graph.Tools).MultiHop($ListBuild(pId,pClass),path,.rows,$Select(pLayers=$Char(0):"",1:pLayers)))
        Do ..EdgeHandle(rows,.qHandle)
    } Catch exception { Return exception.AsStatus() }
    Return $$$OK
}

/// 中文：执行 SQL BFS 表值函数，将发现树边结果存入游标供 Fetch 返回。
/// 入参：qHandle 输出游标，pClass/pId 指定起点，pMaxDepth 指定最大跳数。
/// 示例：Set sc=##class(Graph.SQL).BFSExecute(.cursor,"EMR.Patient","123",3)
///
/// English: Execute the SQL BFS table-valued function and store discovery-tree edges for subsequent Fetch calls.
/// Parameters: qHandle receives the cursor, pClass/pId identify the seed and pMaxDepth is the hop limit.
/// Example: Set sc=##class(Graph.SQL).BFSExecute(.cursor,"EMR.Patient","123",3)
ClassMethod BFSExecute(ByRef qHandle As %Binary, pClass As %String, pId As %String, pMaxDepth As %Integer, pLayers As %String = "") As %Status
{
    Set qHandle = ""
    Try {
        $$$ThrowOnError(##class(Graph.Tools).BFS($ListBuild(pId,pClass),pMaxDepth,.rows,$Select(pLayers=$Char(0):"",1:pLayers)))
        Do ..EdgeHandle(rows,.qHandle)
    } Catch exception { Return exception.AsStatus() }
    Return $$$OK
}

/// 中文：执行并行 BFS 表值函数；工作数及策略配置交由 Graph.Tools.BFSParallel 处理。
/// 将完整结果数组挂接到 SQL 游标，失败时返回错误状态。
/// 入参：qHandle 输出游标，pClass/pId 指定起点，pMaxDepth 为跳数上限，pWorkers 为工作数（0 使用默认值）。
/// 示例：Set sc=##class(Graph.SQL).BFSParallelExecute(.cursor,"EMR.Patient","123",3,4)
///
/// English: Execute the parallel BFS TVF, delegating worker and policy handling to Graph.Tools.BFSParallel.
/// Attach the computed result array to the SQL cursor or return the failure status.
/// Parameters: qHandle receives the cursor, pClass/pId identify the seed, pMaxDepth is the hop limit and pWorkers selects worker count (0 uses the default).
/// Example: Set sc=##class(Graph.SQL).BFSParallelExecute(.cursor,"EMR.Patient","123",3,4)
ClassMethod BFSParallelExecute(ByRef qHandle As %Binary, pClass As %String, pId As %String, pMaxDepth As %Integer, pWorkers As %Integer = 0, pLayers As %String = "") As %Status
{
    Set qHandle = ""
    Try {
        $$$ThrowOnError(##class(Graph.Tools).BFSParallel($ListBuild(pId,pClass),pMaxDepth,.rows,+pWorkers,"",.stats,0,"","","",$Select(pLayers=$Char(0):"",1:pLayers)))
        Do ..EdgeHandle(rows,.qHandle)
    } Catch exception { Return exception.AsStatus() }
    Return $$$OK
}

/// 中文：计算两节点间最短路径，并以按步序读取的游标结果供 SQL 查询使用。
/// 入参：qHandle 输出游标，pStartClass/pStartId 与 pEndClass/pEndId 分别指定路径端点。
/// 示例：Set sc=##class(Graph.SQL).ShortestPathExecute(.cursor,"EMR.Patient","123","EMR.Drug","D1")
///
/// English: Compute a shortest path and expose its ordered steps through the SQL query cursor.
/// Parameters: qHandle receives the cursor; pStartClass/pStartId and pEndClass/pEndId identify the endpoints.
/// Example: Set sc=##class(Graph.SQL).ShortestPathExecute(.cursor,"EMR.Patient","123","EMR.Drug","D1")
ClassMethod ShortestPathExecute(ByRef qHandle As %Binary, pStartClass As %String, pStartId As %String, pEndClass As %String, pEndId As %String, pLayers As %String = "") As %Status
{
    Set qHandle = ""
    Try {
        $$$ThrowOnError(##class(Graph.Tools).ShortestPath($ListBuild(pStartId,pStartClass),$ListBuild(pEndId,pEndClass),.rows,.stats,"",$Select(pLayers=$Char(0):"",1:pLayers)))
        Do ..EdgeHandle(rows,.qHandle,"step")
    } Catch exception { Return exception.AsStatus() }
    Return $$$OK
}

/// 中文：唯一可达节点及最短深度，包含起点（Depth=0）；不生成边 JSON 或持久化结果。
/// pClass/pId 为起点；pMaxDepth 为非负整数最大跳数，0 只产生起点（仍受返回类过滤）。
/// pDirection：0 出边（默认），1 入边，2 双向。pRelation：逗号分隔的遍历关系过滤。
/// pResultClass 仅过滤返回节点，不剪枝中间节点；空表示所有类。
/// 返回 NodeClass、NodeId、Depth（最短跳数），每个内部节点键一次；不提供父节点或关系信息。
/// 与 BFS 比较时需显式设 pDirection=2；默认出边遍历的范围可能不同。
/// 适合按类名及 ID 关联业务表；不需要对图结果再 DISTINCT，但业务表一对多 JOIN 仍可能重复。
/// 没有存储邻接的起点也会作为 Depth=0 节点返回，这不验证对应业务记录存在。
/// English: Unique reachable nodes and minimum depths, including the seed, without edge JSON.
/// pClass/pId identify the seed; pMaxDepth is a nonnegative integer. Depth 0 emits only the seed, subject to resultClass.
/// pDirection=0 outgoing (default), 1 incoming, 2 both; empty pRelation permits all relations.
/// Returns NodeClass/NodeId/Depth once per internal node key; no parent or relation columns.
/// Use direction=2 to match BFS reachability. Even an unstored seed is returned without checking business existence.
/// Result-class filtering is output-only; traversal may pass through other classes.
/// Execute completes BFS before Fetch; TOP/WHERE do not stop traversal early. No snapshot.
/// IDs retain the existing SQL string-input contract; numeric binary graph keys are not coerced.
/// SQL 示例 / Examples:
///   SELECT * FROM Graph.BFSNodes('EMR.Patient','123',3)
///   SELECT * FROM Graph.BFSNodes('EMR.Patient','123',3,2) ORDER BY Depth, NodeClass, NodeId
/// 指定遍历关系及输出类 / Restrict traversal relations and output class:
///   SELECT * FROM Graph.BFSNodes('EMR.Patient','123',2,0,'prescribed','EMR.Drug')
/// JOIN 示例，假设表 EMR.Drug 的主键为 ID / JOIN assuming EMR.Drug has primary key ID:
///   SELECT d.ID, n.Depth
///   FROM Graph.BFSNodes('EMR.Patient','123',3,2,'','EMR.Drug') n
///   JOIN EMR.Drug d ON n.NodeClass='EMR.Drug' AND n.NodeId=d.ID
///   ORDER BY n.Depth, d.ID
Query BFSNodes(pClass As %String, pId As %String, pMaxDepth As %Integer, pDirection As %Integer = 0, pRelation As %String = "", pResultClass As %String = "", pLayers As %String = "") As %Query(ROWSPEC = "NodeClass:%String,NodeId:%String,Depth:%Integer") [ SqlName = BFSNodes, SqlProc ]
{
}

/// 中文：执行 BFSNodes 并将节点深度映射保存在独立 NodeCursor 中，供 Fetch 流式输出。
/// 归一化 SQL 缺省参数；发生错误时清空游标。
/// 入参：qHandle 输出游标，pClass/pId 指定起点，pMaxDepth 限制深度，pDirection/pRelation 过滤遍历，pResultClass 过滤返回节点类。
/// 示例：Set sc=##class(Graph.SQL).BFSNodesExecute(.cursor,"EMR.Patient","123",3,2,"takes","EMR.Drug")
///
/// English: Execute BFSNodes and keep its node-depth map in an independent NodeCursor for streaming Fetch.
/// Normalize omitted SQL arguments and clear the cursor if execution fails.
/// Parameters: qHandle receives the cursor; pClass/pId identify the seed; pMaxDepth, pDirection and pRelation control traversal; pResultClass filters returned nodes.
/// Example: Set sc=##class(Graph.SQL).BFSNodesExecute(.cursor,"EMR.Patient","123",3,2,"takes","EMR.Drug")
ClassMethod BFSNodesExecute(ByRef qHandle As %Binary, pClass As %String, pId As %String, pMaxDepth As %Integer, pDirection As %Integer = 0, pRelation As %String = "", pResultClass As %String = "", pLayers As %String = "") As %Status
{
    Set qHandle = ""
    Try {
        If pDirection=$Char(0) Set pDirection = 0
        If pRelation=$Char(0) Set pRelation = ""
        If pResultClass=$Char(0) Set pResultClass = ""
        $$$ThrowOnError(##class(Graph.Tools).BFSNodes($ListBuild(pId,pClass),pMaxDepth,.nodes,pDirection,pRelation,$Select(pLayers=$Char(0):"",1:pLayers)))
        Set cursor = ##class(Graph.NodeCursor).%New()
        Merge cursor.Nodes = nodes
        Kill nodes
        Set cursor.Position = "", cursor.ResultClass = pResultClass, qHandle = cursor
    } Catch exception { Return exception.AsStatus() }
    Return $$$OK
}

/// 中文：从节点游标中顺序查找下一条满足结果类过滤的节点，并返回其最短深度。
/// 到达末尾后保持空行和 AtEnd=1；每个游标独立维护位置。
/// 入参：qHandle 是节点游标；Row 输出 NodeClass/NodeId/Depth，AtEnd 表示游标是否结束。
/// 示例：Do ##class(Graph.SQL).BFSNodesFetch(.cursor,.row,.atEnd)
///
/// English: Fetch the next node matching the result-class filter and return its minimum depth.
/// Exhausted cursors return an empty row with AtEnd=1; each cursor maintains independent state.
/// Parameters: qHandle is the node cursor; Row receives NodeClass/NodeId/Depth and AtEnd signals exhaustion.
/// Example: Do ##class(Graph.SQL).BFSNodesFetch(.cursor,.row,.atEnd)
ClassMethod BFSNodesFetch(ByRef qHandle As %Binary, ByRef Row As %List, ByRef AtEnd As %Integer) As %Status
{
    Set Row = "", AtEnd = 1
    Try {
        Set node = qHandle.Position
        For {
            Set node = $Order(qHandle.Nodes(node))
            If node="" Return $$$OK
            Set qHandle.Position = node
            Continue:(qHandle.ResultClass'="")&&($ListGet(node,2)'=qHandle.ResultClass)
            Set Row = $ListBuild($ListGet(node,2),$ListGet(node,1),qHandle.Nodes(node)), AtEnd = 0
            Return $$$OK
        }
    } Catch exception { Return exception.AsStatus() }
}

/// 中文：关闭 BFSNodes 游标并释放其内存节点映射；重复关闭安全。
/// 入参：qHandle 是待关闭的游标，关闭后置为空。
/// 示例：Do ##class(Graph.SQL).BFSNodesClose(.cursor)
///
/// English: Close a BFSNodes cursor and release its in-memory node map; repeated close calls are safe.
/// Parameter: qHandle is the cursor to close and is cleared afterward. Example: Do ##class(Graph.SQL).BFSNodesClose(.cursor)
ClassMethod BFSNodesClose(ByRef qHandle As %Binary) As %Status
{
    Set qHandle = ""
    Return $$$OK
}


/// 内部：把边结果（%DynamicArray of {OID,Relation,TargetOID}）直接挂到游标句柄，
/// Internal: attach the edge result (%DynamicArray of {OID,Relation,TargetOID}) directly to the cursor handle,
/// Fetch 时按位置惰性解码为结果行——不再拷贝进 ^||GraphSQL 全局（去掉第二层物化）。
/// decoding lazily by position on Fetch — no longer copied into the ^||GraphSQL global (removes the second materialization layer).
/// qHandle 是一个承载游标状态的 %DynamicObject：{kind, pos, cnt, rows}。
/// qHandle is a %DynamicObject carrying cursor state: {kind, pos, cnt, rows}.
ClassMethod initEdge(pResult As %DynamicArray, ByRef qHandle As %Binary) [ Internal, Private ]
{
    Set qHandle = {}
    Set qHandle.kind = "edge", qHandle.pos = 0, qHandle.cnt = pResult.%Size(), qHandle.rows = pResult
    Quit
}

/// 通用 Fetch：按 qHandle.pos 惰性解码一行；kind 决定行结构
/// Generic Fetch: lazily decode one row per qHandle.pos; kind determines the row structure
/// （edge=边 JSON 对象 5 列 / step=最短路径步 JSON 7 列）。SingleHop 走独立的流式 Fetch，不经此。
/// (edge = edge JSON object 5 columns / step = shortest-path step JSON 7 columns). SingleHop uses its own streaming Fetch and does not go through here.
ClassMethod HopFetch(ByRef qHandle As %Binary, ByRef Row As %List, ByRef AtEnd As %Integer) As %Status [ Internal, PlaceAfter = initEdge ]
{
    Set tSC = $$$OK
    Try 
    {
        Set tPos = qHandle.pos
        If tPos >= qHandle.cnt 
        {
            Set Row = "", AtEnd = 1
            Quit
        }
        If qHandle.kind = "step" 
        {
            Set tS = qHandle.rows.%Get(tPos), tSrc = tS.OID, tTgt = tS.TargetOID
            Set Row = $ListBuild(tPos + 1, tS.Relation, +tS.Inverse, $ListGet(tSrc, 2), $ListGet(tSrc, 1), $ListGet(tTgt, 2), $ListGet(tTgt, 1))
        }
        Else 
        {
            Set tE = qHandle.rows.%Get(tPos), tSrc = tE.OID, tTgt = tE.TargetOID
            Set Row = $ListBuild($ListGet(tSrc, 2), $ListGet(tSrc, 1), tE.Relation, $ListGet(tTgt, 2), $ListGet(tTgt, 1))
        }
        Set qHandle.pos = tPos + 1, AtEnd = 0
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 通用 Close：释放游标句柄（无临时全局可清理）
/// Generic Close: release the cursor handle (no temporary global to clean up)
ClassMethod HopClose(ByRef qHandle As %Binary) As %Status [ Internal, PlaceAfter = initEdge ]
{
    Set qHandle = ""
    Quit $$$OK
}

ClassMethod SingleHopExecute(ByRef qHandle As %Binary, pClass As %String, pId As %String, pRelation As %String = "", pInverse As %Integer = 0, pLayers As %String = "") As %Status
{
    Set tSC = $$$OK
    Try 
    {
        // +pInverse：把 SQL 缺省/NULL 传入的 $Char(0) 归一为 0（正向出边）
        // +pInverse: normalize the $Char(0) passed in by SQL default/NULL to 0 (forward out-edge)
        Set pInverse = +pInverse
        // 跨层并集需去重：视图内不止一个扫描单元时物化为边游标，单层仍流式 $Order
        // A cross-layer union needs dedup: materialize as an edge cursor when the view has several scan units, keep the streaming $Order for one layer
        If pLayers = $Char(0) Set pLayers = ""
        Set tUnits = ##class(Graph.Tools).units(pInverse, pInverse, pLayers, .tUnit)
        If tUnits '= 1
        {
            $$$ThrowOnError(##class(Graph.Tools).SingleHop($ListBuild(pId, pClass), pRelation, pInverse, .tRows, pLayers))
            Do ..EdgeHandle(tRows, .qHandle)
            Return $$$OK
        }
        // B：不做任何遍历/物化，仅在句柄上建立流式 $Order 游标，逐行 Fetch 时现取
        // B: no traversal/materialization at all; only set up a streaming $Order cursor on the handle, fetched on demand per row
        Set qHandle = {}
        Set qHandle.kind = "stream"
        Set qHandle.node = $ListBuild(pId, pClass)
        Set qHandle.gref = $List(tUnit(1), 2)
        Set qHandle.inv = pInverse
        Set qHandle.rels = ##class(Graph.Tools).relList(pRelation)
        Set qHandle.nbr = "", qHandle.rel = "", qHandle.ri = 0
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

ClassMethod SingleHopClose(ByRef qHandle As %Binary) As %Status
{
    Set tSC = $$$OK
    Try 
    {
        Set tSC = ..HopClose(.qHandle)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

ClassMethod MultiHopFetch(ByRef qHandle As %Binary, ByRef Row As %List, ByRef AtEnd As %Integer) As %Status
{
    Set tSC = $$$OK
    Try 
    {
        Set tSC = ..HopFetch(.qHandle, .Row, .AtEnd)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

ClassMethod MultiHopClose(ByRef qHandle As %Binary) As %Status
{
    Set tSC = $$$OK
    Try 
    {
        Set tSC = ..HopClose(.qHandle)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

ClassMethod BFSFetch(ByRef qHandle As %Binary, ByRef Row As %List, ByRef AtEnd As %Integer) As %Status
{
    Set tSC = $$$OK
    Try 
    {
        Set tSC = ..HopFetch(.qHandle, .Row, .AtEnd)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

ClassMethod BFSClose(ByRef qHandle As %Binary) As %Status
{
    Set tSC = $$$OK
    Try 
    {
        Set tSC = ..HopClose(.qHandle)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

ClassMethod BFSParallelFetch(ByRef qHandle As %Binary, ByRef Row As %List, ByRef AtEnd As %Integer) As %Status
{
    Set tSC = $$$OK
    Try 
    {
        Set tSC = ..HopFetch(.qHandle, .Row, .AtEnd)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

ClassMethod BFSParallelClose(ByRef qHandle As %Binary) As %Status
{
    Set tSC = $$$OK
    Try 
    {
        Set tSC = ..HopClose(.qHandle)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

ClassMethod ShortestPathFetch(ByRef qHandle As %Binary, ByRef Row As %List, ByRef AtEnd As %Integer) As %Status
{
    Set tSC = $$$OK
    Try 
    {
        Set tSC = ..HopFetch(.qHandle, .Row, .AtEnd)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

ClassMethod ShortestPathClose(ByRef qHandle As %Binary) As %Status
{
    Set tSC = $$$OK
    Try 
    {
        Set tSC = ..HopClose(.qHandle)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}
}
