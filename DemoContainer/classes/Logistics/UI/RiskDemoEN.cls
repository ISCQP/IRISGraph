Include %occInclude

/// Graph-based supply chain risk identification & recommendations · CSP demo page (English)
/// 
/// URL: /csp/healthshare/nehr/Logistics.UI.RiskDemoEN.cls
///      ?action=setup rebuilds the demo scenario data
/// 
/// Sections:
///   1) Risk alert (RiskEvent)
///   2) KPIs (# affected segments / shipments / POs / suppliers)
///   3) Impact propagation chain (Risk -> Impact -> shipments/POs/suppliers; + shipments transiting the segment)
///   4) Graph-traced interactive view (vis-network, BFS impact subgraph from the risk)
///   5) AI recommendations (rule-based, derived from the graph trace)
/// 
/// Data is built by Logistics.Test.PersianGulfDemo.Setup(); graph edges are auto-maintained by the
/// Graph.Object.Index functional index; all traversals go through Graph.Tools (SingleHop / MultiHop / BFS).
/// Author: QP
/// Version: 1.0
Class Logistics.UI.RiskDemoEN Extends %CSP.Page
{

Parameter CONTENTTYPE = "text/html";

Parameter CHARSET = "UTF-8";

/// Page entry point
ClassMethod OnPage() As %Status
{
    // Action routing: trigger risk / reset / full rebuild / ensure baseline on first load
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

    // No active risk -> calm state with a trigger call-to-action
    If tRisk = "" {
        Write "<!DOCTYPE html>", !
        Write "<html lang='en'><head><meta charset='UTF-8'>", !
        Write "<meta name='viewport' content='width=device-width, initial-scale=1.0'>", !
        Write "<title>Graph-Based Supply Chain Risk Identification &amp; Recommendations</title>", !
        Write "<style>", ..CSS(), "</style></head><body>", !
        Write "<header class='topbar'>"
        Write "<div class='brand'>&#127760; GraphRisk &#183; Supply Chain Risk Graph</div>"
        Write "<div class='sub'>Real-time impact propagation analysis powered by the InterSystems IRIS graph index</div>"
        Write "<a class='trigger' href='?action=trigger'>&#9889; Trigger Hormuz Tension Risk</a>"
        Write "<a class='rebuild' href='?action=clear'>&#8635; Reset</a>"
        Write "</header>", !
        Write "<section class='alert calm'><div class='alert-icon'>&#9989;</div><div class='alert-body'>"
        Write "<div class='alert-title'>All clear &#183; No active risk</div>"
        Write "<div class='alert-meta'>Baseline supply chain is loaded. Click <b>Trigger Hormuz Tension Risk</b> to simulate a Strait of Hormuz blockade and reveal the graph-traced impact chain &amp; recommendations.</div>"
        Write "</div></section>"
        Write "<section class='card' style='text-align:center;padding:44px 24px'>"
        Write "<a class='bigbtn' href='?action=trigger'>&#9889; Trigger Hormuz Tension Risk</a>"
        Write "</section>"
        Write "</body></html>", !
        Quit $$$OK
    }

    // Risk details
    Set tRName = "", tRType = "", tRSev = "", tRForecast = "", tRLoc = ""
    Set tRObj = ##class(Logistics.Risk.RiskEvent).%OpenId($ListGet(tRisk, 1))
    If $IsObject(tRObj) {
        Set tRName = tRObj.Name, tRType = tRObj.Type, tRSev = tRObj.Severity, tRForecast = tRObj.Forecast
        Set:$IsObject(tRObj.Location) tRLoc = tRObj.Location.Name
    }

    // Graph tracing
    Do ##class(Graph.Tools).SingleHop(tRisk, "affects_segment", 0, .tR)  Do ..hopLabels(.tR, 0, .tSegs)
    Do ##class(Graph.Tools).SingleHop(tRisk, "causes", 0, .tR)           Do ..hopLabels(.tR, 0, .tImpacts)
    Do ##class(Graph.Tools).MultiHop(tRisk, [{"Relation":"causes","Inverse":0},{"Relation":"impact_affects_shipment","Inverse":0}], .tR)  Do ..hopLabels(.tR, 0, .tShips)
    Do ##class(Graph.Tools).MultiHop(tRisk, [{"Relation":"causes","Inverse":0},{"Relation":"impact_affects_po","Inverse":0}], .tR)        Do ..hopLabels(.tR, 0, .tPOs)
    Do ##class(Graph.Tools).MultiHop(tRisk, [{"Relation":"causes","Inverse":0},{"Relation":"impact_affects_supplier","Inverse":0}], .tR)  Do ..hopLabels(.tR, 0, .tSups)
    Do ##class(Graph.Tools).MultiHop(tSeg, [{"Relation":"route_contains_segment","Inverse":1},{"Relation":"uses","Inverse":1},{"Relation":"assigned_to","Inverse":1},{"Relation":"loaded_on","Inverse":1},{"Relation":"contains","Inverse":1}], .tR)  Do ..hopLabels(.tR, 1, .tTransit)

    // BFS subgraph -> vis-network data
    Set tGraphJSON = ..GraphJSON(tRisk)

    // ---------- Render (all via Write; HTML attributes use single quotes) ----------
    Write "<!DOCTYPE html>", !
    Write "<html lang='en'><head><meta charset='UTF-8'>", !
    Write "<meta name='viewport' content='width=device-width, initial-scale=1.0'>", !
    Write "<title>Graph-Based Supply Chain Risk Identification &amp; Recommendations</title>", !
    Do ##class(Graph.UI.Network).Head()
    Write "<style>", ..CSS(), ##class(Graph.UI.Network).CSS(), "</style>", !
    Write "</head><body>", !

    Write "<header class='topbar'>"
    Write "<div class='brand'>&#127760; GraphRisk &#183; Supply Chain Risk Graph</div>"
    Write "<div class='sub'>Real-time impact propagation analysis powered by the InterSystems IRIS graph index</div>"
    Write "<a class='trigger' href='?action=trigger'>&#9889; Re-trigger Risk</a>"
    Write "<a class='rebuild' href='?action=clear'>&#8635; Reset</a>"
    Write "</header>", !

    // Risk alert banner
    Write "<section class='alert'><div class='alert-icon'>&#9888;</div><div class='alert-body'>"
    Write "<div class='alert-title'>High-risk event detected: ", ..esc(tRName), " <span class='badge'>", ..esc(tRType), "</span></div>"
    Write "<div class='alert-meta'>Severity <b>", ..esc(tRSev), "/10</b> &#183; Location <b>", ..esc(tRLoc), "</b> &#183; ", ..esc(tRForecast), "</div>"
    Write "</div></section>", !

    // KPIs
    Write "<section class='kpis'>"
    Do ..kpi("Affected Segments", $ListLength(tSegs), "&#129517;")
    Do ..kpi("Affected Shipments", $ListLength(tShips), "&#128674;")
    Do ..kpi("Affected POs", $ListLength(tPOs), "&#128196;")
    Do ..kpi("Affected Suppliers", $ListLength(tSups), "&#127981;")
    Write "</section>", !

    // Impact propagation chain
    Write "<section class='card'><h2>Impact Propagation Chain</h2>"
    Write "<p class='hint'>Trace how the risk propagates to business objects along the <code>causes &#8594; impact_affects_*</code> edges</p>"
    Write "<div class='chain'>"
    Write "<span class='chip risk'>&#9888; ", ..esc(tRName), "</span>"
    Write "<span class='arrow'>causes &#9654;</span>"
    Write "<div class='chip-col'>"
    If $ListLength(tImpacts) = 0 { Write "<span class='chip muted'>(no impact nodes)</span>" }
    For i = 1:1:$ListLength(tImpacts) { Write "<span class='chip impact'>&#9201; ", ..esc($List(tImpacts, i)), "</span>" }
    Write "</div>"
    Write "<span class='arrow'>affects &#9654;</span>"
    Write "<div class='chip-col'>"
    For i = 1:1:$ListLength(tShips) { Write "<span class='chip biz'>&#128674; ", ..esc($List(tShips, i)), "</span>" }
    For i = 1:1:$ListLength(tPOs) { Write "<span class='chip biz'>&#128196; ", ..esc($List(tPOs, i)), "</span>" }
    For i = 1:1:$ListLength(tSups) { Write "<span class='chip biz'>&#127981; ", ..esc($List(tSups, i)), "</span>" }
    Write "</div></div>"

    Write "<h3>Shipments physically transiting the affected segment <span class='hint'>(reverse multi-hop: Route &#8592; Voyage &#8592; Vessel &#8592; Container &#8592; Shipment)</span></h3>"
    Write "<div class='chain'>"
    Write "<span class='chip seg'>&#129517; ", ..esc($ListGet(tSegs, 1, "Affected Segment")), "</span>"
    Write "<span class='arrow'>transits &#9654;</span>"
    Write "<div class='chip-col'>"
    If $ListLength(tTransit) = 0 { Write "<span class='chip muted'>(none)</span>" }
    For i = 1:1:$ListLength(tTransit) { Write "<span class='chip biz'>&#128674; ", ..esc($List(tTransit, i)), "</span>" }
    Write "</div></div></section>", !

    // Graph view + recommendations (two columns)
    Write "<section class='grid2'>"
    Write "<div class='card'><h2>Graph-Traced Impact Subgraph <span class='hint'>(BFS from Risk)</span></h2>"
    // Subgraph rendered by the standard component Graph.UI.Network
    Set gopt("groups") = "{""RiskEvent"":{""color"":{""background"":""#ef4444"",""border"":""#b91c1c""},""font"":{""color"":""#fff""}},""RouteImpact"":{""color"":{""background"":""#f97316"",""border"":""#c2410c""}},""Impact"":{""color"":{""background"":""#fb923c"",""border"":""#ea580c""},""font"":{""color"":""#fff""}},""Shipment"":{""color"":{""background"":""#3b82f6"",""border"":""#1d4ed8""},""font"":{""color"":""#fff""}},""Container"":{""color"":{""background"":""#60a5fa"",""border"":""#2563eb""}},""PurchaseOrder"":{""color"":{""background"":""#6366f1"",""border"":""#4338ca""},""font"":{""color"":""#fff""}},""Product"":{""color"":{""background"":""#818cf8"",""border"":""#4f46e5""}},""Supplier"":{""color"":{""background"":""#0ea5e9"",""border"":""#0369a1""},""font"":{""color"":""#fff""}},""HSCode"":{""color"":{""background"":""#38bdf8"",""border"":""#0284c7""}},""Route"":{""color"":{""background"":""#14b8a6"",""border"":""#0f766e""},""font"":{""color"":""#fff""}},""RouteSegment"":{""color"":{""background"":""#2dd4bf"",""border"":""#0d9488""}},""Voyage"":{""color"":{""background"":""#5eead4"",""border"":""#14b8a6""}},""Vessel"":{""color"":{""background"":""#a78bfa"",""border"":""#7c3aed""},""font"":{""color"":""#fff""}},""TransportLeg"":{""color"":{""background"":""#c4b5fd"",""border"":""#8b5cf6""}},""Location"":{""color"":{""background"":""#34d399"",""border"":""#059669""}}}"
    Set gopt("legend") = 0
    Set gopt("edgeHighlight") = "#f59e0b"
    Do ##class(Graph.UI.Network).Widget("net", tGraphJSON, .gopt)
    Write "<div class='legend'>"
    Write "<span><i class='dot risk'></i>Risk</span><span><i class='dot impact'></i>Impact</span><span><i class='dot biz'></i>Business</span><span><i class='dot route'></i>Route/Segment</span><span><i class='dot transport'></i>Transport</span><span><i class='dot geo'></i>Geography</span>"
    Write "</div></div>"

    Write "<div class='card'><h2>&#129302; AI Recommendations</h2>"
    Do ..recommendations(.tTransit, .tSups, .tPOs, .tImpacts)
    Write "</div></section>", !

    Write "<footer class='foot'>Data built by Logistics.Test.PersianGulfDemo &#183; graph edges auto-maintained by the Graph.Object.Index functional index &#183; queries via Graph.Tools (SingleHop / MultiHop / BFS)</footer>", !

    Write "</body></html>", !

    Quit $$$OK
}

/// Collect the terminal-node labels of hop results into a %List
/// pUseSource=1 uses hop.OID (terminal of a reverse multi-hop), otherwise hop.TargetOID
ClassMethod hopLabels(pResult As %DynamicArray, pUseSource As %Boolean, Output pList As %List)
{
    Set pList = ""
    For i = 1:1:pResult.%Size() {
        Set tHop = pResult.%Get(i - 1)
        Set tOID = $Select(pUseSource: tHop.OID, 1: tHop.TargetOID)
        Set pList = pList _ $ListBuild(##class(Logistics.Test.PersianGulfDemo).Label(tOID))
    }
}

/// Build vis-network graph data (BFS impact subgraph from the risk)
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

/// Node id: OID($LB(Id,Class)) -> "Id~Class"
ClassMethod nid(pOID As %List) As %String
{
    Quit $ListGet(pOID, 1) _ "~" _ $ListGet(pOID, 2)
}

/// Append a de-duplicated node
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
    Set tN.title = ..NodeDesc(pOID)   // hover tooltip
    Do pNodes.%Push(tN)
}

/// Build a short description for a node (used as the vis-network hover tooltip)
ClassMethod NodeDesc(pOID As %List) As %String
{
    Set tId = $ListGet(pOID, 1), tCls = $ListGet(pOID, 2), tShort = $Piece(tCls, ".", *)
    Set tDesc = ""
    Try {
        Set tObj = $ClassMethod(tCls, "%OpenId", tId)
        Quit:'$IsObject(tObj)
        If tShort = "RiskEvent" {
            Set tLoc = $Select($IsObject(tObj.Location): tObj.Location.Name, 1: "")
            Set tDesc = "Risk event · " _ tObj.Name _ " [" _ tObj.Type _ "] · severity " _ tObj.Severity _ "/10"
            Set:tLoc'="" tDesc = tDesc _ " · location " _ tLoc
            Set:tObj.Forecast'="" tDesc = tDesc _ " · " _ tObj.Forecast
        } ElseIf tShort = "RouteSegment" {
            Set tDesc = "Route segment · " _ tObj.Name
        } ElseIf tShort = "Route" {
            Set tDesc = "Route · " _ tObj.RouteName
        } ElseIf tShort = "Voyage" {
            Set tDesc = "Voyage · " _ tObj.VoyageNo
        } ElseIf tShort = "Vessel" {
            Set tDesc = "Vessel · " _ tObj.Name _ " (IMO " _ tObj.IMO _ ")"
        } ElseIf tShort = "Location" {
            Set tDesc = "Location · " _ tObj.Name _ " / " _ tObj.Type
        } ElseIf tShort = "Shipment" {
            Set tDesc = "Shipment · " _ tObj.ShipmentNo
        } ElseIf tShort = "Container" {
            Set tDesc = "Container · " _ tObj.ContainerNo
        } ElseIf tShort = "TransportLeg" {
            Set tDesc = "Transport leg · Leg#" _ tObj.LegNo
        } ElseIf tShort = "PurchaseOrder" {
            Set tDesc = "Purchase order · " _ tObj.PONumber
        } ElseIf tShort = "Product" {
            Set tDesc = "Product · " _ tObj.SKU _ " " _ tObj.Name
        } ElseIf tShort = "Supplier" {
            Set tDesc = "Supplier · " _ tObj.Name
        } ElseIf tShort = "HSCode" {
            Set tDesc = "HS code · " _ tObj.Code
        } ElseIf tShort = "Impact" {
            Set tDesc = "Impact · " _ tObj.Type _ " · delay " _ tObj.DelayHours _ "h"
        } ElseIf tShort = "RouteImpact" {
            Set tDesc = "Route impact · severity " _ tObj.Severity
        } Else {
            Set tDesc = tShort
        }
    } Catch { Set tDesc = "" }
    Quit tDesc
}

/// Render one KPI card
ClassMethod kpi(pTitle As %String, pValue As %Integer, pIcon As %String)
{
    Write "<div class='kpi'><div class='kpi-ico'>", pIcon, "</div><div class='kpi-num'>", +pValue, "</div><div class='kpi-lbl'>", ..esc(pTitle), "</div></div>"
}

/// Generate rule-based AI recommendations from the graph-trace results
ClassMethod recommendations(ByRef pTransit As %List, ByRef pSups As %List, ByRef pPOs As %List, ByRef pImpacts As %List)
{
    Set tN = 0
    // 1) Reroute: shipments physically transiting the affected segment
    For i = 1:1:$ListLength(pTransit) {
        Set tN = tN + 1
        Do ..rec("high", "Reroute via Alternative Path", "Shipment <b>" _ ..esc($List(pTransit, i)) _ "</b> is transiting the affected segment. Recommend rerouting via the backup path 'Asia-Europe via Cape' (round the Cape of Good Hope): ~+10-14 days, but avoids the blockade risk.")
    }
    // 2) Backup supplier
    For i = 1:1:$ListLength(pSups) {
        Set tN = tN + 1
        Do ..rec("mid", "Activate Backup Supplier", "Supplier <b>" _ ..esc($List(pSups, i)) _ "</b> is located in the risk area. Recommend evaluating and activating a backup supplier to reduce the supply-disruption risk.")
    }
    // 3) Notify buyer
    For i = 1:1:$ListLength(pPOs) {
        Set tN = tN + 1
        Do ..rec("mid", "Notify Buyer & Adjust Delivery", "Purchase order <b>" _ ..esc($List(pPOs, i)) _ "</b> is expected to be delayed. Recommend notifying the buyer in advance and rescheduling the delivery plan.")
    }
    // 4) Safety stock
    If $ListLength(pImpacts) > 0 {
        Set tN = tN + 1
        Do ..rec("low", "Increase Safety Stock", "Given the predicted delay (" _ ..esc($ListGet(pImpacts, 1)) _ "), recommend temporarily increasing safety stock of critical materials by 7-14 days.")
    }
    If tN = 0 { Write "<p class='muted'>No recommendations.</p>" }
}

/// Render one recommendation card
ClassMethod rec(pLevel As %String, pTitle As %String, pText As %String)
{
    Write "<div class='rec rec-", pLevel, "'>"
    Write "<div class='rec-title'>", ..esc(pTitle), "</div>"
    Write "<div class='rec-text'>", pText, "</div>"
    Write "</div>"
}

/// HTML escape
ClassMethod esc(pText As %String) As %String
{
    Quit $ZCONVERT(pText, "O", "HTML")
}

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
