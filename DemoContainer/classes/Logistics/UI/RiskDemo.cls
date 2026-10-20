Include %occInclude

/// 基于图谱的供应链风险识别与建议 · CSP 演示页
/// Graph-based supply chain risk identification and recommendations · CSP demo page
/// 
/// 访问：/csp/healthshare/nehr/Logistics.UI.RiskDemo.cls
/// Access: /csp/healthshare/nehr/Logistics.UI.RiskDemo.cls
///       ?action=setup 重建演示场景数据
///       ?action=setup rebuilds the demo scenario data
/// 
/// 页面内容：
/// Page contents:
///   1) 风险告警（RiskEvent）
///   1) Risk alert (RiskEvent)
///   2) KPI（受影响的航段/货运/采购单/供应商数量）
///   2) KPI (counts of affected segments/shipments/purchase orders/suppliers)
///   3) 影响传播链（Risk → Impact → 货运/采购单/供应商 ；及物理途经航段的货运）
///   3) Impact propagation chain (Risk → Impact → shipment/purchase order/supplier; and shipments physically transiting the segment)
///   4) 图追踪交互视图（vis-network，展示从风险出发的 BFS 影响子图）
///   4) Interactive graph tracing view (vis-network, showing the BFS impact subgraph starting from the risk)
///   5) AI 建议（基于图追踪结果的规则化推荐）
///   5) AI recommendations (rule-based suggestions from the graph tracing result)
/// 
/// 数据由 Logistics.Test.PersianGulfDemo.Setup() 构造，图边由 Graph.Object.Index 功能索引自动维护，
/// Data is built by Logistics.Test.PersianGulfDemo.Setup(); graph edges are automatically maintained by the Graph.Object.Index functional index,
/// 追踪查询统一走 Graph.Tools（SingleHop / MultiHop / BFS）。
/// tracing queries all go through Graph.Tools (SingleHop / MultiHop / BFS).
/// Author: QP
/// Version: 1.0
Class Logistics.UI.RiskDemo Extends %CSP.Page
{

Parameter CONTENTTYPE = "text/html";

Parameter CHARSET = "UTF-8";

/// 页面入口
/// Page entry point
ClassMethod OnPage() As %Status
{
    // 动作路由：触发风险 / 重置 / 全量重建 / 首次访问确保基线
    // Action routing: trigger risk / reset / full rebuild / ensure baseline on first visit
    Set tAction = %request.Get("action")
    If tAction = "setup" { Do ##class(Logistics.Test.PersianGulfDemo).Setup() }
    ElseIf tAction = "trigger" { Do ##class(Logistics.Test.PersianGulfDemo).TriggerHormuzRisk() }
    ElseIf tAction = "clear" {
        If $Get(^LogiDemo("key", "segment")) = "" { Do ##class(Logistics.Test.PersianGulfDemo).SetupBaseline() }
        Else { Do ##class(Logistics.Test.PersianGulfDemo).ClearRisk() }
    }
    ElseIf $Get(^LogiDemo("key", "segment")) = "" { Do ##class(Logistics.Test.PersianGulfDemo).SetupBaseline() }

    Set tRisk = $Get(^LogiDemo("key", "risk"))
    Set tSeg = $Get(^LogiDemo("key", "segment"))

    // 无活动风险 -> 平静状态 + 触发按钮
    // No active risk -> calm state + trigger button
    If tRisk = "" {
        Write "<!DOCTYPE html>", !
        Write "<html lang='zh-CN'><head><meta charset='UTF-8'>", !
        Write "<meta name='viewport' content='width=device-width, initial-scale=1.0'>", !
        Write "<title>基于图谱的供应链风险识别与建议</title>", !
        Write "<style>", ..CSS(), "</style></head><body>", !
        Write "<header class='topbar'>"
        Write "<div class='brand'>&#127760; GraphRisk &#183; <span data-i18n='brandName'></span></div>"
        Write "<div class='sub' data-i18n='brandSub'></div>"
        Write "<button type='button' id='langtoggle' class='rebuild'>&#127760; <span data-i18n='langBtn'></span></button>"
        Write "<a class='trigger' href='?action=trigger'>&#9889; <span data-i18n='triggerCalm'></span></a>"
        Write "<a class='rebuild' href='?action=clear'>&#8635; <span data-i18n='reset'></span></a>"
        Write "</header>", !
        Write "<section class='alert calm'><div class='alert-icon'>&#9989;</div><div class='alert-body'>"
        Write "<div class='alert-title' data-i18n='calmTitle'></div>"
        Write "<div class='alert-meta' data-i18n='calmMeta'></div>"
        Write "</div></section>"
        Write "<section class='card' style='text-align:center;padding:44px 24px'>"
        Write "<a class='bigbtn' href='?action=trigger'>&#9889; <span data-i18n='bigbtn'></span></a>"
        Write "</section>"
        Do ..I18NScript()
        Write "</body></html>", !
        Quit $$$OK
    }

    // 风险详情
    // Risk details
    Set tRName = "", tRType = "", tRSev = "", tRForecast = "", tRLoc = ""
    Set tRObj = ##class(Logistics.Risk.RiskEvent).%OpenId($ListGet(tRisk, 1))
    If $IsObject(tRObj) {
        Set tRName = tRObj.Name, tRType = tRObj.Type, tRSev = tRObj.Severity, tRForecast = tRObj.Forecast
        Set:$IsObject(tRObj.Location) tRLoc = tRObj.Location.Name
    }

    // 图追踪
    // Graph tracing
    Do ##class(Graph.Tools).SingleHop(tRisk, "affects_segment", 0, .tR)  Do ..hopLabels(.tR, 0, .tSegs)
    Do ##class(Graph.Tools).SingleHop(tRisk, "causes", 0, .tR)           Do ..hopLabels(.tR, 0, .tImpacts)
    Do ##class(Graph.Tools).MultiHop(tRisk, [{"Relation":"causes","Inverse":0},{"Relation":"impact_affects_shipment","Inverse":0}], .tR)  Do ..hopLabels(.tR, 0, .tShips)
    Do ##class(Graph.Tools).MultiHop(tRisk, [{"Relation":"causes","Inverse":0},{"Relation":"impact_affects_po","Inverse":0}], .tR)        Do ..hopLabels(.tR, 0, .tPOs)
    Do ##class(Graph.Tools).MultiHop(tRisk, [{"Relation":"causes","Inverse":0},{"Relation":"impact_affects_supplier","Inverse":0}], .tR)  Do ..hopLabels(.tR, 0, .tSups)
    Do ##class(Graph.Tools).MultiHop(tSeg, [{"Relation":"route_contains_segment","Inverse":1},{"Relation":"uses","Inverse":1},{"Relation":"assigned_to","Inverse":1},{"Relation":"loaded_on","Inverse":1},{"Relation":"contains","Inverse":1}], .tR)  Do ..hopLabels(.tR, 1, .tTransit)

    // BFS 子图 → vis-network 数据
    // BFS subgraph → vis-network data
    Set tGraphJSON = ..GraphJSON(tRisk)

    // ---------- 渲染（全部用 Write，HTML 属性用单引号）----------
    // ---------- Render (all via Write, HTML attributes use single quotes) ----------
    Write "<!DOCTYPE html>", !
    Write "<html lang='zh-CN'><head><meta charset='UTF-8'>", !
    Write "<meta name='viewport' content='width=device-width, initial-scale=1.0'>", !
    Write "<title>基于图谱的供应链风险识别与建议</title>", !
    Do ##class(Graph.UI.Network).Head()
    Write "<style>", ..CSS(), ##class(Graph.UI.Network).CSS(), "</style>", !
    Write "</head><body>", !

    Write "<header class='topbar'>"
    Write "<div class='brand'>&#127760; GraphRisk &#183; <span data-i18n='brandName'></span></div>"
    Write "<div class='sub' data-i18n='brandSub'></div>"
    Write "<button type='button' id='langtoggle' class='rebuild'>&#127760; <span data-i18n='langBtn'></span></button>"
    Write "<a class='trigger' href='?action=trigger'>&#9889; <span data-i18n='triggerAgain'></span></a>"
    Write "<a class='rebuild' href='?action=clear'>&#8635; <span data-i18n='reset'></span></a>"
    Write "</header>", !

    // 风险告警条
    // Risk alert bar
    Write "<section class='alert'><div class='alert-icon'>&#9888;</div><div class='alert-body'>"
    Write "<div class='alert-title'><span data-i18n='alertDetected'></span>", ..esc(tRName), " <span class='badge'>", ..esc(tRType), "</span></div>"
    Write "<div class='alert-meta'><span data-i18n='severity'></span> <b>", ..esc(tRSev), "/10</b> &#183; <span data-i18n='location'></span> <b>", ..esc(tRLoc), "</b> &#183; ", ..esc(tRForecast), "</div>"
    Write "</div></section>", !

    // KPI
    Write "<section class='kpis'>"
    Do ..kpi("kpiSeg", $ListLength(tSegs), "&#129517;")
    Do ..kpi("kpiShip", $ListLength(tShips), "&#128674;")
    Do ..kpi("kpiPo", $ListLength(tPOs), "&#128196;")
    Do ..kpi("kpiSup", $ListLength(tSups), "&#127981;")
    Write "</section>", !

    // 影响传播链
    // Impact propagation chain
    Write "<section class='card'><h2 data-i18n='chainTitle'></h2>"
    Write "<p class='hint'><span data-i18n='chainHintA'></span> <code>causes &#8594; impact_affects_*</code> <span data-i18n='chainHintB'></span></p>"
    Write "<div class='chain'>"
    Write "<span class='chip risk'>&#9888; ", ..esc(tRName), "</span>"
    Write "<span class='arrow'>causes &#9654;</span>"
    Write "<div class='chip-col'>"
    If $ListLength(tImpacts) = 0 { Write "<span class='chip muted' data-i18n='noImpact'></span>" }
    For i = 1:1:$ListLength(tImpacts) { Write "<span class='chip impact'>&#9201; ", ..esc($List(tImpacts, i)), "</span>" }
    Write "</div>"
    Write "<span class='arrow'>affects &#9654;</span>"
    Write "<div class='chip-col'>"
    For i = 1:1:$ListLength(tShips) { Write "<span class='chip biz'>&#128674; ", ..esc($List(tShips, i)), "</span>" }
    For i = 1:1:$ListLength(tPOs) { Write "<span class='chip biz'>&#128196; ", ..esc($List(tPOs, i)), "</span>" }
    For i = 1:1:$ListLength(tSups) { Write "<span class='chip biz'>&#127981; ", ..esc($List(tSups, i)), "</span>" }
    Write "</div></div>"

    Write "<h3><span data-i18n='transitTitle'></span> <span class='hint' data-i18n='transitHint'></span></h3>"
    Write "<div class='chain'>"
    Write "<span class='chip seg'>&#129517; ", ..esc($ListGet(tSegs, 1, "segment")), "</span>"
    Write "<span class='arrow'>transits &#9654;</span>"
    Write "<div class='chip-col'>"
    If $ListLength(tTransit) = 0 { Write "<span class='chip muted' data-i18n='none2'></span>" }
    For i = 1:1:$ListLength(tTransit) { Write "<span class='chip biz'>&#128674; ", ..esc($List(tTransit, i)), "</span>" }
    Write "</div></div></section>", !

    // 图 + 建议（两栏）
    // Graph + recommendations (two columns)
    Write "<section class='grid2'>"
    Write "<div class='card'><h2><span data-i18n='graphTitle'></span> <span class='hint'>(BFS from Risk)</span></h2>"
    // 子图由标准组件 Graph.UI.Network 渲染
    // The subgraph is rendered by the standard component Graph.UI.Network
    Set gopt("groups") = "{""RiskEvent"":{""color"":{""background"":""#ef4444"",""border"":""#b91c1c""},""font"":{""color"":""#fff""}},""RouteImpact"":{""color"":{""background"":""#f97316"",""border"":""#c2410c""}},""Impact"":{""color"":{""background"":""#fb923c"",""border"":""#ea580c""},""font"":{""color"":""#fff""}},""Shipment"":{""color"":{""background"":""#3b82f6"",""border"":""#1d4ed8""},""font"":{""color"":""#fff""}},""Container"":{""color"":{""background"":""#60a5fa"",""border"":""#2563eb""}},""PurchaseOrder"":{""color"":{""background"":""#6366f1"",""border"":""#4338ca""},""font"":{""color"":""#fff""}},""Product"":{""color"":{""background"":""#818cf8"",""border"":""#4f46e5""}},""Supplier"":{""color"":{""background"":""#0ea5e9"",""border"":""#0369a1""},""font"":{""color"":""#fff""}},""HSCode"":{""color"":{""background"":""#38bdf8"",""border"":""#0284c7""}},""Route"":{""color"":{""background"":""#14b8a6"",""border"":""#0f766e""},""font"":{""color"":""#fff""}},""RouteSegment"":{""color"":{""background"":""#2dd4bf"",""border"":""#0d9488""}},""Voyage"":{""color"":{""background"":""#5eead4"",""border"":""#14b8a6""}},""Vessel"":{""color"":{""background"":""#a78bfa"",""border"":""#7c3aed""},""font"":{""color"":""#fff""}},""TransportLeg"":{""color"":{""background"":""#c4b5fd"",""border"":""#8b5cf6""}},""Location"":{""color"":{""background"":""#34d399"",""border"":""#059669""}}}"
    Set gopt("legend") = 0
    Set gopt("edgeHighlight") = "#f59e0b"
    Do ##class(Graph.UI.Network).Widget("net", tGraphJSON, .gopt)
    Write "<div class='legend'>"
    Write "<span><i class='dot risk'></i><span data-i18n='legRisk'></span></span><span><i class='dot impact'></i><span data-i18n='legImpact'></span></span><span><i class='dot biz'></i><span data-i18n='legBiz'></span></span><span><i class='dot route'></i><span data-i18n='legRoute'></span></span><span><i class='dot transport'></i><span data-i18n='legTransport'></span></span><span><i class='dot geo'></i><span data-i18n='legGeo'></span></span>"
    Write "</div></div>"

    Write "<div class='card'><h2>&#129302; <span data-i18n='recTitle'></span></h2>"
    Do ..recommendations(.tTransit, .tSups, .tPOs, .tImpacts)
    Write "</div></section>", !

    Write "<footer class='foot' data-i18n='footer'></footer>", !

    Do ..I18NScript()
    Write "</body></html>", !

    Quit $$$OK
}

/// 把 hop 结果的终点标签收集成 %List
/// Collect the endpoint labels of the hop result into a %List
/// pUseSource=1 取 hop.OID（反向多跳终点），否则取 hop.TargetOID
/// When pUseSource=1 take hop.OID (endpoint of a reverse multi-hop), otherwise take hop.TargetOID
ClassMethod hopLabels(pResult As %DynamicArray, pUseSource As %Boolean, Output pList As %List)
{
    Set pList = ""
    For i = 1:1:pResult.%Size() {
        Set tHop = pResult.%Get(i - 1)
        Set tOID = $Select(pUseSource: tHop.OID, 1: tHop.TargetOID)
        Set pList = pList _ $ListBuild(##class(Logistics.Test.PersianGulfDemo).Label(tOID))
    }
}

/// 构造 vis-network 图数据（从风险出发的 BFS 影响子图）
/// Build the vis-network graph data (BFS impact subgraph starting from the risk)
ClassMethod GraphJSON(pRisk As %List) As %String
{
    Do ##class(Graph.Tools).BFS(pRisk, 8, .tHops)
    Set tNodes = [], tEdges = []
    Kill tSeen
    Do ..addNode(pRisk, .tSeen, tNodes)
    For i = 1:1:tHops.%Size() {
        Set tHop = tHops.%Get(i - 1)
        Do ..addNode(tHop.OID, .tSeen, tNodes)
        Do ..addNode(tHop.TargetOID, .tSeen, tNodes)
        Set tE = {}
        Set tE.from = ..nid(tHop.OID), tE.to = ..nid(tHop.TargetOID), tE.label = tHop.Relation
        Do tEdges.%Push(tE)
    }
    Set tG = {}, tG.nodes = tNodes, tG.edges = tEdges
    Quit tG.%ToJSON()
}

/// 节点 id：OID($LB(Id,Class)) → "Id~Class"
/// Node id: OID($LB(Id,Class)) → "Id~Class"
ClassMethod nid(pOID As %List) As %String
{
    Quit $ListGet(pOID, 1) _ "~" _ $ListGet(pOID, 2)
}

/// 追加去重节点
/// Append a node with de-duplication
ClassMethod addNode(pOID As %List, ByRef pSeen, pNodes As %DynamicArray)
{
    Set tId = ..nid(pOID)
    Quit:$Data(pSeen(tId))
    Set pSeen(tId) = 1
    Set tShort = $Piece($ListGet(pOID, 2), ".", *)
    Set tN = {}
    Set tN.id = tId
    Set tN.label = ##class(Logistics.Test.PersianGulfDemo).Label(pOID)
    Set tN.group = tShort
    Set tN.title = ..NodeDesc(pOID)   // 鼠标悬停提示 | Mouse hover tooltip
    Do pNodes.%Push(tN)
}

/// 生成节点的简单描述（用作 vis-network 悬停 tooltip）
/// Generate a simple node description (used as the vis-network hover tooltip)
ClassMethod NodeDesc(pOID As %List) As %String
{
    Set tId = $ListGet(pOID, 1), tCls = $ListGet(pOID, 2), tShort = $Piece(tCls, ".", *)
    Set tDesc = ""
    Try {
        Set tObj = $ClassMethod(tCls, "%OpenId", tId)
        Quit:'$IsObject(tObj)
        If tShort = "RiskEvent" {
            Set tLoc = $Select($IsObject(tObj.Location): tObj.Location.Name, 1: "")
            Set tDesc = "风险事件 · " _ tObj.Name _ " [" _ tObj.Type _ "] · 严重度 " _ tObj.Severity _ "/10"
            Set:tLoc'="" tDesc = tDesc _ " · 位置 " _ tLoc
            Set:tObj.Forecast'="" tDesc = tDesc _ " · " _ tObj.Forecast
        } ElseIf tShort = "RouteSegment" {
            Set tDesc = "航段 · " _ tObj.Name
        } ElseIf tShort = "Route" {
            Set tDesc = "航路 · " _ tObj.RouteName
        } ElseIf tShort = "Voyage" {
            Set tDesc = "航次 · " _ tObj.VoyageNo
        } ElseIf tShort = "Vessel" {
            Set tDesc = "船舶 · " _ tObj.Name _ " (IMO " _ tObj.IMO _ ")"
        } ElseIf tShort = "Location" {
            Set tDesc = "地点 · " _ tObj.Name _ " / " _ tObj.Type
        } ElseIf tShort = "Shipment" {
            Set tDesc = "货运 · " _ tObj.ShipmentNo
        } ElseIf tShort = "Container" {
            Set tDesc = "集装箱 · " _ tObj.ContainerNo
        } ElseIf tShort = "TransportLeg" {
            Set tDesc = "运输段 · Leg#" _ tObj.LegNo
        } ElseIf tShort = "PurchaseOrder" {
            Set tDesc = "采购单 · " _ tObj.PONumber
        } ElseIf tShort = "Product" {
            Set tDesc = "产品 · " _ tObj.SKU _ " " _ tObj.Name
        } ElseIf tShort = "Supplier" {
            Set tDesc = "供应商 · " _ tObj.Name
        } ElseIf tShort = "HSCode" {
            Set tDesc = "HS 编码 · " _ tObj.Code
        } ElseIf tShort = "Impact" {
            Set tDesc = "影响 · " _ tObj.Type _ " · 延误 " _ tObj.DelayHours _ " 小时"
        } ElseIf tShort = "RouteImpact" {
            Set tDesc = "航路影响 · 严重度 " _ tObj.Severity
        } Else {
            Set tDesc = tShort
        }
    } Catch { Set tDesc = "" }
    Quit tDesc
}

/// 渲染单个 KPI 卡片
/// Render a single KPI card
ClassMethod kpi(pKey As %String, pValue As %Integer, pIcon As %String)
{
    Write "<div class='kpi'><div class='kpi-ico'>", pIcon, "</div><div class='kpi-num'>", +pValue, "</div><div class='kpi-lbl' data-i18n='", pKey, "'></div></div>"
}

/// 基于图追踪结果生成规则化 AI 建议
/// Generate rule-based AI recommendations from the graph tracing result
ClassMethod recommendations(ByRef pTransit As %List, ByRef pSups As %List, ByRef pPOs As %List, ByRef pImpacts As %List)
{
    Set tN = 0
    // 1) 改航路：物理途经受影响航段的货运
    // 1) Reroute: shipments physically transiting the affected segment
    For i = 1:1:$ListLength(pTransit) {
        Set tN = tN + 1
        Do ..rec("high", "recRerouteT", "recRerouteA", $List(pTransit, i), "recRerouteB")
    }
    // 2) 备用供应商
    // 2) Backup supplier
    For i = 1:1:$ListLength(pSups) {
        Set tN = tN + 1
        Do ..rec("mid", "recSupplierT", "recSupplierA", $List(pSups, i), "recSupplierB")
    }
    // 3) 通知采购方
    // 3) Notify the buyer
    For i = 1:1:$ListLength(pPOs) {
        Set tN = tN + 1
        Do ..rec("mid", "recPoT", "recPoA", $List(pPOs, i), "recPoB")
    }
    // 4) 安全库存
    // 4) Safety stock
    If $ListLength(pImpacts) > 0 {
        Set tN = tN + 1
        Do ..rec("low", "recStockT", "recStockA", $ListGet(pImpacts, 1), "recStockB")
    }
    If tN = 0 { Write "<p class='muted' data-i18n='recNone'></p>" }
}

/// 渲染单条建议（静态文案用 data-i18n，动态值包在 <b> 中）
/// Render a single recommendation (static copy via data-i18n, dynamic value wrapped in <b>)
ClassMethod rec(pLevel As %String, pTitleKey As %String, pTextA As %String, pVal As %String, pTextB As %String)
{
    Write "<div class='rec rec-", pLevel, "'>"
    Write "<div class='rec-title' data-i18n='", pTitleKey, "'></div>"
    Write "<div class='rec-text'><span data-i18n='", pTextA, "'></span><b>", ..esc(pVal), "</b><span data-i18n='", pTextB, "'></span></div>"
    Write "</div>"
}

/// i18n 脚本（单语切换，参考 ResearchChatWithHITL）/ i18n script (single-language toggle)
ClassMethod I18NScript()
{
    Write "<script>", !
    Write "var LANG=localStorage.getItem('risklang');", !
    Write "if(LANG!=='zh'&&LANG!=='en'){LANG=((navigator.language||'').toLowerCase().indexOf('zh')===0)?'zh':'en';}", !
    Write "var I18N={", !
    Write "langBtn:{zh:'EN',en:'中文'},", !
    Write "brandName:{zh:'供应链风险图谱',en:'Supply-chain Risk Graph'},", !
    Write "brandSub:{zh:'基于 InterSystems IRIS 图索引的实时影响传播分析',en:'Real-time impact-propagation analysis on the InterSystems IRIS graph index'},", !
    Write "triggerCalm:{zh:'触发 Hormuz Tension 风险',en:'Trigger Hormuz Tension risk'},", !
    Write "triggerAgain:{zh:'重新触发风险',en:'Re-trigger risk'},", !
    Write "reset:{zh:'重置',en:'Reset'},", !
    Write "calmTitle:{zh:'一切正常 · 当前无风险',en:'All clear · no active risk'},", !
    Write "calmMeta:{zh:'基线供应链数据已加载。点击「触发 Hormuz Tension 风险」模拟霍尔木兹海峡封锁，查看图追踪的影响链与建议。',en:'Baseline supply-chain data loaded. Click ""Trigger Hormuz Tension risk"" to simulate a Strait of Hormuz blockade and view the graph-traced impact chain and recommendations.'},", !
    Write "bigbtn:{zh:'触发 Hormuz Tension 风险',en:'Trigger Hormuz Tension risk'},", !
    Write "alertDetected:{zh:'检测到高风险事件：',en:'High-risk event detected: '},", !
    Write "severity:{zh:'严重度',en:'Severity'},", !
    Write "location:{zh:'位置',en:'Location'},", !
    Write "kpiSeg:{zh:'受影响航段',en:'Affected segments'},", !
    Write "kpiShip:{zh:'受影响货运',en:'Affected shipments'},", !
    Write "kpiPo:{zh:'受影响采购单',en:'Affected purchase orders'},", !
    Write "kpiSup:{zh:'受影响供应商',en:'Affected suppliers'},", !
    Write "chainTitle:{zh:'影响传播链 (Impact Propagation Chain)',en:'Impact Propagation Chain'},", !
    Write "chainHintA:{zh:'沿图边',en:'Trace along graph edges'},", !
    Write "chainHintB:{zh:'追踪风险如何传导至业务对象',en:'to see how risk propagates to business objects'},", !
    Write "noImpact:{zh:'（无影响节点）',en:'(no impact nodes)'},", !
    Write "transitTitle:{zh:'物理途经受影响航段的货运',en:'Shipments physically transiting the affected segment'},", !
    Write "transitHint:{zh:'(反向多跳: Route ← Voyage ← Vessel ← Container ← Shipment)',en:'(reverse multi-hop: Route ← Voyage ← Vessel ← Container ← Shipment)'},", !
    Write "none2:{zh:'（无）',en:'(none)'},", !
    Write "graphTitle:{zh:'图追踪影响子图',en:'Graph-traced impact subgraph'},", !
    Write "legRisk:{zh:'风险',en:'Risk'},", !
    Write "legImpact:{zh:'影响',en:'Impact'},", !
    Write "legBiz:{zh:'业务',en:'Business'},", !
    Write "legRoute:{zh:'航路/航段',en:'Route / segment'},", !
    Write "legTransport:{zh:'运输',en:'Transport'},", !
    Write "legGeo:{zh:'地理',en:'Geo'},", !
    Write "recTitle:{zh:'AI 建议 (Recommendations)',en:'AI Recommendations'},", !
    Write "recRerouteT:{zh:'改走备用航路',en:'Reroute via alternate lane'},", !
    Write "recRerouteA:{zh:'货运 ',en:'Shipment '},", !
    Write "recRerouteB:{zh:' 正途经受影响航段，建议改走备用航路「Asia-Europe via Cape（绕行好望角）」，预计 +10~14 天但可规避封锁风险。',en:' is transiting the affected segment. Reroute via ""Asia-Europe via Cape"" (around the Cape of Good Hope): ~+10-14 days but avoids the blockade risk.'},", !
    Write "recSupplierT:{zh:'启用备用供应商',en:'Activate backup supplier'},", !
    Write "recSupplierA:{zh:'供应商 ',en:'Supplier '},", !
    Write "recSupplierB:{zh:' 位于风险区域，建议评估并激活备用供应商，降低断供风险。',en:' is in the risk zone. Evaluate and activate a backup supplier to reduce supply-disruption risk.'},", !
    Write "recPoT:{zh:'通知采购方并调整交期',en:'Notify buyer and adjust delivery dates'},", !
    Write "recPoA:{zh:'采购单 ',en:'Purchase order '},", !
    Write "recPoB:{zh:' 预计受延误影响，建议提前通知采购方并重排交付计划。',en:' is expected to be delayed. Notify the buyer early and reschedule the delivery plan.'},", !
    Write "recStockT:{zh:'提高安全库存',en:'Raise safety stock'},", !
    Write "recStockA:{zh:'针对预测延误（',en:'For the forecasted delay ('},", !
    Write "recStockB:{zh:'），建议对关键物料临时提高安全库存 7~14 天。',en:'), temporarily raise safety stock for critical materials by 7-14 days.'},", !
    Write "recNone:{zh:'暂无建议。',en:'No recommendations.'},", !
    Write "footer:{zh:'数据由 Logistics.Test.PersianGulfDemo 构造 · 图边由 Graph.Object.Index 功能索引自动维护 · 查询走 Graph.Tools（SingleHop / MultiHop / BFS）',en:'Data built by Logistics.Test.PersianGulfDemo · graph edges auto-maintained by the Graph.Object.Index functional index · queries via Graph.Tools (SingleHop / MultiHop / BFS)'}", !
    Write "};", !
    Write "function t(k){var e=I18N[k];return e?(e[LANG]||e.en):k;}", !
    Write "function applyLang(){document.documentElement.lang=(LANG==='zh')?'zh-CN':'en';var els=document.querySelectorAll('[data-i18n]');for(var i=0;i<els.length;i++){els[i].textContent=t(els[i].getAttribute('data-i18n'));}}", !
    Write "function toggleLang(){LANG=(LANG==='zh')?'en':'zh';localStorage.setItem('risklang',LANG);applyLang();}", !
    Write "window.addEventListener('DOMContentLoaded',function(){var lb=document.getElementById('langtoggle');if(lb)lb.onclick=toggleLang;applyLang();});", !
    Write "</script>", !
}

/// HTML 转义
/// HTML escaping
ClassMethod esc(pText As %String) As %String
{
    Quit $ZCONVERT(pText, "O", "HTML")
}

/// 页面样式
/// Page styles
ClassMethod CSS() As %String
{
    Quit "*{box-sizing:border-box}body{margin:0;font-family:system-ui,-apple-system,'Segoe UI',Roboto,'PingFang SC','Microsoft YaHei',sans-serif;background:#f1f5f9;color:#0f172a}"
     _ ".topbar{background:linear-gradient(90deg,#0f172a,#1e293b);color:#fff;padding:16px 28px;display:flex;align-items:center;gap:16px;box-shadow:0 2px 10px rgba(0,0,0,.15)}"
     _ ".brand{font-size:20px;font-weight:700}.sub{color:#94a3b8;font-size:13px;flex:1}"
     _ ".rebuild{color:#e2e8f0;background:#334155;padding:8px 14px;border-radius:8px;text-decoration:none;font-size:13px}.rebuild:hover{background:#475569}"
     _ ".trigger{color:#fff;background:#ef4444;padding:8px 16px;border-radius:8px;text-decoration:none;font-size:13px;font-weight:700}.trigger:hover{background:#dc2626}"
     _ ".alert.calm{background:#ecfdf5;border-color:#a7f3d0;border-left-color:#10b981}.alert.calm .alert-title{color:#065f46}.alert.calm .alert-meta{color:#047857}"
     _ ".bigbtn{display:inline-block;background:#ef4444;color:#fff;padding:15px 30px;border-radius:12px;text-decoration:none;font-size:18px;font-weight:800;box-shadow:0 6px 16px rgba(239,68,68,.35)}.bigbtn:hover{background:#dc2626}"
     _ ".alert{margin:20px 24px;background:#fef2f2;border:1px solid #fecaca;border-left:5px solid #ef4444;border-radius:12px;padding:16px 20px;display:flex;gap:16px;align-items:center}"
     _ ".alert-icon{font-size:32px}.alert-title{font-size:17px;font-weight:700;color:#991b1b}.alert-meta{color:#7f1d1d;font-size:13px;margin-top:4px}"
     _ ".badge{font-size:12px;padding:2px 8px;border-radius:6px;background:#ef4444;color:#fff;vertical-align:middle}"
     _ ".kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin:0 24px 20px}"
     _ ".kpi{background:#fff;border-radius:12px;padding:18px;box-shadow:0 1px 4px rgba(0,0,0,.06);display:flex;flex-direction:column;align-items:center}"
     _ ".kpi-ico{font-size:26px}.kpi-num{font-size:34px;font-weight:800;color:#1e293b;line-height:1.1}.kpi-lbl{color:#64748b;font-size:13px;margin-top:2px}"
     _ ".card{background:#fff;border-radius:14px;padding:20px 24px;margin:0 24px 20px;box-shadow:0 1px 6px rgba(0,0,0,.06)}"
     _ ".card h2{margin:0 0 6px;font-size:18px}.card h3{margin:18px 0 6px;font-size:15px;color:#334155}"
     _ ".hint{color:#94a3b8;font-size:12px;font-weight:400}code{background:#f1f5f9;padding:1px 6px;border-radius:5px;font-size:12px;color:#0f766e}"
     _ ".chain{display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin:12px 0}"
     _ ".chip-col{display:flex;flex-direction:column;gap:8px}"
     _ ".chip{padding:8px 14px;border-radius:20px;font-size:13px;font-weight:600;white-space:nowrap;box-shadow:0 1px 3px rgba(0,0,0,.08)}"
     _ ".chip.risk{background:#ef4444;color:#fff}.chip.impact{background:#f97316;color:#fff}.chip.biz{background:#dbeafe;color:#1e40af}.chip.seg{background:#ccfbf1;color:#0f766e}.chip.muted{background:#f1f5f9;color:#94a3b8}"
     _ ".arrow{color:#94a3b8;font-size:12px;font-weight:700}"
     _ ".grid2{display:grid;grid-template-columns:1.4fr 1fr;gap:0}.grid2 .card{margin-right:24px}.grid2 .card:last-child{margin-left:0}"
     _ "@media(max-width:900px){.grid2{grid-template-columns:1fr}.kpis{grid-template-columns:repeat(2,1fr)}}"
     _ ".net{height:460px;border:1px solid #e2e8f0;border-radius:10px;background:#fafcff}"
     _ ".netbar{display:flex;gap:8px;margin-bottom:8px}.netbar button{border:1px solid #cbd5e1;background:#fff;color:#334155;border-radius:8px;padding:5px 13px;font-size:15px;line-height:1;cursor:pointer;font-weight:700}.netbar button:hover{background:#f1f5f9;border-color:#94a3b8}"
     _ ".legend{display:flex;gap:16px;flex-wrap:wrap;margin-top:10px;font-size:12px;color:#475569}"
     _ ".legend .dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:5px;vertical-align:middle}"
     _ ".dot.risk{background:#ef4444}.dot.impact{background:#fb923c}.dot.biz{background:#3b82f6}.dot.route{background:#14b8a6}.dot.transport{background:#a78bfa}.dot.geo{background:#34d399}"
     _ ".rec{border-left:4px solid #cbd5e1;background:#f8fafc;border-radius:8px;padding:12px 14px;margin-bottom:12px}"
     _ ".rec-title{font-weight:700;font-size:14px;margin-bottom:4px}.rec-text{font-size:13px;color:#475569;line-height:1.5}"
     _ ".rec-high{border-left-color:#ef4444;background:#fef2f2}.rec-mid{border-left-color:#f59e0b;background:#fffbeb}.rec-low{border-left-color:#10b981;background:#ecfdf5}"
     _ ".muted{color:#94a3b8}.foot{text-align:center;color:#94a3b8;font-size:12px;padding:16px 24px 30px}"
}

}
