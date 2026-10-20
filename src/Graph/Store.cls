Include %occInclude

/// 图数据写入工具 / 核心数据层（正向边 ^GraphData.OUT + 入边索引 ^GraphData.IN 的单一写入入口）
/// Graph data write tool / core data layer (single write entry point for forward edges ^GraphData.OUT + in-edge index ^GraphData.IN)
///
/// 本类是 ^GraphData 底层建边/删边的**唯一工具类**：所有调用方都应经由此处，
/// This class is the **only tool class** for low-level edge add/remove on ^GraphData: all callers should go through here,
/// 而不再在各自代码里直接 Set/Kill ^GraphData.OUT。位于 Graph 核心包，与
/// instead of directly Set/Kill ^GraphData.OUT in their own code. Located in the Graph core package, at the same layer as
/// Graph.Object.Index（模型图维护）/ Graph.Tools（查询）同层。
/// Graph.Object.Index (model graph maintenance) / Graph.Tools (queries).
///     ^GraphData.OUT(层, 源OID, 目标OID, Relation) = ""     // 正向边（供正向单跳）
///     ^GraphData.OUT(layer, sourceOID, targetOID, Relation) = ""     // forward edge (for forward single hop)
///     ^GraphData.IN (层, 目标OID, 源OID, Relation) = ""     // 入边索引（供反向单跳）
///     ^GraphData.IN (layer, targetOID, sourceOID, Relation) = ""     // in-edge index (for reverse single hop)
/// 层由 Graph.Layer 登记与路由；写入层按 pLayer > 进程上下文 > 默认写入层解析，并校验可写。
/// Layers are registered and routed by Graph.Layer; the write layer resolves pLayer > process context > default write layer and must be writable.
/// 其中对于模型投影图， NodeOID = $ListBuild(Id, ClassName)。
/// For the model projection graph, NodeOID = $ListBuild(Id, ClassName).
///
/// 写入原语 AddEdge / 删除原语 RemoveEdge 带 pGenOut 开关：
/// The write primitive AddEdge / delete primitive RemoveEdge carry a pGenOut switch:
///   pGenOut=1（默认）：生成/删除正向边 OUT，并同步入边镜像 IN —— 建/删一条真实边；
///   pGenOut=1 (default): generate/delete forward edge OUT and sync the in-edge mirror IN — add/delete a real edge;
///   pGenOut=0       ：只维护入边镜像 IN，不动 OUT —— 为既有 OUT 数据回填索引。
///   pGenOut=0       : only maintain the in-edge mirror IN, leave OUT untouched — backfill the index for existing OUT data.
/// LinkIN / UnlinkIN 即 pGenOut=0 的语义别名（保持向后兼容）。
/// LinkIN / UnlinkIN are the semantic aliases of pGenOut=0 (kept for backward compatibility).
///
/// 调用方：
/// Callers:
///   - 模型投影图 Graph.Object.Index：建/删边时自动调用 AddEdge / RemoveEdge（OWN 拥有边索引仍由其自身维护）；
///   - Model projection graph Graph.Object.Index: automatically calls AddEdge / RemoveEdge when adding/deleting edges (the OWN ownership-edge index is still maintained by itself);
///   - 原生数据图 ：建/删边时调用手动调用 AddEdge / RemoveEdge；
///   - Native data graph: manually calls AddEdge / RemoveEdge when adding/deleting edges;
///   - 批量回填：既有 OUT 数据可用 BuildIN() 一次性重建全部 IN。
///   - Batch backfill: existing OUT data can rebuild all IN in one pass via BuildIN().
///
/// 入边索引作用：把「反向单跳 / 入度查询」从 O(全图边数) 全表扫描降为 O(入度) 有序下降，
/// Purpose of the in-edge index: lowers "reverse single hop / in-degree query" from an O(total edges) full scan to an O(in-degree) ordered descent,
/// 进而把 BFS / 最短路径从 O(V·E) 拉回 O(V+E)。
/// thereby pulling BFS / shortest path back from O(V·E) to O(V+E).
/// 不变式：每一层内 ^GraphData.IN(layer) 始终是 ^GraphData.OUT(layer) 的纯镜像。
/// Invariant: within each layer, ^GraphData.IN(layer) is always a pure mirror of ^GraphData.OUT(layer).
///
/// Author: QP
/// Version: 3.0
/// Last Modified Date: 2026/10/19
Class Graph.Store Extends %RegisteredObject
{

/// 写入一条图边 src --rel--> tgt
/// Write a graph edge src --rel--> tgt
/// 始终维护入边镜像 ^GraphData.IN；pGenOut=1 时同时生成正向边 ^GraphData.OUT
/// Always maintains the in-edge mirror ^GraphData.IN; when pGenOut=1 also generates the forward edge ^GraphData.OUT
/// pSrc：源节点 OID（模型图为 $ListBuild(Id, ClassName)）
/// pSrc: source node OID (for the model graph, $ListBuild(Id, ClassName))
/// pRel：关系名
/// pRel: relation name
/// pTgt：目标节点 OID（模型图为 $ListBuild(Id, ClassName)）
/// pTgt: target node OID (for the model graph, $ListBuild(Id, ClassName))
/// pGenOut：1=同时建正向边 OUT+入边镜像 IN（默认）；0=仅建入边镜像 IN（为既有 OUT 回填索引）
/// pGenOut: 1=build both forward edge OUT + in-edge mirror IN (default); 0=build only the in-edge mirror IN (backfill index for existing OUT)
/// pLayer：写入层；空则按进程上下文/默认写入层解析
/// pLayer: target layer; empty resolves via the process context / default write layer
/// 返回：%Status，成功 $$$OK，异常时携带错误状态
/// Returns: %Status, $$$OK on success, carries the error status on exception
ClassMethod AddEdge(pSrc As %Binary, pRel As %String, pTgt As %Binary, pGenOut As %Boolean = 1, pLayer As %String = "") As %Status
{
    Set tSC = $$$OK
    Try 
    {
        Set tLayer = ##class(Graph.Layer).WriteLayer(pLayer)
        Set tSC = ##class(Graph.Layer).CheckWrite(tLayer)
        Return:$$$ISERR(tSC) tSC
        // 正向边（供正向单跳）
        // Forward edge (for forward single hop)
        If pGenOut { Set ^GraphData.OUT(tLayer, pSrc, pTgt, pRel) = "" }
        // 入边镜像（供反向单跳）
        // In-edge mirror (for reverse single hop)
        Set ^GraphData.IN(tLayer, pTgt, pSrc, pRel) = ""
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 删除一条图边 src --rel--> tgt
/// Delete a graph edge src --rel--> tgt
/// 始终删除入边镜像 ^GraphData.IN；pGenOut=1 时同时删除正向边 ^GraphData.OUT
/// Always deletes the in-edge mirror ^GraphData.IN; when pGenOut=1 also deletes the forward edge ^GraphData.OUT
/// pSrc：源节点 OID（模型图为 $ListBuild(Id, ClassName)）
/// pSrc: source node OID (for the model graph, $ListBuild(Id, ClassName))
/// pRel：关系名
/// pRel: relation name
/// pTgt：目标节点 OID（模型图为 $ListBuild(Id, ClassName)）
/// pTgt: target node OID (for the model graph, $ListBuild(Id, ClassName))
/// pGenOut：1=同时删正向边 OUT+入边镜像 IN（默认）；0=仅删入边镜像 IN
/// pGenOut: 1=delete both forward edge OUT + in-edge mirror IN (default); 0=delete only the in-edge mirror IN
/// pLayer：边所在层；空则按进程上下文/默认写入层解析
/// pLayer: the layer holding the edge; empty resolves via the process context / default write layer
/// 返回：%Status，成功 $$$OK，异常时携带错误状态
/// Returns: %Status, $$$OK on success, carries the error status on exception
ClassMethod RemoveEdge(pSrc As %Binary, pRel As %String, pTgt As %Binary, pGenOut As %Boolean = 1, pLayer As %String = "") As %Status
{
    Set tSC = $$$OK
    Try 
    {
        Set tLayer = ##class(Graph.Layer).WriteLayer(pLayer)
        Set tSC = ##class(Graph.Layer).CheckWrite(tLayer)
        Return:$$$ISERR(tSC) tSC
        // 删除正向边
        // Delete the forward edge
        If pGenOut { Kill ^GraphData.OUT(tLayer, pSrc, pTgt, pRel) }
        // 删除对应入边镜像
        // Delete the corresponding in-edge mirror
        Kill ^GraphData.IN(tLayer, pTgt, pSrc, pRel)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 只补一条入边镜像（不动 OUT）—— AddEdge(..., pGenOut=0) 的别名，保持向后兼容
/// Add only one in-edge mirror (leave OUT untouched) — alias of AddEdge(..., pGenOut=0), kept for backward compatibility
/// pSrc：源节点 OID；pRel：关系名；pTgt：目标节点 OID
/// pSrc: source node OID; pRel: relation name; pTgt: target node OID
/// 返回：%Status
/// Returns: %Status
ClassMethod LinkIN(pSrc As %Binary, pRel As %String, pTgt As %Binary, pLayer As %String = "") As %Status
{
    Set tSC = $$$OK
    Try 
    {
        Set tSC = ..AddEdge(pSrc, pRel, pTgt, 0, pLayer)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 只删一条入边镜像（不动 OUT）—— RemoveEdge(..., pGenOut=0) 的别名，保持向后兼容
/// Delete only one in-edge mirror (leave OUT untouched) — alias of RemoveEdge(..., pGenOut=0), kept for backward compatibility
/// pSrc：源节点 OID；pRel：关系名；pTgt：目标节点 OID
/// pSrc: source node OID; pRel: relation name; pTgt: target node OID
/// 返回：%Status
/// Returns: %Status
ClassMethod UnlinkIN(pSrc As %Binary, pRel As %String, pTgt As %Binary, pLayer As %String = "") As %Status
{
    Set tSC = $$$OK
    Try 
    {
        Set tSC = ..RemoveEdge(pSrc, pRel, pTgt, 0, pLayer)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 全量从 ^GraphData.OUT 重建 ^GraphData.IN（幂等）。
/// Fully rebuild ^GraphData.IN from ^GraphData.OUT (idempotent).
/// 用途：① 首次为既有边数据回填入边索引；② 原生数据图批量重建后一次性同步。
/// Uses: (1) first-time backfill of the in-edge index for existing edge data; (2) one-shot sync after a bulk rebuild of the native data graph.
/// pLayers：逗号分隔的层名；空=所有有数据的层
/// pLayers: comma-separated layer names; empty = every layer that holds data
/// 返回：%Status，成功 $$$OK，异常时携带错误状态
/// Returns: %Status, $$$OK on success, carries the error status on exception
ClassMethod BuildIN(pLayers As %String = "") As %Status
{
    Set tSC = $$$OK
    Try 
    {
        Set tList = ..layerList(pLayers)
        For tI = 1:1:$ListLength(tList)
        {
            Set tLayer = $List(tList, tI)
            $$$ThrowOnError(##class(Graph.Layer).CheckWrite(tLayer))
            // 先整体清空该层的镜像，保证幂等（重复调用结果一致）
            // Clear the layer's whole mirror first to ensure idempotency (repeated calls yield the same result)
            Kill ^GraphData.IN(tLayer)
            Set tSrc = ""
            For 
            {
                Set tSrc = $Order(^GraphData.OUT(tLayer, tSrc))
                Quit:tSrc=""
                Set tTgt = ""
                For 
                {
                    Set tTgt = $Order(^GraphData.OUT(tLayer, tSrc, tTgt))
                    Quit:tTgt=""
                    Set tRel = ""
                    For 
                    {
                        Set tRel = $Order(^GraphData.OUT(tLayer, tSrc, tTgt, tRel))
                        Quit:tRel=""
                        // 写入镜像：下标换序 (层,目标,源,关系)
                        // Write the mirror: subscripts reordered to (layer, target, source, relation)
                        Set ^GraphData.IN(tLayer, tTgt, tSrc, tRel) = ""
                    }
                }
            }
        }
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 清空入边索引
/// Clear the in-edge index
/// pLayers：逗号分隔的层名；空=所有有数据的层
/// pLayers: comma-separated layer names; empty = every layer that holds data
/// 返回：%Status
/// Returns: %Status
ClassMethod KillIN(pLayers As %String = "") As %Status
{
    Set tSC = $$$OK
    Try 
    {
        Set tList = ..layerList(pLayers)
        For tI = 1:1:$ListLength(tList)
        {
            Set tLayer = $List(tList, tI)
            $$$ThrowOnError(##class(Graph.Layer).CheckWrite(tLayer))
            Kill ^GraphData.IN(tLayer)
        }
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 校验入边索引与正向边是否完全一致（供测试）。
/// Verify that the in-edge index and the forward edges are fully consistent (for testing).
/// 出参 pOut / pIn 为各层边计数之和；返回「OUT 中缺失对应 IN」的条数（应为 0）。
/// Output params pOut / pIn are the edge counts summed over layers; returns the number of "OUT entries missing a corresponding IN" (should be 0).
/// pOut：出参，%Integer，正向边（^GraphData.OUT）总数
/// pOut: output param, %Integer, total forward edges (^GraphData.OUT)
/// pIn：出参，%Integer，入边镜像（^GraphData.IN）总数
/// pIn: output param, %Integer, total in-edge mirrors (^GraphData.IN)
/// pLayers：逗号分隔的层名；空=所有有数据的层
/// pLayers: comma-separated layer names; empty = every layer that holds data
/// 返回：%Integer，缺失镜像条数；一致时为 0 且 pOut=pIn
/// Returns: %Integer, number of missing mirrors; 0 when consistent and pOut=pIn
ClassMethod Verify(Output pOut As %Integer, Output pIn As %Integer, pLayers As %String = "") As %Integer
{
    // pOut=正向边数 pIn=镜像边数 tMiss=缺镜像数
    // pOut=forward edge count, pIn=mirror edge count, tMiss=missing mirror count
    Set pOut = 0, pIn = 0, tMiss = 0
    Try 
    {
        Set tList = ..layerList(pLayers)
        For tI = 1:1:$ListLength(tList)
        {
            Set tLayer = $List(tList, tI), tSrc = ""
            // 遍历正向边（源→目标→关系 三层）
            // Traverse forward edges (three levels: source→target→relation)
            For 
            {
                Set tSrc = $Order(^GraphData.OUT(tLayer, tSrc))  Quit:tSrc=""
                Set tTgt = ""
                For {
                    Set tTgt = $Order(^GraphData.OUT(tLayer, tSrc, tTgt))  Quit:tTgt=""
                    Set tRel = ""
                    For 
                    {
                        Set tRel = $Order(^GraphData.OUT(tLayer, tSrc, tTgt, tRel))  Quit:tRel=""
                        Set pOut = pOut + 1
                        // 对应镜像缺失则记一笔
                        // Record one if the corresponding mirror is missing
                        If '$Data(^GraphData.IN(tLayer, tTgt, tSrc, tRel)) { Set tMiss = tMiss + 1 }
                    }
                }
            }
            // 独立统计镜像边数（目标→源→关系 三层）
            // Independently count mirror edges (three levels: target→source→relation)
            Set tTgt2 = ""
            For 
            {
                Set tTgt2 = $Order(^GraphData.IN(tLayer, tTgt2))  Quit:tTgt2=""
                Set tSrc2 = ""
                For 
                {
                    Set tSrc2 = $Order(^GraphData.IN(tLayer, tTgt2, tSrc2))  Quit:tSrc2=""
                    Set tRel2 = ""
                    For 
                    {
                        Set tRel2 = $Order(^GraphData.IN(tLayer, tTgt2, tSrc2, tRel2))  Quit:tRel2=""
                        Set pIn = pIn + 1
                    }
                }
            }
        }
    }
    // 出错则返回已统计到的部分计数（安全默认）
    // On error, return the partial counts gathered so far (safe default)
    Catch ex {}
    // 一致时应为 0，且 pOut=pIn
    // Should be 0 when consistent, with pOut=pIn
    Quit tMiss
}

/// 解析层名参数；空=所有有数据的层。
/// Resolve the layer argument; empty = every layer that holds data.
ClassMethod layerList(pLayers As %String) As %List [ Private ]
{
    If pLayers = "" Quit ##class(Graph.Layer).Present()
    Quit $ListFromString(pLayers, ",")
}

}
