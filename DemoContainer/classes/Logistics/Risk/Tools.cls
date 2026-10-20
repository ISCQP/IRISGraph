/// 风险影响分析通用工具 · 空间(图遍历) + 时间(时间窗重叠) 双重判定。
/// Generic risk impact analysis utility · dual decision of space (graph traversal) + time (time-window overlap).
/// 
/// 适用于各类风险事件（台风、地缘冲突、港口封锁等）：只要风险通过
/// Applicable to all kinds of risk events (typhoon, geopolitical conflict, port blockade, etc.): as long as the risk is
///   risk_at_location 关联到地理区域（Location），即可沿
///   linked to a geographic region (Location) via risk_at_location, one can traverse along
///   区域 <-passes_through- 航段 <-route_contains_segment- 航路 <-uses- 航次 <-assigned_to- 船
///   region <-passes_through- segment <-route_contains_segment- route <-uses- voyage <-assigned_to- vessel
/// 反向图遍历，得出航路空间上经过风险区域的候选船；再按风险的 StartTime/EndTime
/// reverse graph traversal to obtain candidate vessels whose routes spatially pass through the risk region; then, using the risk's StartTime/EndTime
/// 时间窗与「船经过该航段的时间窗」做重叠判定。
/// time window, an overlap check is performed against "the vessel's time window for passing that segment".
/// 
/// 若风险未设置 StartTime/EndTime（持续性/无明确时段的风险），则空间命中即视为受影响。
/// If the risk has no StartTime/EndTime (a persistent risk with no defined period), a spatial hit alone is considered affected.
/// Author: QP
/// Version: 1.0
Class Logistics.Risk.Tools Extends %RegisteredObject
{

/// 打开 OID = $LB(Id, ClassName) 对应的对象
/// Open the object corresponding to OID = $LB(Id, ClassName)
ClassMethod openOID(pOID As %List)
{
    Quit:pOID="" ""
    Quit $ClassMethod($ListGet(pOID, 2), "%OpenId", $ListGet(pOID, 1))
}

/// %TimeStamp -> 绝对秒（用于时间窗重叠比较）
/// %TimeStamp -> absolute seconds (used for time-window overlap comparison)
ClassMethod tsToSec(pTS As %String) As %Integer
{
    Quit:pTS="" ""
    Set tH = $ZDateTimeH(pTS, 3)
    Quit ($Piece(tH, ",", 1) * 86400) + (+$Piece(tH, ",", 2))
}

/// 绝对秒 -> 可读 %TimeStamp（仅用于打印）
/// Absolute seconds -> readable %TimeStamp (for printing only)
ClassMethod secToTs(pSec As %Integer) As %String
{
    Quit:pSec="" ""
    Quit $ZDateTime((pSec \ 86400) _ "," _ (pSec # 86400), 3)
}

/// 两个闭区间 [a1,a2] 与 [b1,b2] 是否重叠
/// Whether the two closed intervals [a1,a2] and [b1,b2] overlap
ClassMethod overlap(pA1, pA2, pB1, pB2) As %Boolean
{
    Quit (pA1 <= pB2) && (pA2 >= pB1)
}

/// 把节点 OID 渲染成可读标签
/// Render a node OID into a readable label
ClassMethod Label(pOID As %List) As %String
{
    Set tId = $ListGet(pOID, 1), tCls = $ListGet(pOID, 2), tShort = $Piece(tCls, ".", *)
    Set tKey = ""
    Try 
    {
        Set tObj = $ClassMethod(tCls, "%OpenId", tId)
        If $IsObject(tObj) 
        {
            If tShort = "RiskEvent" { Set tKey = tObj.Name_" ["_tObj.Type_"]" }
            ElseIf tShort = "RouteSegment" { Set tKey = tObj.Name }
            ElseIf tShort = "Route" { Set tKey = tObj.RouteName }
            ElseIf tShort = "Voyage" { Set tKey = tObj.VoyageNo }
            ElseIf tShort = "Vessel" { Set tKey = tObj.Name_"("_tObj.IMO_")" }
            ElseIf tShort = "Location" { Set tKey = tObj.Name_"/"_tObj.Type }
        }
    } 
    Catch { Set tKey = "" }
    Quit tShort_"#"_tId_$Select(tKey="":"", 1:" ("_tKey_")")
}

/// 计算某航次经过某航段的时间窗（绝对秒）：ETD + 该航段之前所有航段的累计时长
/// Compute the time window (absolute seconds) of a voyage passing a segment: ETD + cumulative duration of all segments before that segment
/// 返回 $LB(起秒, 止秒)；ETD 缺失时返回 ""
/// Return $LB(startSec, endSec); return "" when ETD is missing
ClassMethod segWindow(pVoyageOID As %List, pSegOID As %List) As %List
{
    Set tVoy = ..openOID(pVoyageOID)
    Set tSeg = ..openOID(pSegOID)
    Quit:'$IsObject(tVoy)||'$IsObject(tSeg) ""
    Set tEtd = ..tsToSec(tVoy.ETD)
    Quit:tEtd="" ""
    Set tRoute = tVoy.Route
    Quit:'$IsObject(tRoute) ""
    Set tOffsetH = 0
    For tI = 1:1:tRoute.Segments.Count() 
    {
        Set tS = tRoute.Segments.GetAt(tI)
        If (+tS.Sequence) < (+tSeg.Sequence) { Set tOffsetH = tOffsetH + tS.ExpectedDuration }
    }
    Set tStart = tEtd + (tOffsetH * 3600)
    Set tEnd = tStart + (tSeg.ExpectedDuration * 3600)
    Quit $ListBuild(tStart, tEnd)
}

/// 通用风险影响分析：结合空间(图) + 时间，得出受影响船舶。
/// Generic risk impact analysis: combine space (graph) + time to determine affected vessels.
///   pRiskOID          风险事件 OID = $LB(Id, ClassName)
///   pRiskOID          risk event OID = $LB(Id, ClassName)
///   pSpatial(船OID)   = 命中航段 OID              —— 航路空间上经过风险区域的船
///   pSpatial(vesselOID)  = hit segment OID              —— vessels whose route spatially passes through the risk region
///   pAffected(船OID)  = $LB(命中航段OID, 窗起秒, 窗止秒) —— 且经过时间与风险时间窗重叠（真正受影响）
///   pAffected(vesselOID) = $LB(hitSegmentOID, windowStartSec, windowEndSec) —— and whose passing time overlaps the risk time window (truly affected)
/// 风险无 StartTime/EndTime 时，空间命中即受影响（窗起止秒为空）。
/// When the risk has no StartTime/EndTime, a spatial hit alone is affected (window start/end seconds are empty).
ClassMethod AnalyzeRisk(pRiskOID As %List, ByRef pSpatial, ByRef pAffected) As %Status
{
    Kill pSpatial, pAffected
    Quit:pRiskOID="" $$$OK
    Set tRiskObj = ..openOID(pRiskOID)
    Quit:'$IsObject(tRiskObj) $$$OK
    Set tHasTime = (tRiskObj.StartTime '= "") && (tRiskObj.EndTime '= "")
    Set tS = ..tsToSec(tRiskObj.StartTime), tE = ..tsToSec(tRiskObj.EndTime)

    // 风险覆盖区域：Risk -risk_at_location-> Region（可能多个）
    // Risk coverage region: Risk -risk_at_location-> Region (possibly multiple)
    Do ##class(Graph.Tools).SingleHop(pRiskOID, "risk_at_location", 0, .tRegRes)
    For tR = 1:1:tRegRes.%Size() 
    {
        Set tRegion = tRegRes.%Get(tR - 1).TargetOID
        // [空间] 区域 <-passes_through- 航段（反向入边）
        // [space] region <-passes_through- segment (reverse in-edge)
        Do ##class(Graph.Tools).SingleHop(tRegion, "passes_through", 1, .tSegRes)
        For tI = 1:1:tSegRes.%Size() 
        {
            Set tSegOID = tSegRes.%Get(tI - 1).OID
            // 航段 <-route_contains_segment- 航路
            // segment <-route_contains_segment- route
            Do ##class(Graph.Tools).SingleHop(tSegOID, "route_contains_segment", 1, .tRtRes)
            For tJ = 1:1:tRtRes.%Size() 
            {
                Set tRtOID = tRtRes.%Get(tJ - 1).OID
                // 航路 <-uses- 航次
                // route <-uses- voyage
                Do ##class(Graph.Tools).SingleHop(tRtOID, "uses", 1, .tVoyRes)
                For tK = 1:1:tVoyRes.%Size() 
                {
                    Set tVoyOID = tVoyRes.%Get(tK - 1).OID
                    // 航次 <-assigned_to- 船
                    // voyage <-assigned_to- vessel
                    Do ##class(Graph.Tools).SingleHop(tVoyOID, "assigned_to", 1, .tVesRes)
                    Continue:tVesRes.%Size()=0
                    Set tVesOID = tVesRes.%Get(0).OID
                    Set pSpatial(tVesOID) = tSegOID
                    Set tWin = ..segWindow(tVoyOID, tSegOID)
                    If 'tHasTime 
                    {
                        // 无时间窗约束：空间命中即受影响
                        // no time-window constraint: a spatial hit alone is affected
                        Set pAffected(tVesOID) = $ListBuild(tSegOID, $Select(tWin="":"", 1:$List(tWin, 1)), $Select(tWin="":"", 1:$List(tWin, 2)))
                        Continue
                    }
                    Continue:tWin=""
                    Set tWs = $List(tWin, 1), tWe = $List(tWin, 2)
                    If ..overlap(tWs, tWe, tS, tE) 
                    {
                        Set pAffected(tVesOID) = $ListBuild(tSegOID, tWs, tWe)
                    }
                }
            }
        }
    }
    Quit $$$OK
}

}
