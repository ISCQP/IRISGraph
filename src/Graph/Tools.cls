/// Author: QP
/// Version: 4.0
/// Last Modified Date: 2026/10/19
Include %occInclude

/// 中文：图遍历核心工具类。遍历策略的命名空间级默认值持久化在全局 ^Graph.Settings("Traversal")，
/// 其值为 $ListBuild(pBalance, pSplitSize, pDegreeAware, pCacheLimit, pDirOpt)，出厂默认 $lb(0,0,0,4096,1)；
/// 由 Graph.Analysis 校验并写入，本类在省略对应入参时按位读取（显式入参始终优先）。各位置含义：
/// 1) pBalance（布尔 0/1，默认 0）：并行 top-down 的分块策略——1 按估算邻接权重做负载均衡分配，0 轮转分配；仅对排队执行的 top-down 前沿生效。
/// 2) pSplitSize（整数 >=0，默认 0）：高邻接度节点的范围分片大小，0 表示禁用分片；需多 worker 且 top-down 才启用。
/// 3) pDegreeAware（布尔 0/1，默认 0）：ShortestPath 的扩展侧选择——1 按前沿邻接权重估算选边，0 仅按前沿节点数选边。
/// 4) pCacheLimit（整数 >=-1，默认 4096）：并行 worker 本地 visited 缓存条数上限，-1 为无上限（需自行评估内存）。
/// 5) pDirOpt（布尔 0/1，默认 1）：BFSParallel 方向优化开关——大前沿时在 top-down 与 bottom-up(pull) 扫描间自动切换。
///
/// English: Core graph-traversal utility. Namespace-level defaults for traversal policy are persisted in the global ^Graph.Settings("Traversal"),
/// whose value is $ListBuild(pBalance, pSplitSize, pDegreeAware, pCacheLimit, pDirOpt) with factory default $lb(0,0,0,4096,1);
/// Graph.Analysis validates and writes it, and this class reads each position when the matching argument is omitted (explicit arguments always win). Positions:
/// 1) pBalance (boolean 0/1, default 0): parallel top-down chunking — 1 assigns by estimated adjacency weight (load balancing), 0 round-robin; applies only to a queued top-down frontier.
/// 2) pSplitSize (integer >=0, default 0): range-split size for high-degree nodes, 0 disables splitting; enabled only with multiple workers and top-down expansion.
/// 3) pDegreeAware (boolean 0/1, default 0): ShortestPath expansion-side choice — 1 selects by estimated frontier adjacency weight, 0 by frontier node count.
/// 4) pCacheLimit (integer >=-1, default 4096): per-worker local visited-cache entry cap, -1 means unbounded (assess memory yourself).
/// 5) pDirOpt (boolean 0/1, default 1): BFSParallel direction-optimization switch — on a large frontier, auto-switch between top-down and bottom-up (pull) scans.
Class Graph.Tools Extends %RegisteredObject
{

Parameter PARALLELTHRESHOLD = 64;

/// 中文：按节点和关系过滤条件，从指定邻接全局中枚举下一条匹配边。
/// 入参：pGref 是邻接全局引用，pNode 是当前节点，pRelList 是允许的关系列表；pNbr、pRel、pRi 通过引用保存迭代位置。
/// 返回 1 表示找到下一条边，0 表示邻接已耗尽。示例：Set found=##class(Graph.Tools).SingleHopNext(##class(Graph.Layer).Root("OUT","User"),node,relations,.neighbor,.relation,.relationIndex)
///
/// English: Return the next edge matching a node and optional relation list in the selected adjacency global.
/// pGref, pNode and pRelList select the scan; pNbr, pRel and pRi carry iteration state by reference. Returns 1 when found, otherwise 0.
/// Example: Set found=##class(Graph.Tools).SingleHopNext(##class(Graph.Layer).Root("OUT","User"),node,relations,.neighbor,.relation,.relationIndex)
ClassMethod SingleHopNext(pGref As %String, pNode, pRelList As %List, ByRef pNbr, ByRef pRel, ByRef pRi) As %Boolean [ Internal ]
{
    // 不过滤关系：先在当前邻居下推进关系，关系耗尽再推进邻居
    // No relation filter: advance relation under the current neighbor first, then advance the neighbor when relations are exhausted
    If pRelList = ""
    {
        For
        {
            If pNbr '= ""
            {
                // 同一邻居下取下一条关系（折叠多重边）
                // Next relation under the same neighbor (collapsing multi-edges)
                Set pRel = $Order(@pGref@(pNode, pNbr, pRel))
                If pRel '= "" Return 1
            }
            // 推进到下一个邻居，并重置关系游标
            // Advance to the next neighbor and reset the relation cursor
            Set pNbr = $Order(@pGref@(pNode, pNbr))
            If pNbr = "" Return 0
            Set pRel = ""
        }
    }
    // 按关系列表过滤：对每个邻居逐个 $Data 探测给定关系
    // Filter by relation list: probe each given relation per neighbor with $Data
    Set tLength = $ListLength(pRelList)
    For
    {
        If pNbr '= ""
        {
            // 续扫当前邻居剩余的关系下标
            // Continue scanning the remaining relation indexes of the current neighbor
            While pRi < tLength
            {
                Set pRi = pRi + 1, pRel = $List(pRelList, pRi)
                If $Data(@pGref@(pNode, pNbr, pRel)) Return 1
            }
        }
        // 推进到下一个邻居，关系下标归零
        // Advance to the next neighbor and reset the relation index
        Set pNbr = $Order(@pGref@(pNode, pNbr)), pRi = 0
        If pNbr = "" Return 0
    }
}

/// 中文：按节点和关系过滤条件枚举下一个不同邻居及其一条匹配关系。
/// 用于遍历邻居集合；若某邻居匹配多个关系，此方法只返回其中一个关系。
/// 入参：pGref 是邻接全局引用，pNode 是当前节点，pRelList 是关系列表；pNbr 是迭代位置，pRel 输出匹配关系。
/// 示例：Set found=##class(Graph.Tools).NeighborNext(##class(Graph.Layer).Root("OUT","User"),node,relations,.neighbor,.relation)
///
/// English: Find the next distinct neighbor and one matching relation in the selected adjacency global.
/// Multiple matching relations for one neighbor do not produce duplicate neighbor results.
/// Parameters: pGref selects the adjacency global, pNode is the source node, pRelList filters relations, and pNbr carries iteration state; pRel is output.
/// Example: Set found=##class(Graph.Tools).NeighborNext(##class(Graph.Layer).Root("OUT","User"),node,relations,.neighbor,.relation)
ClassMethod NeighborNext(pGref As %String, pNode, pRelList As %List, ByRef pNbr, Output pRel) As %Boolean [ Internal ]
{
    Set pRel = "", tLength = $ListLength(pRelList)
    For 
    {
        // 推进到下一个不同邻居
        // Advance to the next distinct neighbor
        Set pNbr = $Order(@pGref@(pNode, pNbr))
        If pNbr = "" Return 0
        If pRelList = "" 
        {
            // 不过滤：取该邻居的任一关系即算命中
            // No filter: any single relation of this neighbor counts as a hit
            Set pRel = $Order(@pGref@(pNode, pNbr, ""))
            If pRel '= "" Return 1
        } 
        Else 
        {
            // 过滤：命中关系列表中任一关系即返回该邻居
            // Filter: return this neighbor on the first relation in the list that matches
            For tIndex = 1:1:tLength 
            {
                Set pRel = $List(pRelList, tIndex)
                If $Data(@pGref@(pNode, pNbr, pRel)) Return 1
            }
        }
    }
}

/// 中文：构造一条边结果，并根据 pInverse 将端点排列为存储方向。
/// 返回包含 OID、Relation、TargetOID 的动态对象。
/// 入参：pNode 与 pNeighbor 是行走两端，pRelation 是关系名，pInverse=1 表示从邻居反向走到节点。
/// 示例：Set edge=##class(Graph.Tools).Edge(source,target,"related",0)
///
/// English: Build an edge result with endpoints arranged in stored direction according to pInverse.
/// Returns a dynamic object containing OID, Relation and TargetOID.
/// Parameters: pNode and pNeighbor are traversal endpoints, pRelation is the edge label, and pInverse marks reverse traversal.
/// Example: Set edge=##class(Graph.Tools).Edge(source,target,"related",0)
ClassMethod Edge(pNode, pNeighbor, pRelation As %String, pInverse As %Boolean) As %DynamicObject [ Internal ]
{
    // 反向：邻居是源、节点是目标（还原边的存储方向）
    // Reverse: the neighbor is the source and the node is the target (restore stored edge direction)
    If pInverse Return {"OID": (pNeighbor), "Relation": (pRelation), "TargetOID": (pNode)}
    // 正向：节点是源、邻居是目标
    // Forward: the node is the source and the neighbor is the target
    Return {"OID": (pNode), "Relation": (pRelation), "TargetOID": (pNeighbor)}
}

/// 中文：取得起点的一跳邻边，可按关系过滤，并可选择沿出边或入边查询。
/// pInverse=0 查询出边，pInverse=1 查询入边；返回边端点仍按图中的存储方向排列。
/// 入参：pNode 为起点，pRelation 为空表示所有关系或以逗号分隔的关系名，pInverse 选择方向；pResult 输出边数组。
/// 示例：Set sc=##class(Graph.Tools).SingleHop(patient,"prescribed",0,.edges)
///
/// English: Return one-hop edges from a node, optionally filtered by relation and adjacency direction.
/// pInverse=0 selects outgoing edges and 1 selects incoming edges; output endpoints retain stored orientation.
/// Parameters: pNode is the start node; empty pRelation selects all relations, otherwise it is a comma-separated filter; pInverse selects direction.
/// Example: Set sc=##class(Graph.Tools).SingleHop(patient,"prescribed",0,.edges)
ClassMethod SingleHop(pNode, pRelation As %String = "", pInverse As %Boolean = 0, Output pResult As %DynamicArray, pLayers As %String = "") As %Status
{
    Set pResult = [], tStatus = $$$OK
    Try
    {
        // 出边走 OUT，入边走 IN 索引；视图内每一层各扫一遍，结果取并集
        // Out-edges use OUT, in-edges use the IN index; scan every layer in the view and return the union
        Set tUnits = ..units(pInverse, pInverse, pLayers, .tUnit), tRelations = ..relList(pRelation)
        For tU = 1:1:tUnits
        {
            Set tRoot = $List(tUnit(tU), 2), tNeighbor = "", tRelation = "", tIndex = 0
            While ..SingleHopNext(tRoot, pNode, tRelations, .tNeighbor, .tRelation, .tIndex)
            {
                // 同一条边在多层出现时只产出一次
                // The same edge present in several layers is emitted once
                Continue:$Data(tSeen(tNeighbor, tRelation))
                Set tSeen(tNeighbor, tRelation) = ""
                // 按方向还原边的真实源/目标
                // Restore the true source/target of the edge by direction
                Set tSource = $Select(pInverse: tNeighbor, 1: pNode), tTarget = $Select(pInverse: pNode, 1: tNeighbor)
                Do pResult.%Push({"OID":(tSource),"Relation":(tRelation),"TargetOID":(tTarget)})
            }
        }
    }
    Catch tException
    {
        Set tStatus = tException.AsStatus(), pResult = []
    }
    Return tStatus
}

/// 中文：执行忽略边方向的广度优先遍历，返回发现树边。
/// 最大深度为跳数上限；该便捷接口遍历出边和入边，不返回单独的起点记录。
/// 入参：pStartNode 为节点键，pMaxDepth 为非负最大跳数；pResult 输出发现树边。
/// 示例：Set sc=##class(Graph.Tools).BFS(patient,3,.edges)
///
/// English: Run undirected breadth-first traversal and return discovery-tree edges.
/// The depth is a hop limit; this convenience method follows both outgoing and incoming edges.
/// Parameters: pStartNode is the node key and pMaxDepth is the nonnegative hop limit; pResult receives discovery-tree edges.
/// Example: Set sc=##class(Graph.Tools).BFS(patient,3,.edges)
ClassMethod BFS(pStartNode, pMaxDepth As %Integer, Output pResult As %DynamicArray, pLayers As %String = "") As %Status
{
    Return ..BFSDirected(pStartNode, pMaxDepth, .pResult, 2, "", pLayers)
}

/// 中文：执行带方向、关系过滤和深度限制的广度优先遍历。
/// pDirection=0 仅出边、1 仅入边、2 双向；结果包含发现树边。
/// 入参：pStartNode 为起点，pMaxDepth 为跳数上限，pDirection 选择方向，pRelation 为空或为逗号分隔关系过滤；pResult 输出边数组。
/// 示例：Set sc=##class(Graph.Tools).BFSDirected(patient,3,.edges,2,"takes,has_advice")
///
/// English: Run depth-limited breadth-first traversal with direction and relation filters.
/// pDirection selects outgoing (0), incoming (1) or both (2); results contain discovery-tree edges.
/// Parameters: pStartNode is the seed, pMaxDepth is the hop limit, pDirection selects edge direction, and pRelation filters labels.
/// Example: Set sc=##class(Graph.Tools).BFSDirected(patient,3,.edges,2,"takes,has_advice")
ClassMethod BFSDirected(pStartNode, pMaxDepth As %Integer, Output pResult As %DynamicArray, pDirection As %Integer = 0, pRelation As %String = "", pLayers As %String = "") As %Status
{
    Return ..Traverse(pStartNode, pMaxDepth, .pResult, .tNodes, pDirection, pRelation, 1, pLayers)
}

/// 中文：执行 BFS 并返回节点键到最短深度的数组，不构造边结果。
/// 方向和关系参数与 BFSDirected 相同；结果包含起点且其深度为 0。
/// 入参：pStartNode 为起点，pMaxDepth 为跳数上限，pDirection 与 pRelation 控制遍历；pNodes 输出节点键到深度的映射。
/// 示例：Set sc=##class(Graph.Tools).BFSNodes(patient,3,.nodes,2,"takes")
///
/// English: Run BFS and return a node-key-to-minimum-depth array without building edge results.
/// Direction and relation filters match BFSDirected; the start node is included at depth 0.
/// Parameters: pStartNode is the seed, pMaxDepth is the hop limit, pDirection and pRelation filter traversal, and pNodes receives node depths.
/// Example: Set sc=##class(Graph.Tools).BFSNodes(patient,3,.nodes,2,"takes")
ClassMethod BFSNodes(pStartNode, pMaxDepth As %Integer, ByRef pNodes, pDirection As %Integer = 0, pRelation As %String = "", pLayers As %String = "") As %Status
{
    Return ..Traverse(pStartNode, pMaxDepth, .tEdges, .pNodes, pDirection, pRelation, 0, pLayers)
}

/// 中文：BFS 的共享实现，验证参数并维护队列、已访问节点及可选发现边。
/// 入参：pStartNode 起跳节点
/// pMaxDepth 深度表示最大跳数
/// pDirection 方向 2 表示双向遍历
/// pRelation 定义搜索的关系
/// pResult/pNodes 接收结果
/// pEmitEdges 控制是否生成边数组。
/// 示例：Do ..Traverse(start,2,.edges,.nodes,2,"related",1)
///
/// English: Shared BFS implementation that validates options and maintains the queue and visited-depth map.
/// pEmitEdges controls edge materialization; direction 2 traverses both adjacency directions.
/// Parameters: pStartNode, pMaxDepth, pDirection and pRelation define the search; pResult/pNodes receive results and pEmitEdges controls edge output.
/// Example: Do ..Traverse(start,2,.edges,.nodes,2,"related",1)
ClassMethod Traverse(pStartNode, pMaxDepth As %Integer, Output pResult As %DynamicArray, ByRef pNodes, pDirection As %Integer, pRelation As %String, pEmitEdges As %Boolean, pLayers As %String = "") As %Status [ Internal ]
{
    Set pResult = [], tStatus = $$$OK
    Kill pNodes
    Try 
    {
        // 校验深度与方向参数（必须为合法非负整数 / 0-2）
        // Validate depth and direction arguments (must be valid nonnegative integers / 0-2)
        If (pMaxDepth < 0) || (pMaxDepth '= (pMaxDepth\1)) Throw ##class(%Exception.General).%New("INVALID_DEPTH")
        If (pDirection < 0) || (pDirection > 2) || (pDirection '= (pDirection\1)) Throw ##class(%Exception.General).%New("INVALID_DIRECTION")
        Set tRelations = ..relList(pRelation), 
        tRelationCount = $ListLength(tRelations)
        // 方向 0=仅出边、1=仅入边、2=双向（展开为扫描方向区间）
        // Direction 0=out only, 1=in only, 2=both (expanded into a scan-direction range)
        Set tFirstDirection = $Select(pDirection=1: 1, 1: 0), 
        tLastDirection = $Select(pDirection=0: 0, 1: 1)
        // 扫描单元 = (方向, 层)；多层取并集，已访问节点自然去重
        // Scan units = (direction, layer); layers are unioned and visited nodes dedupe naturally
        Set tUnits = ..units(tFirstDirection, tLastDirection, pLayers, .tUnit)
        // 初始化 FIFO 队列，起点深度为 0
        // Initialize the FIFO queue; the start node is at depth 0
        Set tHead = 1, tTail = 1, tQueue(1) = pStartNode, pNodes(pStartNode) = 0
        While tHead <= tTail 
        {
            // 出队当前节点及其深度
            // Dequeue the current node and its depth
            Set tNode = tQueue(tHead), tDepth = pNodes(tNode)
            Kill tQueue(tHead)
            Set tHead = tHead + 1
            // 已达最大深度的节点不再扩展
            // Nodes at the maximum depth are not expanded further
            Continue:tDepth>=pMaxDepth
            For tU = 1:1:tUnits 
            {
                Set tDirection = $List(tUnit(tU), 1), tRoot = $List(tUnit(tU), 2), tNeighbor = ""
                For 
                {
                    Set tNeighbor = $Order(@tRoot@(tNode, tNeighbor))
                    Quit:tNeighbor=""
                    // 已访问过的节点跳过（保留最短深度）
                    // Skip already-visited nodes (keep the minimum depth)
                    Continue:$Data(pNodes(tNeighbor))
                    If tRelations = "" 
                    {
                        // 不过滤：仅在需产边时取一条代表关系
                        // No filter: fetch one representative relation only when edges are needed
                        If pEmitEdges Set tRelation = $Order(@tRoot@(tNode, tNeighbor, ""))
                    } 
                    Else 
                    {
                        // 过滤：命中任一关系才算可达
                        // Filter: reachable only if any listed relation matches
                        Set tMatched = 0
                        For tRelationIndex = 1:1:tRelationCount 
                        {
                            Set tRelation = $List(tRelations, tRelationIndex)
                            If $Data(@tRoot@(tNode, tNeighbor, tRelation)) { Set tMatched = 1 Quit }
                        }
                        Continue:'tMatched
                    }
                    // 记录邻居深度，必要时产出发现树边
                    // Record the neighbor's depth and emit the discovery-tree edge if requested
                    Set pNodes(tNeighbor) = tDepth + 1
                    If pEmitEdges Do pResult.%Push(..Edge(tNode, tNeighbor, tRelation, tDirection))
                    // 未达深度上限则入队，供下一层扩展
                    // Enqueue for the next level if below the depth limit
                    If (tDepth + 1) < pMaxDepth Set tTail = tTail + 1, tQueue(tTail) = tNeighbor
                }
            }
        }
    } 
    Catch tException 
    {
        Set tStatus = tException.AsStatus(), pResult = []
        Kill pNodes
    }
    Return tStatus
}

/// 中文：按有序关系与方向序列执行多跳遍历，并返回最后一步的匹配边。
/// 每步对节点去重；路径描述为空或执行失败时返回错误状态并清空结果。
/// 入参：pStartNode 为起点；pRelList 是按顺序排列的动态数组，每项含 Relation 和 Inverse；pResult 输出末步边。
/// 示例：Set path=[{"Relation":"takes","Inverse":0},{"Relation":"interactsWith","Inverse":0}] Set sc=##class(Graph.Tools).MultiHop(patient,path,.edges)
///
/// English: Follow an ordered sequence of relation and direction steps, returning matching edges from the final step.
/// Nodes are deduplicated at each step; an empty path or failure returns an error status and clears results.
/// Parameters: pStartNode is the seed; pRelList is an ordered dynamic array of Relation/Inverse objects; pResult receives final-step edges.
/// Example: Set path=[{"Relation":"takes","Inverse":0},{"Relation":"interactsWith","Inverse":0}] Set sc=##class(Graph.Tools).MultiHop(patient,path,.edges)
ClassMethod MultiHop(pStartNode, pRelList As %DynamicArray, Output pResult As %DynamicArray, pLayers As %String = "") As %Status
{
    Set pResult = [], tStatus = $$$OK
    Try 
    {
        // 空路径视为错误
        // An empty path is treated as an error
        If pRelList.%Size() = 0 Throw ##class(%Exception.General).%New("EMPTY_RELATION_PATH")
        // 前沿初始化为起点
        // Initialize the frontier with the start node
        Set tFrontier(pStartNode) = ""
        // 逐步沿路径的每一跳推进前沿
        // Advance the frontier one hop at a time along the path
        For tDepth = 0:1:pRelList.%Size()-1 
        {
            // 本步的关系与方向（Inverse 决定走 OUT 还是 IN）
            // Relation and direction of this step (Inverse selects OUT or IN)
            Set tStep = pRelList.%Get(tDepth), tUnits = ..units(+tStep.Inverse, +tStep.Inverse, pLayers, .tUnit)
            Set tRelations = $ListBuild(tStep.Relation), tNode = ""
            Kill tNextFrontier
            For 
            {
                // 遍历当前前沿的每个节点
                // Iterate each node in the current frontier
                Set tNode = $Order(tFrontier(tNode))
                Quit:tNode=""
                Set tNeighbor = "", tRelation = "", tIndex = 0, tU = 1
                While ..UnitNext(.tUnit, tUnits, tNode, tRelations, .tU, .tNeighbor, .tRelation, .tIndex) 
                {
                    // 末跳：产出边；中间跳：去重累积下一层前沿
                    // Last hop: emit edges; intermediate hop: dedup into the next frontier
                    If tDepth = (pRelList.%Size()-1) 
                    {
                        If '$Data(tEmitted(tNode, tNeighbor, tRelation)) { Set tEmitted(tNode, tNeighbor, tRelation) = ""  Do pResult.%Push(..Edge(tNode, tNeighbor, tRelation, +tStep.Inverse)) }
                    } 
                    Else 
                    { 
                        Set tNextFrontier(tNeighbor) = "" 
                    }
                }
            }
            // 用下一层前沿替换当前前沿
            // Replace the current frontier with the next-level frontier
            Kill tFrontier
            Merge tFrontier = tNextFrontier
        }
    } 
    Catch tException 
    { 
        Set tStatus = tException.AsStatus(), pResult = [] 
    }
    Return tStatus
}

/// 中文：使用双向 BFS 查找两个节点之间的一条无权最少跳数路径。
/// pDegreeAware 可启用按邻接权重选择扩展侧；统计输出记录扫描工作量，空字符串使用配置默认值。
/// 路径按行走顺序输出，Inverse 表示行走方向是否与边的存储方向相反。
/// 入参：pStartNode/pEndNode 为端点，pDegreeAware 为度数感知开关；pResult 输出路径，pStats 输出扩展与扫描计数。
/// 示例：Set sc=##class(Graph.Tools).ShortestPath(patient,drug,.path,.stats,1)
///
/// English: Find one minimum-hop undirected path with bidirectional BFS.
/// pDegreeAware enables degree-weighted side selection; an empty value uses configured defaults.
/// Results are in walk order, and Inverse indicates traversal opposite to stored edge orientation.
/// Parameters: pStartNode/pEndNode are endpoints, pDegreeAware selects weighted side choice, and pResult/pStats receive the path and work counts.
/// Example: Set sc=##class(Graph.Tools).ShortestPath(patient,drug,.path,.stats,1)
ClassMethod ShortestPath(pStartNode, pEndNode, Output pResult As %DynamicArray, Output pStats As %DynamicObject, pDegreeAware As %Boolean = "", pLayers As %String = "") As %Status
{
    Set pResult = [], tStatus = $$$OK, pStats = {"expandedNodes":0,"scannedNeighbors":0,"relationReads":0}
    Set tExpandedNodes = 0, tScannedNeighbors = 0, tRelationReads = 0
    Try 
    {
        // 度数感知开关为空时读取 Graph.Settings 默认值
        // When the degree-aware switch is empty, read the default from Graph.Settings
        If pDegreeAware="" Set pDegreeAware = $ListGet($Get(^Graph.Settings("Traversal")),3,0)
        Throw:((pDegreeAware'=0) && (pDegreeAware'=1) ) ##class(%Exception.General).%New("INVALID_DEGREE_AWARE")
        Set tUnits = ..units(0, 1, pLayers, .tUnit)
        
        If pDegreeAware Set pStats.weightProbes = 0, pStats.weightNeighbors = 0
        // 常规情形：同一节点，或任一端点在图中无边 → 无路径
        // Trivial cases: same node, or either endpoint has no edges in the graph → no path
        Return:(pStartNode = pEndNode) tStatus
        Return:'..hasNode(.tUnit, tUnits, pStartNode) tStatus
        Return:'..hasNode(.tUnit, tUnits, pEndNode) tStatus

        // 双向 BFS：side 0 从起点、side 1 从终点，各自维护 visited/frontier（双槽轮换）
        // Bidirectional BFS: side 0 from start, side 1 from end, each with its own visited/frontier (double-buffered slots)
        Set tVisited(0,pStartNode) = 0, tVisited(1,pEndNode) = 0
        Set tFrontier(0,0,pStartNode) = "", tFrontier(1,0,pEndNode) = ""
        Set tSlot(0) = 0, tSlot(1) = 0, tCount(0) = 1, tCount(1) = 1, tMeeting = ""
        While (tCount(0)>0) && (tCount(1)>0) 
        {
            // 默认扩展较小的一侧（按节点数）
            // By default expand the smaller side (by node count)
            Set tSide = $Select(tCount(0)<=tCount(1):0,1:1)
            If pDegreeAware 
            {
                // 度数感知：按前沿邻接权重估算，改为扩展预期工作量更小的一侧
                // Degree-aware: estimate frontier adjacency weight and instead expand the side with less expected work
                For tCandidateSide = tSide,1-tSide 
                {
                    If '$Data(tFrontierWeight(tCandidateSide))
                    {
                        // 累加该侧前沿每个节点的有界邻接权重
                        // Sum the bounded adjacency weight of each node in this side's frontier
                        Set tFrontierWeight(tCandidateSide) = 0, tProbeNode = "", tProbes = 0
                        For 
                        {
                            Set tProbeNode = $Order(tFrontier(tCandidateSide,tSlot(tCandidateSide),tProbeNode))
                            Quit:tProbeNode=""
                            Set tFrontierWeight(tCandidateSide) = tFrontierWeight(tCandidateSide)+..NeighborWeight(tProbeNode, .tUnit, tUnits)
                            Set tProbes = tProbes+1
                        }
                        Set pStats.weightProbes = pStats.weightProbes+tProbes
                        Set pStats.weightNeighbors = pStats.weightNeighbors+tFrontierWeight(tCandidateSide)
                    }
                    Quit:(tCandidateSide=tSide)&&(tFrontierWeight(tSide)<=tCount(1-tSide))
                }
                If $Data(tFrontierWeight(0)) && $Data(tFrontierWeight(1)) 
                {
                    If tFrontierWeight(0)'=tFrontierWeight(1) Set tSide = $Select(tFrontierWeight(0)<tFrontierWeight(1):0,1:1)
                }
            }
            Set tOpposite = 1-tSide
            // 轮换到下一槽作为新前沿，清空待写入
            // Rotate to the next slot as the new frontier and clear it for writing
            Set tCurrentSlot = tSlot(tSide), tNextSlot = 1-tCurrentSlot, tNextCount = 0, tNode = ""
            Kill tFrontier(tSide,tNextSlot)
            For 
            {
                // 遍历本侧当前前沿的每个节点
                // Iterate each node in this side's current frontier
                Set tNode = $Order(tFrontier(tSide,tCurrentSlot,tNode))
                Quit:tNode=""
                Set tExpandedNodes = tExpandedNodes + 1
                // 无向：同时展开出边与入边
                // Undirected: expand both out-edges and in-edges
                For tU = 1:1:tUnits 
                {
                    Set tDirection = $List(tUnit(tU),1), tRoot = $List(tUnit(tU),2), tNeighbor = ""
                    For 
                    {
                        Set tNeighbor = $Order(@tRoot@(tNode,tNeighbor))
                        Quit:tNeighbor=""
                        Set tScannedNeighbors = tScannedNeighbors + 1
                        // 本侧已访问 → 跳过
                        // Already visited on this side → skip
                        Continue:$Data(tVisited(tSide,tNeighbor))
                        Set tRelation = $Order(@tRoot@(tNode,tNeighbor,""))
                        Set tRelationReads = tRelationReads + 1
                        Continue:tRelation=""
                        // 记录深度与父边（用于回溯构造路径）
                        // Record depth and parent edge (for backtracking the path)
                        Set tVisited(tSide,tNeighbor) = tVisited(tSide,tNode)+1
                        Set tParent(tSide,tNeighbor) = $ListBuild(tNode,tRelation,tDirection)
                        // 对侧已访问该节点 → 两侧相遇，结束搜索
                        // The opposite side has visited this node → the two sides meet; stop searching
                        If $Data(tVisited(tOpposite,tNeighbor)) { Set tMeeting = tNeighbor Quit }
                        Set tFrontier(tSide,tNextSlot,tNeighbor) = "", tNextCount = tNextCount+1
                    }
                    Quit:tMeeting'=""
                }
                Quit:tMeeting'=""
            }
            Quit:tMeeting'=""
            // 丢弃旧前沿槽，切换到新槽并更新计数
            // Discard the old frontier slot, switch to the new slot and update the count
            Kill tFrontier(tSide,tCurrentSlot)
            If pDegreeAware Kill tFrontierWeight(tSide)
            Set tSlot(tSide) = tNextSlot, tCount(tSide) = tNextCount
        }
        // 未相遇 → 两点不连通，返回空路径
        // No meeting → the two nodes are disconnected; return an empty path
        If tMeeting = "" 
        {
            Set pStats.expandedNodes = tExpandedNodes, pStats.scannedNeighbors = tScannedNeighbors, pStats.relationReads = tRelationReads
            Return tStatus
        }
        // 从相遇点沿 side 0 父链回溯到起点，逆序即起点→相遇段
        // From the meeting node, backtrack along side 0's parent chain to the start; reversed it is the start→meeting segment
        Set tNode = tMeeting, tLength = 0
        While $Data(tParent(0,tNode)) 
        {
            Set tRecord = tParent(0,tNode), tPrevious = $List(tRecord,1), tInverse = $List(tRecord,3)
            Set tEdge = ..Edge(tPrevious,tNode,$List(tRecord,2),tInverse), tEdge.Inverse = tInverse
            Set tLength = tLength+1, tSteps(tLength) = tEdge, tNode = tPrevious
        }
        For tIndex = tLength:-1:1 Do pResult.%Push(tSteps(tIndex))
        // 再沿 side 1 父链从相遇点走到终点（正序即相遇→终点段；方向需取反）
        // Then follow side 1's parent chain from the meeting node to the end (forward order is the meeting→end segment; direction is inverted)
        Set tNode = tMeeting
        While $Data(tParent(1,tNode)) 
        {
            Set tRecord = tParent(1,tNode), tPrevious = $List(tRecord,1), tInverse = $List(tRecord,3)
            Set tEdge = ..Edge(tPrevious,tNode,$List(tRecord,2),tInverse), tEdge.Inverse = 1-tInverse
            Do pResult.%Push(tEdge)
            Set tNode = tPrevious
        }
    } 
    Catch tException 
    { Set tStatus = tException.AsStatus(), pResult = [] }
    Set pStats.expandedNodes = tExpandedNodes, pStats.scannedNeighbors = tScannedNeighbors, pStats.relationReads = tRelationReads
    Return tStatus
}

/// 中文：执行并行无向 BFS，并可选择方向优化、任务均衡、邻接分片和缓存策略。
/// pWorkers<=0 使用默认工作数；空配置参数读取 Graph.Settings，显式参数优先。
/// 启用 pProfile 时返回逐层及任务计时；浅层或小前沿可能自动回退为串行处理。
/// 入参：pStartNode/pMaxDepth 定义搜索；
/// pWorkers、pDirOpt、pCacheLimit、pBalance、pSplitSize 控制调度；
/// pResult/pStats 接收边和剖析结果。
/// 示例：Set sc=##class(Graph.Tools).BFSParallel(patient,4,.edges,4,1,.stats,1,4096,1,512)
///
/// English: Run parallel undirected BFS with optional direction optimization, load balancing, range splitting and caching.
/// Nonpositive pWorkers uses the default; empty policy arguments read Graph.Settings and explicit values take precedence.
/// pProfile returns per-layer and task timings; shallow or small frontiers may fall back to serial execution.
/// Parameters: pStartNode/pMaxDepth define the search; worker and policy arguments tune scheduling; pResult/pStats receive edges and optional profiles.
/// Example: Set sc=##class(Graph.Tools).BFSParallel(patient,4,.edges,4,1,.stats,1,4096,1,512)
ClassMethod BFSParallel(pStartNode, pMaxDepth As %Integer, Output pResult As %DynamicArray, pWorkers As %Integer = 0, pDirOpt As %Integer = "", Output pStats As %DynamicObject, pProfile As %Boolean = 0, pCacheLimit As %Integer = "", pBalance As %Boolean = "", pSplitSize As %Integer = "", pLayers As %String = "") As %Status
{
    Set pResult = [], tStatus = $$$OK, tRun = "", tManager = ""
    Set pStats = ""
    If pProfile Set tStarted = $ZH, pStats = {"layers":[],"fallback":0,"complete":0,"cacheLimit":(pCacheLimit),"balance":(pBalance),"splitSize":(pSplitSize)}
    Try 
    {
        // 未显式传入的策略参数从 Graph.Settings 读取默认值（显式值优先）
        // Policy arguments not explicitly passed fall back to defaults in Graph.Settings (explicit values win)
        If (pDirOpt="")||(pCacheLimit="")||(pBalance="")||(pSplitSize="") 
        {
            Set tSettings = $Get(^Graph.Settings("Traversal"))
            If pDirOpt="" Set pDirOpt = $ListGet(tSettings,5,1)
            If pCacheLimit="" Set pCacheLimit = $ListGet(tSettings,4,4096)
            If pBalance="" Set pBalance = $ListGet(tSettings,1,0)
            If pSplitSize="" Set pSplitSize = $ListGet(tSettings,2,0)
        }
        If pProfile Set pStats.cacheLimit = pCacheLimit, pStats.balance = pBalance, pStats.splitSize = pSplitSize, pStats.dirOpt = pDirOpt
        // 校验深度/缓存/均衡/分片参数均为合法整数
        // Validate that depth/cache/balance/split arguments are all valid integers
        If (pMaxDepth < 0) || (pMaxDepth '= (pMaxDepth\1)) Throw ##class(%Exception.General).%New("INVALID_DEPTH")
        If (pCacheLimit < -1) || (pCacheLimit '= (pCacheLimit\1)) Throw ##class(%Exception.General).%New("INVALID_CACHE_LIMIT")
        If (pBalance'=0) && (pBalance'=1) Throw ##class(%Exception.General).%New("INVALID_BALANCE")
        If (pSplitSize<0) || (pSplitSize'=(pSplitSize\1)) Throw ##class(%Exception.General).%New("INVALID_SPLIT_SIZE")
        // 浅层（<=1）并行收益不足，直接回退为串行 BFS
        // Too shallow (<=1) to benefit from parallelism; fall back to serial BFS
        If pMaxDepth <= 1 
        {
            Set tStatus = ..BFS(pStartNode, pMaxDepth, .pResult, pLayers)
            If pProfile Set pStats.fallback = 1, pStats.totalMs = ($ZH-tStarted)*1000, pStats.cleanupMs = 0, pStats.complete = $$$ISOK(tStatus)
            Return tStatus
        }
        // 分配本次运行编号，初始化 visited 与第 0 层前沿（双槽轮换）
        // Allocate this run id; initialize visited and the level-0 frontier (double-buffered slots)
        Set tRun = $Increment(^IRIS.Temp.GraphExBFS)
        // 扫描单元随运行一同存储，worker 进程据此读取（进程私有视图不会被继承）
        // Scan units are stored with the run so worker processes can read them (a process-private view is not inherited)
        Set tUnits = ..units(0, 1, pLayers, .tUnit)
        Merge ^IRIS.Temp.GraphExBFS(tRun, "units") = tUnit
        Set ^IRIS.Temp.GraphExBFS(tRun, "units") = tUnits
        Set ^IRIS.Temp.GraphExBFS(tRun, "vis", pStartNode) = 1
        Set tSlot = 0, ^IRIS.Temp.GraphExBFS(tRun, "front", tSlot, pStartNode) = ""
        Set tCount = 1, tBuilt = 0, tTotal = 0
        // 逐层推进，直到达到深度或前沿为空
        // Advance level by level until the depth limit is reached or the frontier is empty
        For tDepth = 0:1:pMaxDepth-1 
        {
            If pProfile Set tLayerStarted = $ZH
            Set tMode = 0, tNextSlot = 1-tSlot
            // 方向优化：大前沿时评估是否切换为 bottom-up（pull）扫描
            // Direction optimization: on a large frontier, decide whether to switch to bottom-up (pull) scanning
            If pDirOpt && (tCount >= 1000) 
            {
                If 'tBuilt 
                {
                    // 首次构建全体节点集（正/反向并集），用于估算未访问规模
                    // Build the full node set once (union of forward/reverse) to estimate the unvisited scale
                    For tU = 1:1:tUnits 
                    {
                        Set tRoot = $List(tUnit(tU), 2), tNode = ""
                        For 
                        {
                            Set tNode = $Order(@tRoot@(tNode))
                            Quit:tNode=""
                            If '$Data(^IRIS.Temp.GraphExBFS(tRun, "all", tNode)) 
                            {
                                Set ^IRIS.Temp.GraphExBFS(tRun, "all", tNode) = "", tTotal = tTotal+1
                            }
                        }
                    }
                    Set tBuilt = 1
                }
                // 前沿占全体 >5% 时采用 bottom-up
                // Use bottom-up when the frontier exceeds 5% of all nodes
                Set tMode = tCount > (tTotal*0.05)
            }
            Set tWorkers = $Select(pWorkers>0: pWorkers\1, 1: 8)
            Set:tWorkers<1 tWorkers = 1
            // 分片仅在 top-down、多 worker、且配置了 splitSize 时启用（把高度节点拆成有界范围）
            // Range splitting is enabled only in top-down mode with multiple workers and a configured splitSize (splits high-degree nodes into bounded ranges)
            Set tSplitEnabled = (pSplitSize>0) && 'tMode && (tWorkers>1)
            If 'tMode && 'tSplitEnabled && (tWorkers>tCount) Set tWorkers = tCount
            // 小前沿或单 worker 时走内联（串行）路径，避免调度开销
            // Small frontier or single worker takes the inline (serial) path to avoid scheduling overhead
            Set tInline = ('tMode && (tCount < ..#PARALLELTHRESHOLD)) || (tWorkers=1)
            If tInline && 'tSplitEnabled Set tWorkers = 1
            // 清理本层临时结构：下一槽前沿、chunk、res、range
            // Clear this level's temp structures: next-slot frontier, chunk, res, range
            Kill ^IRIS.Temp.GraphExBFS(tRun, "front", tNextSlot), ^IRIS.Temp.GraphExBFS(tRun, "chunk"), ^IRIS.Temp.GraphExBFS(tRun, "res"), ^IRIS.Temp.GraphExBFS(tRun,"range")
            If pProfile Kill ^IRIS.Temp.GraphExBFS(tRun, "task")
            Kill tSizes, tLoads
            Set tBalanced = pBalance && 'tMode && 'tInline
            Set tPruneCandidates = tMode && (tDepth < (pMaxDepth-1))
            // bottom-up 扫全体未访问集；top-down 扫当前前沿
            // bottom-up scans the unvisited node set; top-down scans the current frontier
            Set tSource = $Select(tMode: $Name(^IRIS.Temp.GraphExBFS(tRun, "all")), 1: $Name(^IRIS.Temp.GraphExBFS(tRun, "front", tSlot)))
            Set tNode = "", tIndex = 0, tWorkIndex = 0, tSplitNodes = 0, tRangeTasks = 0
            If pProfile Set tScannedCandidates = 0
            // 遍历候选节点，按轮转/均衡/分片策略分配到各 worker chunk
            // Iterate candidate nodes and assign them to worker chunks by round-robin/balanced/split policy
            For 
            {
                Set tNode = $Order(@tSource@(tNode))
                Quit:tNode=""
                If pProfile Set tScannedCandidates = tScannedCandidates+1
                // bottom-up 下跳过已访问节点（可选剪枝以加速后续层）
                // In bottom-up, skip already-visited nodes (optionally prune to speed up later levels)
                If tMode && $Data(^IRIS.Temp.GraphExBFS(tRun, "vis", tNode)) 
                {
                    If tPruneCandidates Kill @tSource@(tNode)
                    Continue
                }
                Set tIndex = tIndex+1
                If tSplitEnabled 
                {
                    // 高度节点拆分成多个范围任务；成功拆分则本节点不再单独入队
                    // Split a high-degree node into multiple range tasks; if split, this node is not enqueued whole
                    Set tRanges = ..SplitNode(tRun,tNode,pSplitSize,tWorkers,.tSizes,.tLoads,.tWorkIndex,tBalanced,.tUnsplitWeight)
                    If tRanges {
                        Set tSplitNodes = tSplitNodes+1, tRangeTasks = tRangeTasks+tRanges
                        Continue
                    }
                }
                // 未拆分节点：默认轮转分配；启用均衡时选当前负载最小的 chunk
                // Unsplit node: round-robin by default; when balancing, pick the least-loaded chunk
                Set tChunk = tWorkIndex#tWorkers, tWorkIndex = tWorkIndex+1
                If tBalanced 
                {
                    If tSplitEnabled { Set tWeight = tUnsplitWeight }
                    Else { Set tWeight = ..NeighborWeight(tNode, .tUnit, tUnits) }
                    Set tChunk = 0
                    For tCandidate = 1:1:tWorkers-1 
                    {
                        If $Get(tLoads(tCandidate))<$Get(tLoads(tChunk)) Set tChunk = tCandidate
                    }
                    Set tLoads(tChunk) = $Get(tLoads(tChunk))+tWeight
                }
                Set ^IRIS.Temp.GraphExBFS(tRun, "chunk", tChunk, $Increment(tSizes(tChunk))) = tNode
            }
            // 有拆分任务则必并行；bottom-up 候选过少则回退内联
            // Any split tasks force parallel; too few bottom-up candidates fall back to inline
            If tSplitNodes Set tInline = 0
            If tMode && (tIndex < ..#PARALLELTHRESHOLD) Set tInline = 1
            If pProfile 
            {
                Set tExecutionStarted = $ZH
                Set tLayer = {"depth":(tDepth),"bottomUp":(tMode),"inline":(tInline),"balanced":(tBalanced),"workers":(tWorkers),"frontierNodes":(tCount),"candidateNodes":(tIndex),"prepareMs":((tExecutionStarted-tLayerStarted)*1000),"executeMs":0,"collectMs":0,"initializeMs":0,"queueMs":0,"syncMs":0,"tasks":[],"edges":0}
                Set tLayer.scannedCandidates = tScannedCandidates, tLayer.stagedBatches = 0
                Set tLayer.splitNodes = tSplitNodes, tLayer.rangeTasks = tRangeTasks, tLayer.workItems = tWorkIndex
            }
            If tIndex = 0 
            {
                If pProfile Do pStats.layers.%Push(tLayer)
                Quit
            }
            Set tBuildFrontier = tDepth < (pMaxDepth-1)
            If tInline 
            {
                // 内联执行：当前进程逐 chunk 调用 worker，直接写 pResult
                // Inline execution: the current process runs each chunk's worker and writes pResult directly
                Set tCount = 0, tCacheEntries = 0
                For tChunk = 0:1:tWorkers-1 
                {
                    Continue:'$Data(tSizes(tChunk))
                    Set tStatus = ..BFSWorker(tRun, tChunk, tSlot, tMode, tBuildFrontier, 1, pResult, .tDiscovered, pCacheLimit, .tChunkCacheEntries)
                    Quit:$$$ISERR(tStatus)
                    Set tCount = tCount+tDiscovered, tCacheEntries = tCacheEntries+tChunkCacheEntries
                }
            } 
            Else 
            {
                // 并行执行：首次初始化 WorkMgr，把各 chunk 排入队列后 Sync 等待
                // Parallel execution: initialize WorkMgr once, queue each chunk and then Sync to wait
                If pProfile Set tInitializeStarted = $ZH
                If '$IsObject(tManager) 
                {
                    Set tManager = $SYSTEM.WorkMgr.Initialize("", .tStatus)
                    $$$ThrowOnError(tStatus)
                }
                If pProfile Set tQueueStarted = $ZH, tLayer.initializeMs = (tQueueStarted-tInitializeStarted)*1000
                For tChunk = 0:1:tWorkers-1 
                {
                    Continue:'$Data(tSizes(tChunk))
                    If pProfile 
                    {
                        Set tStatus = tManager.Queue("##class(Graph.Tools).BFSProfileWorker", tRun, tChunk, tSlot, tMode, tBuildFrontier, $ZH, pCacheLimit)
                    } 
                    Else 
                    {
                        Set tStatus = tManager.Queue("##class(Graph.Tools).BFSWorker", tRun, tChunk, tSlot, tMode, tBuildFrontier, 0, "", "", pCacheLimit)
                    }
                    Quit:$$$ISERR(tStatus)
                }
                If pProfile Set tSyncStarted = $ZH, tLayer.queueMs = (tSyncStarted-tQueueStarted)*1000
                Set tSyncStatus = tManager.Sync()
                If pProfile Set tLayer.syncMs = ($ZH-tSyncStarted)*1000
                If $$$ISOK(tStatus) Set tStatus = tSyncStatus
            }
            $$$ThrowOnError(tStatus)
            If pProfile Set tCollectStarted = $ZH, tLayer.executeMs = (tCollectStarted-tExecutionStarted)*1000
            // 并行模式下，worker 把边暂存在临时区，此处统一收集到 pResult
            // In parallel mode workers stage edges in temp storage; collect them into pResult here
            If 'tInline Do ..CollectResults(tRun,pResult,.tCount)
            If pProfile 
            {
                Set tLayer.collectMs = ($ZH-tCollectStarted)*1000, tLayer.edges = tCount
                Set tLayer.cacheEntries = $Select(tInline:tCacheEntries,1:0)
                Set tChunk = ""
                For 
                {
                    Set tChunk = $Order(^IRIS.Temp.GraphExBFS(tRun,"task",tChunk),1,tTask)
                    Quit:tChunk=""
                    Do tLayer.tasks.%Push({"chunk":(tChunk),"processId":($List(tTask,1)),"startDelayMs":($List(tTask,2)),"runMs":($List(tTask,3)),"edges":($List(tTask,4)),"complete":($List(tTask,5)),"cacheEntries":($List(tTask,6)),"estimatedNeighbors":($Get(tLoads(tChunk),0)),"stagedBatches":($List(tTask,7))})
                    Set tLayer.cacheEntries = tLayer.cacheEntries+$List(tTask,6)
                    Set tLayer.stagedBatches = tLayer.stagedBatches+$List(tTask,7)
                }
                Do pStats.layers.%Push(tLayer)
            }
            Set tSlot = tNextSlot
            Quit:tCount=0
        }
    } 
    Catch tException 
    { Set tStatus = tException.AsStatus() }
    // 收尾：释放 WorkMgr、清除本次运行的全部临时全局
    // Teardown: free WorkMgr and purge all temp globals of this run
    If pProfile Set tCleanupStarted = $ZH
    If $IsObject(tManager) Do tManager.Free()
    If tRun '= "" Kill ^IRIS.Temp.GraphExBFS(tRun)
    If $$$ISERR(tStatus) Set pResult = []
    If pProfile Set pStats.cleanupMs = ($ZH-tCleanupStarted)*1000, pStats.totalMs = ($ZH-tStarted)*1000, pStats.complete = $$$ISOK(tStatus)
    Return tStatus
}

/// 中文：按并行任务块收集已暂存的边结果，并在成功读取后释放对应结果块。
/// 输出追加到 pResult，pCount 返回本次收集的边数；损坏的批记录会触发异常。
/// 入参：pRun 是本次运行标识，pResult 是追加目标；pCount 输出边数。
/// 示例：Do ##class(Graph.Tools).CollectResults(run,edges,.count)
///
/// English: Collect staged edge batches for a parallel run and release each result chunk after collection.
/// Results are appended to pResult and pCount reports the number collected; malformed batches raise an error.
/// Parameters: pRun identifies the traversal, pResult is the append target, and pCount receives the collected edge count.
/// Example: Do ##class(Graph.Tools).CollectResults(run,edges,.count)
ClassMethod CollectResults(pRun As %Integer, pResult As %DynamicArray, Output pCount As %Integer) [ Internal ]
{
    Set tChunk = "", pCount = 0
    For 
    {
        // 遍历每个任务块的结果区
        // Iterate the result area of each task chunk
        Set tChunk = $Order(^IRIS.Temp.GraphExBFS(pRun,"res",tChunk))
        Quit:tChunk=""
        Set tIndex = ""
        For 
        {
            // 每个批记录是一串 $lb(源,关系,目标) 三元组
            // Each batch record is a stream of $lb(source,relation,target) triples
            Set tIndex = $Order(^IRIS.Temp.GraphExBFS(pRun,"res",tChunk,tIndex),1,tBatch)
            Quit:tIndex=""
            Set tCursor = 0
            While $ListNext(tBatch,tCursor,tEdgeSource) 
            {
                // 依次取出关系与目标，三元组不完整视为损坏
                // Read relation and target in turn; an incomplete triple is treated as corrupt
                Set tHasRelation = $ListNext(tBatch,tCursor,tRelation), tHasTarget = $ListNext(tBatch,tCursor,tEdgeTarget)
                If 'tHasRelation || 'tHasTarget Throw ##class(%Exception.General).%New("INVALID_RESULT_BATCH")
                Do pResult.%Push({"OID":(tEdgeSource),"Relation":(tRelation),"TargetOID":(tEdgeTarget)})
                Set pCount = pCount+1
            }
        }
        // 收集完即释放该块结果区
        // Release this chunk's result area once collected
        Kill ^IRIS.Temp.GraphExBFS(pRun,"res",tChunk)
        Set tBatch = ""
    }
}

/// 中文：将高邻接度节点的 OUT/IN 邻接项切成有界范围并分派给工作块。
/// 小于阈值时不切分并返回 0；切分时返回范围数，同时更新任务大小、负载及工作索引。
/// 入参：pRun/pNode 标识运行和节点，pLimit/pWorkers 控制分片与工作数；pSizes/pLoads/pWorkIndex 更新分配信息，pUnsplitWeight 输出未切分权重。
/// 示例：Set ranges=..SplitNode(run,node,512,4,.sizes,.loads,.workIndex,1,.weight)
///
/// English: Split a high-degree node's OUT/IN adjacency entries into bounded ranges assigned to worker chunks.
/// Returns 0 below the split threshold; otherwise returns the range count and updates partition metadata.
/// Parameters: pRun/pNode identify the run and node; pLimit/pWorkers configure splitting; pSizes/pLoads/pWorkIndex track assignments and pUnsplitWeight returns the unsplit estimate.
/// Example: Set ranges=..SplitNode(run,node,512,4,.sizes,.loads,.workIndex,1,.weight)
ClassMethod SplitNode(pRun As %Integer, pNode, pLimit As %Integer, pWorkers As %Integer, ByRef pSizes, ByRef pLoads, ByRef pWorkIndex, pBalanced As %Boolean = 0, Output pUnsplitWeight As %Integer) As %Integer [ Internal ]
{
    Set pUnsplitWeight = 0
    // 先低成本探测度数：只数到 tProbeLimit 即止，避免对低度节点全扫
    // Cheaply probe the degree first: count only up to tProbeLimit to avoid full scans of low-degree nodes
    Set tProbeLimit = $Select(pLimit<2:pLimit,1:2), tDegree = 0
    Set tUnits = ..runUnits(pRun, .tUnit)
    For tU = 1:1:tUnits
    {
        Set tRoot = $List(tUnit(tU),2), tNeighbor = $Order(@tRoot@(pNode,""))
        While tNeighbor'=""
        {
            Set tDegree = tDegree+1
            Quit:tDegree>tProbeLimit
            Set tNeighbor = $Order(@tRoot@(pNode,tNeighbor))
        }
        Quit:tDegree>tProbeLimit
    }
    // 度数未超阈值：无需切分，回传权重并返回 0
    // Degree within threshold: no split needed; return the weight and 0
    If tDegree<=tProbeLimit 
    {
        Set pUnsplitWeight = $Select(tDegree:tDegree,1:1)
        Return 0
    }
    Set tTotal = 0, tRangeCount = 0, tStagedCount = 0
    // 无向：对 OUT 与 IN 两个方向分别切成每段至多 pLimit 的有界范围
    // Undirected: for both OUT and IN, cut into bounded ranges of at most pLimit entries each
    For tU = 1:1:tUnits
    {
        Set tRoot = $List(tUnit(tU),2), tNeighbor = "", tLower = "", tRangeSize = 0
        For 
        {
            Set tNext = $Order(@tRoot@(pNode,tNeighbor))
            If tNext'="" Set tNeighbor = tNext, tTotal = tTotal+1, tRangeSize = tRangeSize+1
            // 满一段（达到 pLimit）或该方向走完 → 记录一个 (方向,下界,上界,大小) 范围
            // On a full segment (reaching pLimit) or end of this direction → record one (dir,lower,upper,size) range
            If tRangeSize && ((tRangeSize=pLimit)||(tNext="")) 
            {
                Set tRangeCount = tRangeCount+1, tRanges(tRangeCount) = $ListBuild(tU,tLower,tNeighbor,tRangeSize)
                Set tLower = tNeighbor, tRangeSize = 0
                // 确认确需切分（总数超 pLimit）后，才把已累积的范围分派到工作块
                // Only once splitting is confirmed needed (total exceeds pLimit) do we dispatch the accumulated ranges to chunks
                If tTotal>pLimit 
                {
                    For tRangeIndex = tStagedCount+1:1:tRangeCount 
                    {
                        // 轮转分配；均衡模式下选负载最小的 chunk
                        // Round-robin assignment; in balanced mode pick the least-loaded chunk
                        Set tChunk = pWorkIndex#pWorkers, pWorkIndex = pWorkIndex+1, tRecord = tRanges(tRangeIndex)
                        If pBalanced 
                        {
                            Set tChunk = 0
                            For tCandidate = 1:1:pWorkers-1 
                            {
                                If $Get(pLoads(tCandidate))<$Get(pLoads(tChunk)) Set tChunk = tCandidate
                            }
                            Set pLoads(tChunk) = $Get(pLoads(tChunk))+$List(tRecord,4)
                        }
                        // 同一节点多次入块，各携带一个范围记录
                        // The same node is enqueued multiple times, each carrying one range record
                        Set tPosition = $Increment(pSizes(tChunk))
                        Set ^IRIS.Temp.GraphExBFS(pRun,"chunk",tChunk,tPosition) = pNode
                        Set ^IRIS.Temp.GraphExBFS(pRun,"range",tChunk,tPosition) = tRecord
                    }
                    Kill tRanges
                    Set tStagedCount = tRangeCount
                }
            }
            Quit:tNext=""
        }
    }
    // 实际总数未超阈值：撤销切分意图，按未切分处理
    // Actual total within threshold: abandon the split and treat as unsplit
    If tTotal<=pLimit 
    {
        Set pUnsplitWeight = $Select(tTotal>64:64,1:tTotal)
        Return 0
    }
    Return tRangeCount
}

/// 中文：估算节点的 OUT 与 IN 邻接项数量，最多探测 64 项以限制调度开销。
/// 无邻接节点返回最小权重 1，供均衡任务分配使用。
/// 入参：pNode 为待估算节点；返回有界邻接权重。
/// 示例：Set weight=##class(Graph.Tools).NeighborWeight(node)
///
/// English: Estimate a node's combined OUT/IN neighbor count, probing at most 64 entries.
/// An isolated node has minimum weight 1; the estimate is used for load balancing.
/// Parameter: pNode is the node to estimate; the method returns its bounded neighbor weight.
/// Example: Set weight=##class(Graph.Tools).NeighborWeight(node)
ClassMethod NeighborWeight(pNode, ByRef pUnit, pUnits As %Integer = "") As %Integer [ Internal ]
{
    If pUnits = "" Set pUnits = ..units(0, 1, "", .pUnit)
    Set tWeight = 0
    // 正/反两个方向累加邻居数，最多数到 64 即止（有界估算，限制开销）
    // Accumulate neighbor counts over both directions, capped at 64 (bounded estimate to limit overhead)
    For tU = 1:1:pUnits 
    {
        Set tRoot = $List(pUnit(tU),2), tNeighbor = ""
        For 
        {
            Set tNeighbor = $Order(@tRoot@(pNode,tNeighbor))
            Quit:tNeighbor=""
            Set tWeight = tWeight+1
            Quit:tWeight>=64
        }
        Quit:tWeight>=64
    }
    // 孤立节点也返回最小权重 1
    // An isolated node still returns the minimum weight 1
    Return $Select(tWeight:tWeight,1:1)
}

/// 中文：执行带任务计时的 BFS 工作块，并把进程号、排队延迟、运行时间和结果计数写入临时状态。
/// 该方法由并行调度器调用，实际遍历逻辑委托给 BFSWorker。
/// 入参：pRun/pChunk/pSlot 选择工作块，pBottomUp/pBuildFrontier 控制扫描和前沿，pQueuedAt 记录入队时间，pCacheLimit 限制缓存。
/// 示例：Set sc=##class(Graph.Tools).BFSProfileWorker(run,chunk,slot,0,1,$ZH,4096)
///
/// English: Execute a BFS worker while recording process, queue delay, runtime and result counts in run state.
/// Called by the parallel scheduler; traversal itself is delegated to BFSWorker.
/// Parameters: pRun/pChunk/pSlot identify the work; pBottomUp/pBuildFrontier select scan behavior; pQueuedAt records enqueue time and pCacheLimit bounds caching.
/// Example: Set sc=##class(Graph.Tools).BFSProfileWorker(run,chunk,slot,0,1,$ZH,4096)
ClassMethod BFSProfileWorker(pRun As %Integer, pChunk As %Integer, pSlot As %Integer, pBottomUp As %Boolean, pBuildFrontier As %Boolean, pQueuedAt As %Numeric, pCacheLimit As %Integer = 4096) As %Status [ Internal ]
{
    Set tStarted = $ZH
    // 委托给 BFSWorker 执行实际遍历
    // Delegate the actual traversal to BFSWorker
    Set tStatus = ..BFSWorker(pRun,pChunk,pSlot,pBottomUp,pBuildFrontier,0,"",.tCount,pCacheLimit,.tCacheEntries,.tStagedBatches)
    Set tFinished = $ZH
    // 记录本任务计时：进程号、排队延迟、运行时间、边数、成功位、缓存项数、批次数
    // Record this task's timing: process id, queue delay, runtime, edge count, success flag, cache entries, staged batches
    Set ^IRIS.Temp.GraphExBFS(pRun,"task",pChunk) = $ListBuild($Job,(tStarted-pQueuedAt)*1000,(tFinished-tStarted)*1000,tCount,$$$ISOK(tStatus),tCacheEntries,tStagedBatches)
    Return tStatus
}

/// 中文：处理一个并行 BFS 工作块，支持自顶向下/自底向上扫描、分片范围、前沿构建和结果批处理。
/// 输出发现边数、缓存项数及批次数；仅供 Graph.BFSParallel 等内部调度使用。
/// 入参：pRun/pChunk/pSlot 选择任务，pBottomUp/pBuildFrontier 控制遍历，pDirect/pResult 选择结果写入方式，pCacheLimit 限制缓存；其余输出参数返回计数。
/// 示例：Set sc=##class(Graph.Tools).BFSWorker(run,chunk,slot,0,1,0,"",.count,4096,.cacheEntries,.batches)
///
/// English: Process one parallel BFS chunk with top-down/bottom-up scans, optional ranges, frontier building and batching.
/// Reports discovered edges, cache entries and staged batches; intended for internal parallel scheduling.
/// Parameters: pRun/pChunk/pSlot identify the task; pBottomUp/pBuildFrontier select traversal behavior; pDirect/pResult select output; pCacheLimit bounds caching and output arguments return counts.
/// Example: Set sc=##class(Graph.Tools).BFSWorker(run,chunk,slot,0,1,0,"",.count,4096,.cacheEntries,.batches)
ClassMethod BFSWorker(pRun As %Integer, pChunk As %Integer, pSlot As %Integer, pBottomUp As %Boolean, pBuildFrontier As %Boolean = 1, pDirect As %Boolean = 0, pResult As %DynamicArray = "", Output pCount As %Integer, pCacheLimit As %Integer = 4096, Output pCacheEntries As %Integer, Output pStagedBatches As %Integer) As %Status [ Internal ]
{
    Set tStatus = $$$OK, pCount = 0, pCacheEntries = 0, pStagedBatches = 0
    Try
    {
        If (pCacheLimit < -1) || (pCacheLimit '= (pCacheLimit\1)) Throw ##class(%Exception.General).%New("INVALID_CACHE_LIMIT")
        Set tIndex = "", tSequence = 0, tNextSlot = 1-pSlot
        Set tBatch = "", tBatchCount = 0, tBatchIndex = 0
        // 本块是否带范围记录（高度节点被 SplitNode 切片）
        // Whether this chunk carries range records (high-degree nodes sliced by SplitNode)
        Set tHasRanges = $Data(^IRIS.Temp.GraphExBFS(pRun,"range",pChunk))>0
        // 扫描单元由调度者写入运行区，这里载入本地数组
        // The scheduler stores scan units in the run area; load them into a local array
        Set tUnits = ..runUnits(pRun, .tUnit)
        For 
        {
            // 遍历分派给本块的每个节点
            // Iterate each node assigned to this chunk
            Set tIndex = $Order(^IRIS.Temp.GraphExBFS(pRun, "chunk", pChunk, tIndex), 1, tNode)
            Quit:tIndex=""
            Set tRange = ""
            If tHasRanges Set tRange = $Get(^IRIS.Temp.GraphExBFS(pRun,"range",pChunk,tIndex))
            // bottom-up 不支持范围切片
            // bottom-up does not support range slicing
            If pBottomUp && (tRange'="") Throw ##class(%Exception.General).%New("INVALID_RANGE_MODE")
            // 有范围：仅扫该范围的单一方向 [下界,上界)；否则扫出/入两个方向全部
            // With a range: scan only that single direction over [lower,upper); otherwise scan both out/in directions fully
            Set tFound = 0, tFirstUnit = 1, tLastUnit = tUnits, tLower = "", tUpper = ""
            If tRange'="" Set tFirstUnit = $List(tRange,1), tLastUnit = tFirstUnit, tLower = $List(tRange,2), tUpper = $List(tRange,3)
            For tU = tFirstUnit:1:tLastUnit 
            {
                Set tDirection = $List(tUnit(tU),1), tRoot = $List(tUnit(tU),2), tNeighbor = tLower
                For 
                {
                    // 范围上界到达即止
                    // Stop at the range upper bound
                    If tRange'="" Quit:tNeighbor=tUpper
                    Set tNeighbor = $Order(@tRoot@(tNode, tNeighbor))
                    Quit:tNeighbor=""
                    If pBottomUp 
                    {
                        // pull：邻居须在当前前沿中，才认领本节点（tNode）
                        // pull: the neighbor must be in the current frontier to claim this node (tNode)
                        Continue:'$Data(^IRIS.Temp.GraphExBFS(pRun, "front", pSlot, tNeighbor))
                        Set tClaimed = tNode, ^IRIS.Temp.GraphExBFS(pRun, "vis", tClaimed) = 1
                    } 
                    Else 
                    {
                        // push：本地已见过则跳过
                        // push: skip if already seen locally
                        Continue:$Data(tSeen(tNeighbor))
                        // 全局已访问：在缓存上限内记入本地 seen 以省去重复全局读
                        // Already visited globally: cache into local seen (within the cache limit) to avoid repeated global reads
                        If $Data(^IRIS.Temp.GraphExBFS(pRun, "vis", tNeighbor)) {
                            If (pCacheLimit=-1) || (pCacheEntries<pCacheLimit) {
                                Set tSeen(tNeighbor) = 1, pCacheEntries = pCacheEntries+1
                            }
                            Continue
                        }
                        // 原子占用：仅把计数 0→1 的 worker 认领该邻居
                        // Atomic claim: only the worker bumping the count 0→1 claims this neighbor
                        Continue:$Increment(^IRIS.Temp.GraphExBFS(pRun, "vis", tNeighbor))'=1
                        Set tClaimed = tNeighbor
                    }
                    Set tRelation = $Order(@tRoot@(tNode, tNeighbor, ""))
                    // 需要时把认领到的节点加入下一层前沿
                    // Add the claimed node to the next-level frontier when requested
                    If pBuildFrontier Set ^IRIS.Temp.GraphExBFS(pRun, "front", tNextSlot, tClaimed) = ""
                    Set tSequence = tSequence+1
                    If pDirect 
                    {
                        // 直接写出：按真实边方向还原源/目标后推入 pResult
                        // Direct output: restore source/target by true edge direction and push into pResult
                        Set tEdgeSource = $Select(tDirection:tNeighbor,1:tNode), tEdgeTarget = $Select(tDirection:tNode,1:tNeighbor)
                        Do pResult.%Push({"OID":(tEdgeSource),"Relation":(tRelation),"TargetOID":(tEdgeTarget)})
                    } 
                    Else 
                    {
                        // 暂存模式：把边打包成 $lb 批，按条数/字节阈值切批写入临时结果区
                        // Staged mode: pack edges into a $lb batch, flushing to the temp result area on count/byte thresholds
                        Set tRecord = $Select(tDirection: $ListBuild(tNeighbor,tRelation,tNode), 1: $ListBuild(tNode,tRelation,tNeighbor))
                        If tBatchCount && ((tBatchCount>=128)||(($Length(tBatch)+$Length(tRecord))>32768)) 
                        {
                            Set tBatchIndex = tBatchIndex+1, ^IRIS.Temp.GraphExBFS(pRun,"res",pChunk,tBatchIndex) = tBatch
                            Set tBatch = "", tBatchCount = 0
                        }
                        Set tBatch = tBatch_tRecord, tBatchCount = tBatchCount+1
                    }
                    // bottom-up：本节点一旦认领即停止扫描其余邻居
                    // bottom-up: once this node is claimed, stop scanning its remaining neighbors
                    If pBottomUp { Set tFound = 1 Quit }
                }
                Quit:tFound
            }
        }
        // 冲刷最后一个未满批
        // Flush the final partially-filled batch
        If 'pDirect && tBatchCount Set tBatchIndex = tBatchIndex+1, ^IRIS.Temp.GraphExBFS(pRun,"res",pChunk,tBatchIndex) = tBatch
    }
    Catch tException
    {
        Set tStatus = tException.AsStatus()
    }
    If $$$ISOK(tStatus) Set pCount = tSequence, pStagedBatches = tBatchIndex
    Return tStatus
}


/// 中文：双向 BFS 的「扩展一层」。用间接引用区分正/反两侧的进程私有全局。
/// pVis 本侧 visited 根；pOpp 对侧 visited 根；pPar/pRel 本侧父/边根；
/// pCur 当前层前沿根（输入）；pNext 下一层前沿根（输出，调用方已 Kill）。
/// 返回相遇节点 OID（本次新发现且已在对侧 visited），无则 ""。
///
/// English: The "expand one level" of bidirectional BFS. Uses indirection to distinguish the process-private globals of the forward/backward sides.
/// pVis: this side's visited root; pOpp: the opposite side's visited root; pPar/pRel: this side's parent/edge roots;
/// pCur: current-level frontier root (input); pNext: next-level frontier root (output, already Killed by the caller).
/// Returns the meeting node OID (newly discovered this round and already in the opposite side's visited), or "" if none.
ClassMethod expandLevel(pVis As %String, pOpp As %String, pPar As %String, pRel As %String, pCur As %String, pNext As %String) As %String [ Internal ]
{
    Set tMeet = ""
    Try 
    {
        Set tNode = ""
        // 遍历本层前沿的每个节点（间接引用到指定全局）
        // Iterate each node of this level's frontier (indirection to the specified global)
        For 
        {
            Set tNode = $Order(@pCur@(tNode))  Quit:tNode=""     
            // 无向：正向(出边)、反向(入边) 均展开
            // Undirected: expand both forward (out-edge) and reverse (in-edge)
            For tDir = 0, 1 
            {                                    
                Kill tNbr
                // 枚举该方向邻居
                // Enumerate neighbors in that direction
                Do ..eachNeighbor(tNode, "", tDir, .tNbr)        
                For tI = 1:1:$Get(tNbr, 0) 
                {
                    Set tEntry = tNbr(tI), tNext = $List(tEntry, 1), tRel = $List(tEntry, 2)
                    // 本侧已访问 → 跳过
                    // Already visited on this side → skip
                    Continue:$Data(@pVis@(tNext))  
                    // 标记本侧已访问              
                    // Mark visited on this side
                    Set @pVis@(tNext) = 1    
                    // 记录父（用于回溯）                    
                    // Record parent (for backtracking)
                    Set @pPar@(tNext) = tNode          
                    // 记录连接边：$lb(rel,真实方向)          
                    // Record the connecting edge: $lb(rel, true direction)
                    Set @pRel@(tNext) = $ListBuild(tRel, tDir)  
                     // 加入下一层前沿 
                     // Add to the next-level frontier
                    Set @pNext@(tNext) = 1      
                     // 已在对侧 visited → 相遇                
                     // Already in the opposite side's visited → they meet
                    If $Data(@pOpp@(tNext)) { Set tMeet = tNext  Quit }  
                }
                Quit:tMeet'=""
            }
            Quit:tMeet'=""
        }
    }
    Catch ex {}
    Quit tMeet
}

/// 中文：并行 BFS 的 worker（每个 work 单元在独立进程内运行）。
/// 用 $Increment 原子占用 visited 做无锁去重：首个把某节点计数从 0→1 的 worker「拥有」它，
/// 负责产出边到本片结果区、并把它加入下一层前沿；其余 worker（计数>1）跳过。
/// pRun：运行编号；pChunk：本 work 单元负责的前沿分片号。
/// 产出：^IRIS.Temp.GraphBFS(pRun,"res",pChunk,序号)=$lb(源,关系,目标)；^IRIS.Temp.GraphBFS(pRun,"nfront",新节点)=1。
/// 返回：%Status。
///
/// English: The worker of parallel BFS (each work unit runs in a separate process).
/// Uses $Increment atomic claim on visited for lock-free dedup: the first worker to bump a node's count from 0→1 "owns" it,
/// responsible for producing the edge into this slice's result area and adding it to the next-level frontier; other workers (count>1) skip it.
/// pRun: run id; pChunk: the frontier slice number this work unit is responsible for.
/// Output: ^IRIS.Temp.GraphBFS(pRun,"res",pChunk,seq)=$lb(source,relation,target); ^IRIS.Temp.GraphBFS(pRun,"nfront",newNode)=1.
/// Returns: %Status.
ClassMethod BFSParWorker(pRun As %Integer, pChunk As %Integer) As %Status [ Internal ]
{
    Set tSC = $$$OK
    Try 
    {
        Set tSeq = 0, tI = ""
        // 遍历本片分配到的每个前沿节点
        // Iterate each frontier node assigned to this slice
        For 
        {
            Set tI = $Order(^IRIS.Temp.GraphBFS(pRun, "chunk", pChunk, tI), 1, tNode)  Quit:tI=""
            // 无向：正向 + 反向邻居
            // Undirected: forward + reverse neighbors
            For tDir = 0, 1 
            {
                Kill tNbr
                Do ..eachNeighbor(tNode, "", tDir, .tNbr)
                For tJ = 1:1:$Get(tNbr, 0) 
                {
                    Set tEntry = tNbr(tJ), tNb = $List(tEntry, 1), tRel = $List(tEntry, 2)
                    // 原子占用：仅当把计数 0→1（返回 1）时才「拥有」该节点
                    // Atomic claim: only "owns" the node when bumping the count 0→1 (returns 1)
                    Continue:$Increment(^IRIS.Temp.GraphBFS(pRun, "vis", tNb))'=1
                    // 加入下一层前沿
                    // Add to the next-level frontier
                    Set ^IRIS.Temp.GraphBFS(pRun, "nfront", tNb) = 1
                    Set tSeq = tSeq + 1
                    // 正向：tNode--rel-->tNb；反向：tNb--rel-->tNode（源/目标按真实边方向）
                    // Forward: tNode--rel-->tNb; reverse: tNb--rel-->tNode (source/target per true edge direction)
                    If tDir = 0 { Set ^IRIS.Temp.GraphBFS(pRun, "res", pChunk, tSeq) = $ListBuild(tNode, tRel, tNb) }
                    Else        { Set ^IRIS.Temp.GraphBFS(pRun, "res", pChunk, tSeq) = $ListBuild(tNb, tRel, tNode) }
                }
            }
        }
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 中文：并行 BFS 的 **bottom-up（pull）** worker（方向优化用，每个 work 单元独立进程运行）。
/// 遍历本片分配到的**未访问**节点，对每个节点扫其正/反向邻居，一旦发现某邻居在**当前前沿**中，
/// 即认领该节点（标 vis + 加入 nfront）、按真实边方向产出一条边、**立即停止扫描**（命中即止）。
/// 因每个未访问节点仅由唯一 worker 处理，认领无跨进程竞争（无需 $Increment）。
/// pRun：运行编号；pChunk：本 work 单元负责的未访问节点分片号。
/// 产出：^IRIS.Temp.GraphBFS(pRun,"res",pChunk,序号)=$lb(源,关系,目标)；^IRIS.Temp.GraphBFS(pRun,"nfront",新节点)=1。
/// 返回：%Status。
///
/// English: The **bottom-up (pull)** worker of parallel BFS (for direction optimization; each work unit runs in a separate process).
/// Iterate the **unvisited** nodes assigned to this slice; for each node scan its forward/reverse neighbors, and once a neighbor is found in the **current frontier**,
/// claim that node (mark vis + add to nfront), produce one edge per the true edge direction, and **stop scanning immediately** (stop on first hit).
/// Since each unvisited node is handled by exactly one worker, claiming has no cross-process contention (no $Increment needed).
/// pRun: run id; pChunk: the unvisited-node slice number this work unit is responsible for.
/// Output: ^IRIS.Temp.GraphBFS(pRun,"res",pChunk,seq)=$lb(source,relation,target); ^IRIS.Temp.GraphBFS(pRun,"nfront",newNode)=1.
/// Returns: %Status.
ClassMethod BFSParWorkerBU(pRun As %Integer, pChunk As %Integer) As %Status [ Internal ]
{
    Set tSC = $$$OK
    Try 
    {
        Set tSeq = 0, tI = ""
        // 遍历本片分配到的每个未访问节点
        // Iterate each unvisited node assigned to this slice
        For 
        {
            Set tI = $Order(^IRIS.Temp.GraphBFS(pRun, "chunk", pChunk, tI), 1, tNode)  Quit:tI=""
            Set tFound = 0
            // 无向：先看正向邻居，再看反向邻居；命中前沿即止
            // Undirected: check forward neighbors first, then reverse neighbors; stop once a frontier neighbor is hit
            For tDir = 0, 1 
            {
                Kill tNbr
                Do ..eachNeighbor(tNode, "", tDir, .tNbr)
                For tJ = 1:1:$Get(tNbr, 0) 
                {
                    Set tEntry = tNbr(tJ), tNb = $List(tEntry, 1), tRel = $List(tEntry, 2)
                    // 邻居必须在「当前前沿」中，方可作为父节点认领 tNode
                    // The neighbor must be in the "current frontier" to serve as parent and claim tNode
                    Continue:'$Data(^IRIS.Temp.GraphBFS(pRun, "front", tNb))  
                    // 认领 tNode（本片独占，无竞争）
                    // Claim tNode (exclusive to this slice, no contention)
                    Set ^IRIS.Temp.GraphBFS(pRun, "vis", tNode) = 1
                    Set ^IRIS.Temp.GraphBFS(pRun, "nfront", tNode) = 1
                    Set tSeq = tSeq + 1
                    // 正向邻居：tNode--rel-->tNb（真实边 tNode→tNb）；反向邻居：tNb--rel-->tNode
                    // Forward neighbor: tNode--rel-->tNb (true edge tNode→tNb); reverse neighbor: tNb--rel-->tNode
                    If tDir = 0 { Set ^IRIS.Temp.GraphBFS(pRun, "res", pChunk, tSeq) = $ListBuild(tNode, tRel, tNb) }
                    Else        { Set ^IRIS.Temp.GraphBFS(pRun, "res", pChunk, tSeq) = $ListBuild(tNb, tRel, tNode) }
                    Set tFound = 1
                    Quit                                     // 命中即止：不再扫本方向剩余邻居 | Stop on first hit: don't scan the remaining neighbors of this direction
                }
                Quit:tFound                                  // 已认领：另一方向也不必扫 | Already claimed: no need to scan the other direction either
            }
        }
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}
/// 中文：展开扫描单元——每个 (方向, 层) 一个 $ListBuild(方向, 全局根)；pFirst..pLast 为方向区间（0=出边 OUT，1=入边 IN）。返回单元数。
/// English: Expand scan units — one $ListBuild(direction, global root) per (direction, layer); pFirst..pLast is the direction range (0=OUT, 1=IN). Returns the unit count.
ClassMethod units(pFirst As %Integer, pLast As %Integer, pLayers As %String = "", Output pUnit) As %Integer [ Internal ]
{
    Kill pUnit
    Set tViews = ##class(Graph.Layer).View(pLayers), tN = 0
    For tD = pFirst:1:pLast
    {
        For tI = 1:1:$ListLength(tViews)
        {
            Set tN = tN + 1, pUnit(tN) = $ListBuild(tD, ##class(Graph.Layer).Root($Select(tD: "IN", 1: "OUT"), $List(tViews, tI)))
        }
    }
    Quit tN
}

/// 中文：读取一次并行运行的扫描单元；运行区没有存储时退化为当前视图（供直接调用 worker 的测试使用）。
/// English: Load the scan units of a parallel run; falls back to the current view when the run area holds none (for tests calling workers directly).
ClassMethod runUnits(pRun As %Integer, Output pUnit) As %Integer [ Internal ]
{
    Kill pUnit
    Set tN = +$Get(^IRIS.Temp.GraphExBFS(pRun, "units"))
    If tN
    {
        For tU = 1:1:tN Set pUnit(tU) = ^IRIS.Temp.GraphExBFS(pRun, "units", tU)
        Quit tN
    }
    Quit ..units(0, 1, "", .pUnit)
}

/// 中文：节点在任一扫描单元中有边则返回 1。
/// English: Return 1 when the node has edges in any scan unit.
ClassMethod hasNode(ByRef pUnit, pUnits As %Integer, pNode) As %Boolean [ Internal ]
{
    For tU = 1:1:pUnits
    {
        Set tRoot = $List(pUnit(tU), 2)
        Return:$Data(@tRoot@(pNode)) 1
    }
    Quit 0
}

/// 中文：跨扫描单元的 SingleHopNext：当前单元耗尽后自动推进到下一单元（pU 初始为 1，pNbr/pRel/pRi 初始为空/空/0）。
/// English: SingleHopNext across scan units: advances to the next unit when the current one is exhausted (start with pU=1 and pNbr/pRel/pRi = ""/""/0).
ClassMethod UnitNext(ByRef pUnit, pUnits As %Integer, pNode, pRelList As %List, ByRef pU, ByRef pNbr, ByRef pRel, ByRef pRi) As %Boolean [ Internal ]
{
    For
    {
        If pU > pUnits Return 0
        If ..SingleHopNext($List(pUnit(pU), 2), pNode, pRelList, .pNbr, .pRel, .pRi) Return 1
        Set pU = pU + 1, pNbr = "", pRel = "", pRi = 0
    }
}

/// 中文：用于支持 SQL 访问，把关系约束字符串解析为 %List。
/// pRelation：关系约束字符串，空=不过滤，逗号分隔=多个关系。
/// 返回：%List 关系列表，""=不过滤（含 SQL 传入的 $Char(0) 情形）。
///
/// English: Parse a relation constraint string into a %List, used to support SQL access.
/// pRelation: relation constraint string, empty = no filter, comma-separated = multiple relations.
/// Returns: %List relation list, "" = no filter (including the $Char(0) case passed in by SQL).
ClassMethod relList(pRelation As %String) As %List [ Internal ]
{
    Set tRet = ""
    Try 
    {
        // SQL TVF 派发会把带默认值的空/NULL 关系参数传成 $Char(0)，需与 "" 一并视为"不过滤"
        // SQL TVF dispatch passes an empty/NULL relation parameter with a default value as $Char(0), which must be treated together with "" as "no filter"
        Set tRet = $Select((pRelation = "") || (pRelation = $Char(0)): "", 1: $ListFromString(pRelation, ","))
    }
    Catch ex {}
    Quit tRet
}

/// 中文：枚举 pNode 的邻居（$Order 固定下标；反向走入边索引）。
/// pNode：待枚举邻居的节点 OID（$ListBuild(Id, Class)）。
/// pRelList：$List 关系列表，""=全部。
/// pInverse：0=出边（邻居=目标），1=入边（邻居=源）。
/// 出参 pNbr：pNbr(tI)=$ListBuild(邻居OID, Relation)，pNbr=条数（支持追加）。
/// 返回：邻居总条数（等同回写后的 pNbr）。
///
/// English: Enumerate pNode's neighbors ($Order over fixed subscripts; reverse uses the in-edge index).
/// pNode: the OID of the node whose neighbors are to be enumerated ($ListBuild(Id, Class)).
/// pRelList: $List relation list, "" = all.
/// pInverse: 0 = out-edge (neighbor = target), 1 = in-edge (neighbor = source).
/// Output param pNbr: pNbr(tI)=$ListBuild(neighborOID, Relation), pNbr = count (supports appending).
/// Returns: the total neighbor count (equals pNbr after write-back).
ClassMethod eachNeighbor(pNode, pRelList As %List, pInverse As %Boolean, ByRef pNbr, pLayers As %String = "", pLay As %String = "") [ Internal ]
{
    // pLay 为空：按视图内每一层各枚举一次并追加
    // Empty pLay: enumerate once per layer in the view, appending
    If pLay = ""
    {
        Set tViews = ##class(Graph.Layer).View(pLayers), pNbr = $Get(pNbr, 0)
        For tLI = 1:1:$ListLength(tViews) Do ..eachNeighbor(pNode, pRelList, pInverse, .pNbr, "", $List(tViews, tLI))
        Quit pNbr
    }
    // 支持追加：从已有条数接着记
    // Support appending: continue from the existing count
    Set tN = $Get(pNbr, 0)                                   
    Try 
    {
        // === 正向：走 ^GraphData.OUT，邻居=目标 ===
        // === Forward: via ^GraphData.OUT, neighbor = target ===
        If pInverse = 0 
        {       
            // 不过滤关系                                
            // No relation filter
            If pRelList = "" 
            {                                   
                Set tTgt = ""
                For 
                {
                    // 遍历该源下所有目标
                    // Iterate all targets under this source
                    Set tTgt = $Order(^GraphData.OUT(pLay, pNode, tTgt))  
                    Quit:tTgt=""  
                    Set tRel = ""
                    For 
                    {
                        // 遍历该(源,目标)下所有关系（折叠多重边）
                        // Iterate all relations under this (source, target) (collapsing multi-edges)
                        Set tRel = $Order(^GraphData.OUT(pLay, pNode, tTgt, tRel))  
                        Quit:tRel=""  
                        // 收集 (邻居=目标, 关系)
                        // Collect (neighbor = target, relation)
                        Set tN = tN + 1, pNbr(tN) = $ListBuild(tTgt, tRel)  
                    }
                }
            } 
            // 按给定关系列表过滤（B 布局关系在末位，需按目标逐个 $Data 判定）
            // Filter by the given relation list (in B layout the relation is the last subscript, so probe per target with $Data)
            Else 
            {                                            
                Set tTgt = ""
                For 
                {
                    Set tTgt = $Order(^GraphData.OUT(pLay, pNode, tTgt))  
                    Quit:tTgt=""
                    For tRI = 1:1:$ListLength(pRelList) 
                    {
                        Set tRel = $List(pRelList, tRI)
                        If $Data(^GraphData.OUT(pLay, pNode, tTgt, tRel)) { Set tN = tN + 1, pNbr(tN) = $ListBuild(tTgt, tRel) }
                    }
                }
            }
        } 
        // === 反向：走入边索引 ^GraphData.IN，邻居=源 ===
        // === Reverse: via the in-edge index ^GraphData.IN, neighbor = source ===
        Else 
        {                                                
            If pRelList = "" 
            {
                Set tSrc = ""
                For 
                {
                    // 入边索引以目标为首下标 → O(入度)
                    // The in-edge index uses the target as the first subscript → O(in-degree)
                    Set tSrc = $Order(^GraphData.IN(pLay, pNode, tSrc))  
                    Quit:tSrc=""  
                    Set tRel = ""
                    For 
                    {
                        // 遍历该(目标,源)下所有关系（折叠多重边）
                        // Iterate all relations under this (target, source) (collapsing multi-edges)
                        Set tRel = $Order(^GraphData.IN(pLay, pNode, tSrc, tRel))  
                        Quit:tRel=""
                        // 收集 (邻居=源, 关系)
                        // Collect (neighbor = source, relation)
                        Set tN = tN + 1, pNbr(tN) = $ListBuild(tSrc, tRel)  
                    }
                }
            } 
            Else 
            {
                Set tSrc = ""
                For 
                {
                    Set tSrc = $Order(^GraphData.IN(pLay, pNode, tSrc))  
                    Quit:tSrc=""
                    For tRI = 1:1:$ListLength(pRelList) 
                    {
                        Set tRel = $List(pRelList, tRI)
                        // B 布局关系在末位：需按 (目标,源,关系) 命中判定
                        // In B layout the relation is the last subscript: probe by (target, source, relation) hit
                        If $Data(^GraphData.IN(pLay, pNode, tSrc, tRel)) { Set tN = tN + 1, pNbr(tN) = $ListBuild(tSrc, tRel) }
                    }
                }
            }
        }
    }
    Catch ex {}
    // 回写总条数
    // Write back the total count
    Set pNbr = tN                                           
    Quit tN
}

/// 中文：多跳 DFS（去对象化中间结果；仅末跳边构造 JSON）。
/// pNode：当前跳的起点节点 OID（$ListBuild(Id, Class)）。
/// pDepth：当前步序（1 起），达到 pRL 长度即末层。
/// pRL：$List 关系路径，每项 $ListBuild(关系, 方向0/1)。
/// pResult：出参，%DynamicArray，累积末跳边 [{ "OID", "Relation", "TargetOID" }, ...]。
///
/// English: Multi-hop DFS (de-objectified intermediate results; only the last-hop edge builds JSON).
/// pNode: the start node OID of the current hop ($ListBuild(Id, Class)).
/// pDepth: the current step (starting at 1); reaching pRL's length means the last level.
/// pRL: $List relation path, each item $ListBuild(relation, direction 0/1).
/// pResult: output param, %DynamicArray, accumulates the last-hop edges [{ "OID", "Relation", "TargetOID" }, ...].
ClassMethod dfs(pNode, pDepth As %Integer, pRL As %List, ByRef pResult As %DynamicArray) [ Internal ]
{
    Try 
    {
        // 关系路径总长（最终深度）
        // Total length of the relation path (final depth)
        Set tLL = $ListLength(pRL)                  
        // 本层关系与方向             
        // Relation and direction of this level
        Set tItem = $List(pRL, pDepth), tRel = $List(tItem, 1), tInv = $List(tItem, 2)  
        // (节点,关系,方向) 已处理 → 去重
        // (node, relation, direction) already processed → dedup
        Quit:$Data(^||AGProcessed(pNode, tRel, tInv))            
        // 标记已处理
        // Mark as processed
        Set ^||AGProcessed(pNode, tRel, tInv) = 1               

        Kill tNbr
        // 只沿本层关系+方向展开一步
        // Expand only one step along this level's relation + direction
        Do ..eachNeighbor(pNode, $ListBuild(tRel), tInv, .tNbr)  
        For tI = 1:1:$Get(tNbr, 0) 
        {
            // 下一跳节点
            // Next-hop node
            Set tEntry = tNbr(tI), tNext = $List(tEntry, 1)  
            // 已到最后一步：只把末跳边构造为 JSON    
            // Reached the last step: build only the last-hop edge as JSON
            If pDepth = tLL 
            {                                   
                Set tJSON = {}
                // 正向末跳
                // Forward last hop
                If tInv = 0 
                {                                   
                    Set tJSON.OID = pNode, tJSON.Relation = tRel, tJSON.TargetOID = tNext
                } 
                // 反向末跳
                // Reverse last hop
                Else 
                {                                        
                    Set tJSON.OID = tNext, tJSON.Relation = tRel, tJSON.TargetOID = pNode
                }
                Do pResult.%Push(tJSON)
            } 
            // 未到末层：中间结果不建对象，直接递归下一层
            // Not the last level: intermediate results build no objects, recurse directly to the next level
            Else 
            {                                            
                Do ..dfs(tNext, pDepth + 1, pRL, .pResult)
            }
        }
    }
    Catch ex {}
}
}
