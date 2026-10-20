Include %occInclude

/// Graph 引擎自检 + 基准（一次性测试类，可删）。
/// Graph engine self-check + benchmark (one-off test class, deletable).
/// 对给定病人的图数据跑各类查询，打印结果规模，并校验最短路径每步边真实存在且连通。
/// Runs various queries over a given patient's graph data, prints result sizes, and verifies each step's edge on the shortest path truly exists and is connected.
/// Author: QP
/// Version: 2.0
/// Last Modified Date: 2026/07/26
Class Graph.Test Extends %RegisteredObject
{

/// 跑一遍各类查询并打印规模；最后校验若干最短路径的正确性
/// Runs each type of query once and prints the sizes; finally validates the correctness of several shortest paths
ClassMethod Run(pPatientId As %String = 1)
{
    Set tSC = $$$OK
    Try 
    {
        Set tPatient = $ListBuild(pPatientId _ "", "Research.Patient")
        Set tCond = $ListBuild(pPatientId _ "", "Research.Condition")
        Set tDrug = $ListBuild(pPatientId _ "", "Research.Drug")

        Do ##class(Graph.Tools).SingleHop(tPatient, "", 0, .tR)
        Write "SingleHop FWD  : ", tR.%Size(), !
        Do ##class(Graph.Tools).SingleHop(tCond, "", 1, .tR)
        Write "SingleHop REV  : ", tR.%Size(), !
        Do ##class(Graph.Tools).SingleHop(tCond, "diagnosed_with", 1, .tR)
        Write "SingleHop REVf : ", tR.%Size(), !
        Do ##class(Graph.Tools).BFS(tPatient, 2, .tR)
        Write "BFS depth2     : ", tR.%Size(), !
        Do ##class(Graph.Tools).BFS(tPatient, 3, .tR)
        Write "BFS depth3     : ", tR.%Size(), !
        Set tRL = [{"Relation":"diagnosed_with","Inverse":0}, {"Relation":"treated_by","Inverse":0}]
        Do ##class(Graph.Tools).MultiHop(tPatient, tRL, .tR)
        Write "MultiHop 2-rel : ", tR.%Size(), !
        Do ##class(Graph.Tools).ShortestPath(tPatient, tDrug, .tR)
        Write "ShortestPath   : ", tR.%Size(), !

        Do ..ChkSP()
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 校验若干最短路径：打印长度，并校验每步边真实存在且相邻步连通
/// Validates several shortest paths: prints the length, and verifies each step's edge truly exists and adjacent steps are connected
ClassMethod ChkSP()
{
    Set tSC = $$$OK
    Try 
    {
        Set tP = $ListBuild("1", "Research.Patient")
        Set tG = $ListBuild("1", "Research.Gene")
        Set tD = $ListBuild("1", "Research.Drug")
        Set tC = $ListBuild("1", "Research.Condition")
        Do ..OneSP("Patient->Gene", tP, tG)
        Do ..OneSP("Gene->Patient", tG, tP)
        Do ..OneSP("Drug->Gene", tD, tG)
        Do ..OneSP("Condition->Gene", tC, tG)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

ClassMethod OneSP(pName As %String, pA, pB)
{
    Try {
        Do ##class(Graph.Tools).ShortestPath(pA, pB, .tR)
        Write pName, " : len=", tR.%Size(), " valid=", ..validPath(tR), !
    }
    Catch ex {}
    Quit
}

/// 校验一条路径：每步边存在于 OUT，且相邻步共享一个节点
/// Validates one path: each step's edge exists in OUT, and adjacent steps share a node
ClassMethod validPath(pRes As %DynamicArray) As %Boolean
{
    Try 
    {
        Set tN = pRes.%Size()
        Return:tN=0 1                                            // 空路径（起点==终点）视为合法 | Empty path (start == end) is treated as valid
        Set tPrevA = "", tPrevB = ""                            // 上一步的两个端点 | The two endpoints of the previous step
        For tI = 0:1:tN - 1 
        {
            Set tE = pRes.%Get(tI)
            Set tA = $ListToString(tE.OID, "/"), tB = $ListToString(tE.TargetOID, "/")
            // 边真实存在（真实方向：OID --Relation--> TargetOID）
            // The edge truly exists (real direction: OID --Relation--> TargetOID)
            If '$Data(^GraphData.OUT(tE.OID, tE.TargetOID, tE.Relation)) Return 0
            // 与上一步共享节点（无向路径：相邻步必有一个公共端点）
            // Shares a node with the previous step (undirected path: adjacent steps must have one common endpoint)
            If tI > 0 
            {
                If (tA '= tPrevA) && (tA '= tPrevB) && (tB '= tPrevA) && (tB '= tPrevB) Return 0
            }
            Set tPrevA = tA, tPrevB = tB                        // 推进上一步端点 | Advance the previous-step endpoints
        }
        Return 1
    }
    Catch ex 
    {
        Return 0
    }
}

/// 各操作基准计时（单引擎）
/// Per-operation benchmark timing (single engine)
ClassMethod Bench(pIters As %Integer = 500, pId As %String = 1)
{
    Set tSC = $$$OK
    Try 
    {
        Set tPatient = $ListBuild(pId _ "", "Research.Patient")
        Set tCond = $ListBuild(pId _ "", "Research.Condition")
        Set tDrug = $ListBuild(pId _ "", "Research.Drug")
        Set tRelRev = [{"Relation":"diagnosed_with","Inverse":1}]

        Do ..One("正向单跳", pIters, "SHF", tPatient, tDrug)
        Do ..One("反向单跳", pIters, "SHR", tCond, tDrug)
        Do ..One("MultiHop 反向步", pIters, "MHR", tCond, tRelRev)
        Do ..One("BFS 深度3", pIters, "BFS", tPatient, tDrug)
        Do ..One("ShortestPath", pIters, "SP", tPatient, tDrug)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 单项计时
/// Single-item timing
ClassMethod One(pName As %String, pIters As %Integer, pKind As %String, pA, pB)
{
    Try 
    {
        Set tT0 = $ZHorolog
        For tI = 1:1:pIters { Do ..Exec(pKind, pA, pB, .tR) }
        Set tT = $ZHorolog - tT0
        Write pName, " x", pIters, " : ", $FNumber(tT * 1000, "", 1), " ms", !
    }
    Catch ex {}
    Quit
}

/// 按种类分派一次调用
/// Dispatches one call by kind
ClassMethod Exec(pKind As %String, pA, pB, Output pRes)
{
    Try 
    {
        If pKind = "SHF" { Do ##class(Graph.Tools).SingleHop(pA, "", 0, .pRes) }        // 正向单跳 | Forward single hop
        ElseIf pKind = "SHR" { Do ##class(Graph.Tools).SingleHop(pA, "", 1, .pRes) }    // 反向单跳 | Reverse single hop
        ElseIf pKind = "MHR" { Do ##class(Graph.Tools).MultiHop(pA, pB, .pRes) }         // 含反向步多跳 | Multi-hop containing a reverse step
        ElseIf pKind = "BFS" { Do ##class(Graph.Tools).BFS(pA, 3, .pRes) }               // BFS 深度 3 | BFS depth 3
        ElseIf pKind = "SP" { Do ##class(Graph.Tools).ShortestPath(pA, pB, .pRes) }      // 最短路径 | Shortest path
    }
    Catch ex {}
    Quit
}

/// 并行 BFS 基准：临时构造一个高扇出 hub 图，对比串行 BFS 与 BFSParallel（多档 worker）。
/// Parallel BFS benchmark: temporarily builds a high-fanout hub graph, comparing serial BFS with BFSParallel (multiple worker levels).
/// 每档跑 pReps 次取 min/avg（并预热一次消除冷启动），校验各档边数与串行一致，
/// Each level runs pReps times taking min/avg (and warms up once to eliminate cold start), verifying each level's edge count matches the serial one,
/// 最后清理临时图（仅删本方法建的 Perf.Node 键）与 ^IRIS.Temp.GraphBFS。
/// Finally cleans up the temporary graph (deletes only the Perf.Node keys built by this method) and ^IRIS.Temp.GraphBFS.
/// 说明：这是一次性压测入口（会临时写入 ^GraphData.OUT/IN 的 Perf.Node 子图，跑完即清）。
/// Note: this is a one-off stress-test entry point (temporarily writes the Perf.Node subgraph of ^GraphData.OUT/IN, cleared right after running).
/// pNodes：随机目标空间大小；pHubFanout：hub 出度（=level-1 前沿规模）；
/// pNodes: size of the random target space; pHubFanout: hub out-degree (= level-1 frontier size);
/// pChildFanout：每个 level-1 节点的出度；pDepth：BFS 深度；pReps：每档重复次数。
/// pChildFanout: out-degree of each level-1 node; pDepth: BFS depth; pReps: number of repeats per level.
ClassMethod BenchParallel(pNodes As %Integer = 200000, pHubFanout As %Integer = 50000, pChildFanout As %Integer = 40, pDepth As %Integer = 2, pReps As %Integer = 5)
{
    Set tSC = $$$OK, tCls = "Perf.Node"
    Try 
    {
        // ---- 构造 hub 图：节点 1 连 pHubFanout 个孩子；每个孩子再随机连 pChildFanout 条 ----
        // ---- Build hub graph: node 1 connects pHubFanout children; each child randomly connects pChildFanout more ----
        Set tT0 = $ZHorolog
        For tT = 2:1:pHubFanout + 1 
        {
            Set ^GraphData.OUT($ListBuild(1, tCls), $ListBuild(tT, tCls), "e") = ""
            Set ^GraphData.IN($ListBuild(tT, tCls), $ListBuild(1, tCls), "e") = ""
        }
        For tI = 2:1:pHubFanout + 1 
        {
            Set tS = $ListBuild(tI, tCls)
            For tJ = 1:1:pChildFanout 
            {
                Set tD = $ListBuild($Random(pNodes) + 1, tCls)
                Set ^GraphData.OUT(tS, tD, "e") = "", ^GraphData.IN(tD, tS, "e") = ""
            }
        }
        Set tStart = $ListBuild(1, tCls)
        Write "=== build hub graph: hub-fanout=", pHubFanout, "  child-fanout=", pChildFanout, "  time=", $FNumber($ZHorolog - tT0, "", 2), "s ===", !
        Write "DefaultNumWorkers=", $SYSTEM.WorkMgr.DefaultNumWorkers(), "   depth=", pDepth, "   reps=", pReps, !

        // ---- 预热（消除冷启动）----
        // ---- Warmup (eliminate cold start) ----
        Do ##class(Graph.Tools).BFS(tStart, pDepth, .tW1)
        Set tSC = ##class(Graph.Tools).BFSParallel(tStart, pDepth, .tW2, 0)
        Write "warmup done (serial=", tW1.%Size(), "  parallel=", tW2.%Size(), ")", !

        // ---- 串行基准：min/avg ----
        // ---- Serial benchmark: min/avg ----
        Set tBest = 999999, tSum = 0, tSize = 0
        For tR = 1:1:pReps 
        {
            Set tT1 = $ZHorolog
            Do ##class(Graph.Tools).BFS(tStart, pDepth, .tA)
            Set tD = $ZHorolog - tT1
            Set:tD<tBest tBest = tD
            Set tSum = tSum + tD, tSize = tA.%Size()
        }
        Set tSzSerial = tSize, tBestSerial = tBest
        Write "serial      min=", $FNumber(tBest, "", 3), " avg=", $FNumber(tSum / pReps, "", 3), " edges=", tSize, !

        // ---- 并行基准：多档 worker × 方向优化开/关，各取 min/avg，并校验边数一致 ----
        // ---- Parallel benchmark: multiple worker levels x direction optimization on/off, each taking min/avg, and verifying edge counts match ----
        //      tOpt=0 纯 top-down（原行为）；tOpt=1 方向优化（前沿大时切 bottom-up）
        //      tOpt=0 pure top-down (original behavior); tOpt=1 direction optimization (switch to bottom-up when frontier is large)
        For tW = 0, 4, 8, 10, 20 
        {
            For tOpt = 0, 1 
            {
                Set tBest = 999999, tSum = 0, tSize = 0
                For tR = 1:1:pReps 
                {
                    Set tT1 = $ZHorolog
                    Set tSC = ##class(Graph.Tools).BFSParallel(tStart, pDepth, .tA, tW, tOpt)
                    Set tD = $ZHorolog - tT1
                    Set:tD<tBest tBest = tD
                    Set tSum = tSum + tD, tSize = tA.%Size()
                }
                Set tTag = $Select(tOpt=1: "diropt", 1: "topdwn")
                Set tLbl = $Extract("par W=" _ tW _ " " _ tTag _ "         ", 1, 18)
                Write tLbl, "min=", $FNumber(tBest, "", 3), " avg=", $FNumber(tSum / pReps, "", 3), " edges=", tSize, " speedup=", $FNumber(tBestSerial / tBest, "", 2), "x match=", (tSize = tSzSerial), !
            }
        }
    }
    Catch ex { Set tSC = ex.AsStatus() }

    // ---- 清理：仅删本方法建的 Perf.Node 子图 + 并行临时空间 ----
    // ---- Cleanup: delete only the Perf.Node subgraph built by this method + parallel temp space ----
    Set tK = ""
    For { Set tK = $Order(^GraphData.OUT(tK)) Quit:tK=""  If $ListValid(tK), $ListGet(tK, 2) = tCls Kill ^GraphData.OUT(tK) }
    Set tK = ""
    For { Set tK = $Order(^GraphData.IN(tK)) Quit:tK=""  If $ListValid(tK), $ListGet(tK, 2) = tCls Kill ^GraphData.IN(tK) }
    Kill ^IRIS.Temp.GraphBFS
    Quit tSC
}

}
