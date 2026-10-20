/// 面向对象图数据的查询工具（配合 Graph.Object.Base / Graph.Object.Index 使用）。
/// Query tools for object-oriented graph data (used together with Graph.Object.Base / Graph.Object.Index).
///
/// 继承 Graph.Tools 的全部遍历能力，另加「按业务号」入口：
/// Inherits all traversal capabilities of Graph.Tools, plus a "by business number" entry point:
/// 业务类需实现 ClassMethod GetOIDByNO(pNO As %String) As %String，
/// The business class must implement ClassMethod GetOIDByNO(pNO As %String) As %String,
/// 返回该业务号对应行的 $ListBuild(Id, Class)，无则返回 ""。
/// returning $ListBuild(Id, Class) of the row for that business number, or "" if none.
///
/// Author: QP
/// Version: 2.0
/// Last Modified Date: 2026/07/26
Class Graph.Object.Tools Extends Graph.Tools
{

/// 将业务号解析为节点 OID
/// Resolve a business number into a node OID
/// pClass：业务类名（完整类名）  pNodeNO：业务号
/// pClass: business class name (full class name)  pNodeNO: business number
/// 返回 $ListBuild(Id, Class)；解析失败或参数为空时返回 ""
/// Returns $ListBuild(Id, Class); returns "" on resolution failure or empty parameters
ClassMethod GetOID(pClass, pNodeNO) As %String
{
    Q:(pClass="")||(pNodeNO="") ""                          // 类名或业务号为空 → 无法解析 | class name or business number empty -> cannot resolve
    Set tOID = ""
    Try 
    {
        // 动态调用业务类自实现的 GetOIDByNO，返回 $ListBuild(Id, Class)
        // Dynamically call the business class's own GetOIDByNO, returning $ListBuild(Id, Class)
        Set tOID = $ZOBJCLASSMETHOD(pClass, "GetOIDByNO", pNodeNO)
    }
    Catch ex { Set tOID = "" }                              // 类未实现该方法/报错 → 视为解析失败 | class doesn't implement the method / errored -> treat as resolution failure
    Quit tOID
}

/// 按业务号的单跳查询
/// Single-hop query by business number
ClassMethod SingleHopWithNO(pClass, pNodeNO, pRelation As %String = "", pInverse As %Boolean = 0, Output pResult As %DynamicArray, pLayers As %String = "") As %Status
{
    Set tSC = $$$OK
    Q:(pClass="")||(pNodeNO="") $$$ERROR(-1000, "起跳节点不可以为空")
    Try 
    {
        Set tNode = ..GetOID(pClass, pNodeNO)               // 业务号 → OID | business number -> OID
        If tNode = "" { Set tSC = $$$ERROR(-1000, "起跳节点不存在")  Quit }
        Set tSC = ..SingleHop(tNode, pRelation, pInverse, .pResult, pLayers)  // 委托给基类快速引擎 | delegate to the base class's fast engine
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 按业务号的多跳查询
/// Multi-hop query by business number
ClassMethod MultiHopWithNO(pClass, pNodeNO, pRelList As %DynamicArray, Output pResult As %DynamicArray, pLayers As %String = "") As %Status
{
    Set tSC = $$$OK
    Q:(pClass="")||(pNodeNO="") $$$ERROR(-1000, "起跳节点不可以为空")
    Try 
    {
        Set tNode = ..GetOID(pClass, pNodeNO)               // 业务号 → OID | business number -> OID
        If tNode = "" { Set tSC = $$$ERROR(-1000, "起跳节点不存在")  Quit }
        Set tSC = ..MultiHop(tNode, pRelList, .pResult, pLayers)      // 委托给基类多跳 | delegate to the base class's multi-hop
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 按业务号的最短路径查询
/// Shortest-path query by business number
ClassMethod ShortestPathWithNO(pStartClass, pStartNodeNO, pEndClass, pEndNodeNO, Output pResult As %DynamicArray, pLayers As %String = "") As %Status
{
    Set tSC = $$$OK
    Q:(pStartClass="")||(pStartNodeNO="")||(pEndClass="")||(pEndNodeNO="") $$$ERROR(-1000, "起跳和结束节点不可以为空")
    Try 
    {
        Set tStartNode = ..GetOID(pStartClass, pStartNodeNO)  // 起点业务号 → OID | start business number -> OID
        Set tEndNode = ..GetOID(pEndClass, pEndNodeNO)        // 终点业务号 → OID | end business number -> OID
        If (tStartNode="")||(tEndNode="") { Set tSC = $$$ERROR(-1000, "起跳或结束节点不存在")  Quit }
        Set tSC = ..ShortestPath(tStartNode, tEndNode, .pResult, , , pLayers)  // 委托给基类双向 BFS | delegate to the base class's bidirectional BFS
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 按业务号的广度优先遍历
/// Breadth-first traversal by business number
ClassMethod BFSWithNO(pStartClass, pStartNodeNO, pMaxDepth As %Integer, Output pResult As %DynamicArray, pLayers As %String = "") As %Status
{
    Set tSC = $$$OK
    Q:(pStartClass="")||(pStartNodeNO="") $$$ERROR(-1000, "起跳节点不可以为空")
    Try 
    {
        Set tStartNode = ..GetOID(pStartClass, pStartNodeNO)  // 业务号 → OID | business number -> OID
        If tStartNode = "" { Set tSC = $$$ERROR(-1000, "起跳节点不存在")  Quit }
        Set tSC = ..BFS(tStartNode, pMaxDepth, .pResult, pLayers)     // 委托给基类 BFS | delegate to the base class's BFS
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 按业务号的多进程并行广度优先遍历（超大图，委托基类 BFSParallel）
/// Multi-process parallel breadth-first traversal by business number (very large graphs, delegates to base class BFSParallel)
/// pStartClass/pStartNodeNO：起点业务类名 + 业务号
/// pStartClass/pStartNodeNO: start business class name + business number
/// pMaxDepth：最大遍历深度
/// pMaxDepth: maximum traversal depth
/// pResult：出参，%DynamicArray，[{ "OID":源, "Relation":rel, "TargetOID":目标 }, ...]
/// pResult: output parameter, %DynamicArray, [{ "OID":source, "Relation":rel, "TargetOID":target }, ...]
/// pWorkers：每层并行分片数（<=0 取默认 8）
/// pWorkers: number of parallel shards per level (<=0 uses default 8)
/// 返回：%Status
/// Returns: %Status
ClassMethod BFSParallelWithNO(pStartClass, pStartNodeNO, pMaxDepth As %Integer, Output pResult As %DynamicArray, pWorkers As %Integer = 0, pLayers As %String = "") As %Status
{
    Set tSC = $$$OK
    Q:(pStartClass="")||(pStartNodeNO="") $$$ERROR(-1000, "起跳节点不可以为空")
    Try 
    {
        Set tStartNode = ..GetOID(pStartClass, pStartNodeNO)  // 业务号 → OID | business number -> OID
        If tStartNode = "" { Set tSC = $$$ERROR(-1000, "起跳节点不存在")  Quit }
        Set tSC = ..BFSParallel(tStartNode, pMaxDepth, .pResult, pWorkers, , , , , , , pLayers)  // 委托给基类并行 BFS | delegate to the base class's parallel BFS
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

}
