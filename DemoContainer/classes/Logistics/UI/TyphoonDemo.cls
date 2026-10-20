Include %occInclude

/// Typhoon risk impact tracking - map visualization + LLM advisory - CSP demo page
/// 
/// URL: /csp/healthshare/nehr/Logistics.UI.TyphoonDemo.cls
///      ?action=setup rebuilds the demo scenario data
/// 
/// Page contents:
///   1) Typhoon warning (RiskEvent)
///   2) Map (SVG): shows all vessels and the typhoon, highlighting "affected vessels" (red pulse),
///      "spatially on route but time-clear" vessels (amber), and other vessels (gray)
///   3) KPI: counts of affected vessels / containers / purchase orders / customers
///   4) Affected vessel list (time window crossing the typhoon segment)
///   5) Other affected entities (containers / shipments / purchase orders / customers), traced via the graph:
///      Vessel <-loaded_on- Container <-contains- Shipment <-fulfilled_by- PurchaseOrder
///          -po_contains_product-> Product <-so_contains_product- SalesOrder(.Customer)
///   6) LLM risk advisory (calls NEHR.Tools.CallOpenAI; falls back to built-in rule-based advice when unavailable)
/// 
/// Data is built by Logistics.Test.TyphoonDemo.Setup(); the spatial+temporal check runs through
/// Logistics.Risk.Tools.AnalyzeRisk, and graph edges are maintained automatically by the Graph.Object.Index functional index.
/// Author: QP
/// Version: 1.0
Class Logistics.UI.TyphoonDemo Extends %CSP.Page
{

Parameter CONTENTTYPE = "text/html";

Parameter CHARSET = "UTF-8";

/// Page entry point
ClassMethod OnPage() As %Status
{
    // Action routing: rebuild data / ensure data exists on first visit
    Set tAction = %request.Get("action")
    If tAction = "setup" { Do ##class(Logistics.Test.TyphoonDemo).Setup() }
    ElseIf $Get(^LogiTyphoon("key", "risk")) = "" { Do ##class(Logistics.Test.TyphoonDemo).Setup() }

    Set tRisk = $Get(^LogiTyphoon("key", "risk"))
    Set tRObj = ##class(Logistics.Risk.RiskEvent).%OpenId($ListGet(tRisk, 1))
    Set tRName = "", tRType = "", tRSev = "", tRLoc = "", tRStart = "", tREnd = ""
    If $IsObject(tRObj) {
        Set tRName = tRObj.Name, tRType = tRObj.Type, tRSev = tRObj.Severity
        Set tRStart = tRObj.StartTime, tREnd = tRObj.EndTime
        Set:$IsObject(tRObj.Location) tRLoc = tRObj.Location.Name
    }

    // One-shot fetch: spatial+temporal check, affected business entities, impact graph (nodes/edges)
    Do ##class(Logistics.Risk.ImpactAnalyzer).Analyze(tRisk, .tSpatial, .tAffected, .tCont, .tShip, .tPO, .tCust, .tNodes, .tEdges)

    // Map + graph data
    Set tVJSON = ..VesselsJSON(.tSpatial, .tAffected)
    Set tTJSON = ..TyphoonJSON(tRObj)
    Set tGraphJSON = ..ImpactGraphJSON(.tNodes, .tEdges)

    // KPI counts
    Set tNVes = ..count(.tAffected), tNCont = ..count(.tCont), tNPO = ..count(.tPO), tNCust = ..count(.tCust)

    // ---------- Render ----------
    Write "<!DOCTYPE html>", !
    Write "<html lang='en'><head><meta charset='UTF-8'>", !
    Write "<meta name='viewport' content='width=device-width, initial-scale=1.0'>", !
    Write "<title>Typhoon Risk Impact Tracking</title>", !
    Do ##class(Graph.UI.Network).Head()
    Write "<style>", ..CSS(), ##class(Graph.UI.Network).CSS(), "</style></head><body>", !

    Write "<header class='topbar'>"
    Write "<div class='brand'>&#127786; TyphoonTrack &#183; Supply-Chain Risk Graph</div>"
    Write "<div class='sub'>Spatial + temporal impact analysis on InterSystems IRIS graph index</div>"
    Write "<a class='rebuild' href='?action=setup'>&#8635; Rebuild demo data</a>"
    Write "</header>", !

    // Alert bar
    Write "<section class='alert'><div class='alert-icon'>&#127786;</div><div class='alert-body'>"
    Write "<div class='alert-title'>Typhoon warning: ", ..esc(tRName), " <span class='badge'>", ..esc(tRType), "</span></div>"
    Write "<div class='alert-meta'>Severity <b>", ..esc(tRSev), "/10</b> &#183; Area <b>", ..esc(tRLoc), "</b> &#183; Time window <b>", ..esc(tRStart), " ~ ", ..esc(tREnd), "</b></div>"
    Write "</div></section>", !

    // KPI
    Write "<section class='kpis'>"
    Do ..kpi("Affected vessels", tNVes, "&#128674;")
    Do ..kpi("Affected containers", tNCont, "&#128230;")
    Do ..kpi("Affected purchase orders", tNPO, "&#128196;")
    Do ..kpi("Affected customers", tNCust, "&#128100;")
    Write "</section>", !

    // Map
    Write "<section class='card'><h2>Situation Map <span class='hint'>(all vessels + typhoon &#183; red pulse = affected, amber = spatially on route but time-clear, gray = normal)</span></h2>"
    Write "<div id='map' class='map'></div>"
    Write "<div class='map-cap'>&#9888; Schematic equirectangular projection; the typhoon influence circle is drawn enlarged from radius ", ..esc(tRObj.Radius), " km for visibility.</div>"
    Write "</section>", !

    // Affected vessels list
    Write "<section class='card'><h2>Affected Vessels <span class='hint'>(spatially on a route through the typhoon area AND time window overlaps)</span></h2>"
    Write "<table class='tbl'><thead><tr><th>Vessel</th><th>IMO</th><th>Route / Voyage</th><th>Typhoon segment</th><th>Time window (overlaps typhoon)</th></tr></thead><tbody>"
    Set tV = ""
    Set tAny = 0
    For {
        Set tV = $Order(tAffected(tV))
        Quit:tV=""
        Set tAny = 1
        Set tInfo = tAffected(tV)
        Set tVObj = ##class(Logistics.Transport.Vessel).%OpenId($ListGet(tV, 1))
        Set tVName = $Select($IsObject(tVObj): tVObj.Name, 1: "?")
        Set tVImo = $Select($IsObject(tVObj): tVObj.IMO, 1: "")
        Set tRoute = ##class(Logistics.Risk.ImpactAnalyzer).RouteInfo(tV)
        Set tSegLbl = ##class(Logistics.Risk.Tools).Label($ListGet(tInfo, 1))
        Set tWin = ##class(Logistics.Risk.Tools).secToTs($ListGet(tInfo, 2)) _ " ~ " _ ##class(Logistics.Risk.Tools).secToTs($ListGet(tInfo, 3))
        Write "<tr class='hot'><td><b>", ..esc(tVName), "</b></td><td>", ..esc(tVImo), "</td><td>", ..esc(tRoute), "</td><td>", ..esc(tSegLbl), "</td><td>", ..esc(tWin), "</td></tr>"
    }
    If 'tAny { Write "<tr><td colspan='5' class='muted'>(no affected vessels)</td></tr>" }
    Write "</tbody></table></section>", !

    // Other affected entities
    Write "<section class='card'><h2>Other Affected Entities <span class='hint'>(graph trace: Vessel &#8592; Container &#8592; Shipment &#8592; PurchaseOrder &#8594; Product &#8592; SalesOrder)</span></h2>"
    Write "<div class='grid3'>"
    // Containers
    Write "<div class='ent'><div class='ent-h'>&#128230; Containers</div>"
    Set tK = "", tHas = 0
    For { Set tK = $Order(tCont(tK))  Quit:tK=""  Set tHas = 1
        Set tR = tCont(tK)
        Write "<div class='ent-row'><b>", ..esc($Piece(tR, "|", 1)), "</b> <span class='tag'>", ..esc($Piece(tR, "|", 2)), "</span> <span class='tag'>", ..esc($Piece(tR, "|", 3)), "</span><div class='ent-sub'>on vessel: ", ..esc($Piece(tR, "|", 4)), "</div></div>"
    }
    Write:'tHas "<div class='muted'>(none)</div>"
    Write "</div>"
    // Shipments
    Write "<div class='ent'><div class='ent-h'>&#128674; Shipments</div>"
    Set tK = "", tHas = 0
    For { Set tK = $Order(tShip(tK))  Quit:tK=""  Set tHas = 1
        Set tR = tShip(tK)
        Write "<div class='ent-row'><b>", ..esc($Piece(tR, "|", 1)), "</b> <span class='tag'>", ..esc($Piece(tR, "|", 4)), "</span><div class='ent-sub'>", ..esc($Piece(tR, "|", 2)), " &#8594; ", ..esc($Piece(tR, "|", 3)), "</div></div>"
    }
    Write:'tHas "<div class='muted'>(none)</div>"
    Write "</div>"
    // Purchase orders + customers
    Write "<div class='ent'><div class='ent-h'>&#128196; Purchase Orders / &#128100; Customers</div>"
    Set tK = "", tHas = 0
    For { Set tK = $Order(tPO(tK))  Quit:tK=""  Set tHas = 1
        Set tR = tPO(tK)
        Write "<div class='ent-row'><b>", ..esc($Piece(tR, "|", 1)), "</b> <span class='tag'>", ..esc($Piece(tR, "|", 2)), "</span></div>"
    }
    Write:'tHas "<div class='muted'>(no purchase orders)</div>"
    Set tK = ""
    For { Set tK = $Order(tCust(tK))  Quit:tK=""
        Write "<div class='ent-row cust'>&#128100; <b>", ..esc(tK), "</b></div>"
    }
    Write "</div>"
    Write "</div></section>", !

    // Impact graph (vis-network)
    Write "<section class='card'><h2>Impact Graph <span class='hint'>(spatial + temporal + business chain from the typhoon)</span></h2>"
    Set gopt("groups") = "{""RiskEvent"":{""color"":{""background"":""#ef4444"",""border"":""#b91c1c""},""font"":{""color"":""#fff""}},""Location"":{""color"":{""background"":""#0ea5e9"",""border"":""#0369a1""},""font"":{""color"":""#fff""}},""RouteSegment"":{""color"":{""background"":""#f59e0b"",""border"":""#b45309""}},""Route"":{""color"":{""background"":""#fbbf24"",""border"":""#b45309""}},""Voyage"":{""color"":{""background"":""#a78bfa"",""border"":""#6d28d9""},""font"":{""color"":""#fff""}},""Vessel"":{""color"":{""background"":""#1e293b"",""border"":""#0f172a""},""font"":{""color"":""#fff""}},""Container"":{""color"":{""background"":""#14b8a6"",""border"":""#0f766e""},""font"":{""color"":""#fff""}},""Shipment"":{""color"":{""background"":""#22c55e"",""border"":""#15803d""},""font"":{""color"":""#fff""}},""PurchaseOrder"":{""color"":{""background"":""#6366f1"",""border"":""#4338ca""},""font"":{""color"":""#fff""}},""Product"":{""color"":{""background"":""#e879f9"",""border"":""#a21caf""}},""SalesOrder"":{""color"":{""background"":""#fb7185"",""border"":""#be123c""},""font"":{""color"":""#fff""}}}"
    Set gopt("legend") = 1
    Set gopt("edgeHighlight") = "#f59e0b"
    Do ##class(Graph.UI.Network).Widget("net", tGraphJSON, .gopt)
    Write "</section>", !

    // LLM recommendation
    Write "<section class='card'><h2>&#129302; AI Risk Advisory <span class='hint'>(LLM generated)</span></h2>"
    Do ..Recommend(tRObj, .tAffected, .tCont, .tShip, .tPO, .tCust)
    Write "</section>", !

    Write "<footer class='foot'>Data built by Logistics.Test.TyphoonDemo &#183; spatial+temporal check via Logistics.Risk.Tools.AnalyzeRisk &#183; graph edges maintained by Graph.Object.Index &#183; LLM via NEHR.Tools.CallOpenAI</footer>", !

    // Map script (JSON variables written separately to avoid quote conflicts with ObjectScript strings)
    Write "<script>", !
    Write "var V = ", tVJSON, ";", !
    Write "var T = ", tTJSON, ";", !
    Write "(function(){", !
    Write "var W=1000,H=560,lonMin=8,lonMax=140,latMin=-45,latMax=42;", !
    Write "function X(lon){return ((lon-lonMin)/(lonMax-lonMin)*W).toFixed(1);}", !
    Write "function Y(lat){return ((latMax-lat)/(latMax-latMin)*H).toFixed(1);}", !
    Write "var s='';", !
    Write "for(var lon=lonMin;lon<=lonMax;lon+=20){s+='<line x1='+X(lon)+' y1=0 x2='+X(lon)+' y2='+H+' class=grid />';}", !
    Write "for(var lat=latMin;lat<=latMax;lat+=15){s+='<line x1=0 y1='+Y(lat)+' x2='+W+' y2='+Y(lat)+' class=grid />';}", !
    Write "if(T&&T.lat!=null){var pxDeg=H/(latMax-latMin);var r=T.radiusKm/111*pxDeg;var rv=Math.max(r*2.2,34);", !
    Write "s+='<circle cx='+X(T.lon)+' cy='+Y(T.lat)+' r='+rv.toFixed(1)+' class=storm />';", !
    Write "s+='<circle cx='+X(T.lon)+' cy='+Y(T.lat)+' r='+(rv*0.55).toFixed(1)+' class=storm2 />';", !
    Write "s+='<text x='+X(T.lon)+' y='+Y(T.lat)+' class=storm-ico>&#127744;</text>';", !
    Write "s+='<text x='+X(T.lon)+' y='+(parseFloat(Y(T.lat))+parseFloat(rv)+16).toFixed(1)+' class=storm-lbl>'+T.name+'</text>';}", !
    Write "V.forEach(function(v){var x=X(v.lon),y=Y(v.lat);", !
    Write "if(v.status=='affected'){s+='<circle cx='+x+' cy='+y+' r=8 class=pulse><animate attributeName=r from=8 to=30 dur=1.6s repeatCount=indefinite /><animate attributeName=opacity from=0.5 to=0 dur=1.6s repeatCount=indefinite /></circle>';}", !
    Write "s+='<circle cx='+x+' cy='+y+' r=7 class=""mk mk-'+v.status+'"" />';", !
    Write "s+='<text x='+(parseFloat(x)+10).toFixed(1)+' y='+(parseFloat(y)+4).toFixed(1)+' class=""mk-lbl mk-lbl-'+v.status+'"">'+v.name+'</text>';});", !
    Write "document.getElementById('map').innerHTML='<svg viewBox=""0 0 '+W+' '+H+'"" class=mapsvg>'+s+'</svg>';", !
    Write "})();", !
    Write "</script>", !

    Write "</body></html>", !
    Quit $$$OK
}

/// Count subscripts in an array
ClassMethod count(ByRef pArr) As %Integer
{
    Set tN = 0, tK = ""
    For { Set tK = $Order(pArr(tK))  Quit:tK=""  Set tN = tN + 1 }
    Quit tN
}

/// Build the map JSON for all vessels (with status: affected / spatial / normal)
ClassMethod VesselsJSON(ByRef pSpatial, ByRef pAffected) As %String
{
    Set tArr = []
    Set tCls = "Logistics.Transport.Vessel"
    Set tId = ""
    For {
        Set tId = $Order(^LogiTyphoon("obj", tCls, tId))
        Quit:tId=""
        Set tObj = ##class(Logistics.Transport.Vessel).%OpenId(tId)
        Continue:'$IsObject(tObj)
        Set tVOID = $ListBuild(tId, tCls)
        Set tStatus = "normal"
        If $Data(pAffected(tVOID)) { Set tStatus = "affected" }
        ElseIf $Data(pSpatial(tVOID)) { Set tStatus = "spatial" }
        Set tN = {}
        Set tN.name = tObj.Name
        Set tN.imo = tObj.IMO
        Set tN.lat = +tObj.Latitude
        Set tN.lon = +tObj.Longitude
        Set tN.status = tStatus
        Do tArr.%Push(tN)
    }
    Quit tArr.%ToJSON()
}

/// Build the map JSON for the typhoon
ClassMethod TyphoonJSON(pRObj As Logistics.Risk.RiskEvent) As %String
{
    Set tO = {}
    If $IsObject(pRObj), $IsObject(pRObj.Location) {
        Set tO.name = pRObj.Name
        Set tO.lat = +pRObj.Location.Latitude
        Set tO.lon = +pRObj.Location.Longitude
        Set tO.radiusKm = +pRObj.Radius
    }
    Quit tO.%ToJSON()
}

/// Hover / click description for a graph node (plain text, newline-separated)
ClassMethod NodeDesc(pOID As %List) As %String
{
    Set tId = $ListGet(pOID, 1), tCls = $ListGet(pOID, 2)
    Set tShort = $Piece(tCls, ".", *)
    Set tObj = $classmethod(tCls, "%OpenId", tId)
    Quit:'$IsObject(tObj) tShort
    Set tNl = $Char(10)
    If tShort = "RiskEvent" {
        Set tLoc = $Select($IsObject(tObj.Location): tObj.Location.Name, 1: "")
        Quit tObj.Name _ tNl _ "Type: " _ tObj.Type _ "  Severity: " _ tObj.Severity _ "/10" _ tNl _ "Wind: " _ tObj.WindSpeed _ " km/h  Radius: " _ tObj.Radius _ " km" _ tNl _ "Area: " _ tLoc _ tNl _ "Window: " _ tObj.StartTime _ " ~ " _ tObj.EndTime
    }
    If tShort = "Location" {
        Quit tObj.Name _ tNl _ "Type: " _ tObj.Type _ tNl _ "Lat/Lon: " _ $FNumber(+tObj.Latitude, "", 3) _ ", " _ $FNumber(+tObj.Longitude, "", 3)
    }
    If tShort = "Vessel" {
        Quit tObj.Name _ tNl _ "IMO: " _ tObj.IMO _ tNl _ "Status: " _ tObj.Status _ tNl _ "Lat/Lon: " _ $FNumber(+tObj.Latitude, "", 3) _ ", " _ $FNumber(+tObj.Longitude, "", 3)
    }
    If tShort = "Voyage" {
        Set tRt = $Select($IsObject(tObj.Route): tObj.Route.RouteID _ " " _ tObj.Route.RouteName, 1: "")
        Quit "Voyage " _ tObj.VoyageNo _ tNl _ "Route: " _ tRt _ tNl _ "ETD: " _ tObj.ETD
    }
    If tShort = "Route" {
        Quit "Route " _ tObj.RouteID _ tNl _ tObj.RouteName
    }
    If tShort = "RouteSegment" {
        Quit "Segment: " _ tObj.Name
    }
    If tShort = "Container" {
        Quit "Container " _ tObj.ContainerNo _ tNl _ "ISO: " _ tObj.ISOCode _ tNl _ "Status: " _ tObj.Status
    }
    If tShort = "Shipment" {
        Set tO = $Select($IsObject(tObj.Origin): tObj.Origin.Name, 1: "")
        Set tD = $Select($IsObject(tObj.Destination): tObj.Destination.Name, 1: "")
        Quit "Shipment " _ tObj.ShipmentNo _ tNl _ tO _ " -> " _ tD _ tNl _ "Status: " _ tObj.Status
    }
    If tShort = "PurchaseOrder" {
        Quit "PO " _ tObj.PONumber _ tNl _ "Status: " _ tObj.Status
    }
    If tShort = "Product" {
        Quit "Product " _ tObj.SKU _ tNl _ tObj.Name
    }
    If tShort = "SalesOrder" {
        Quit "Sales Order" _ tNl _ "Customer: " _ tObj.Customer _ tNl _ "Status: " _ tObj.Status
    }
    Quit tShort
}

/// Build vis-network JSON for the impact subgraph (domain returns abstract nodes/edges)
ClassMethod ImpactGraphJSON(ByRef pN, ByRef pE) As %String
{
    Set tNodes = [], tEdges = []
    Set tK = ""
    For {
        Set tK = $Order(pN(tK))
        Quit:tK=""
        Set tOID = pN(tK)
        Set tNode = {}
        Set tNode.id = tK
        Set tNode.label = ##class(Logistics.Risk.Tools).Label(tOID)
        Set tNode.group = $Piece($ListGet(tOID, 2), ".", *)
        Set tNode.title = ..NodeDesc(tOID)
        Do tNodes.%Push(tNode)
    }
    Set tS = ""
    For {
        Set tS = $Order(pE(tS))
        Quit:tS=""
        Set tR = pE(tS)
        Set tEdge = {}
        Set tEdge.from = $List(tR, 1)
        Set tEdge.to = $List(tR, 2)
        Set tEdge.label = $List(tR, 3)
        Do tEdges.%Push(tEdge)
    }
    Set tG = {}
    Set tG.nodes = tNodes
    Set tG.edges = tEdges
    Quit tG.%ToJSON()
}

/// LLM risk advisory: summarize situation -> call OpenAI; fall back to built-in rules on failure
ClassMethod Recommend(pRObj As Logistics.Risk.RiskEvent, ByRef pAffected, ByRef pCont, ByRef pShip, ByRef pPO, ByRef pCust)
{
    Set tPrompt = ..BuildPrompt(pRObj, .pAffected, .pCont, .pShip, .pPO, .pCust)

    Set tMsgs = []
    Set tSys = {}
    Set tSys.role = "system"
    Set tSys.content = "You are a senior shipping-operations and supply-chain risk management expert. For the given typhoon impact situation, provide concrete, actionable risk-mitigation recommendations. Requirements: list them as separate items, each with a [Recommendation title] and a short rationale; cover route diversion, schedule adjustment, cargo and customer communication, inventory and contract handling; keep the language concise and professional, in English."
    Do tMsgs.%Push(tSys)
    Set tUsr = {}
    Set tUsr.role = "user"
    Set tUsr.content = tPrompt
    Do tMsgs.%Push(tUsr)

    Set tSC = ##class(NEHR.Tools).CallOpenAI(tMsgs, .tAnswer)
    If $$$ISOK(tSC), (tAnswer '= "") {
        Write "<div class='llm'>"
        Write ..nl2br(..esc(tAnswer))
        Write "</div>"
    } Else {
        Write "<div class='llm-note'>&#9888; LLM unavailable (", ..esc($System.Status.GetOneErrorText(tSC)), "). Built-in rule-based recommendations below:</div>"
        Do ..fallback(.pAffected, .pShip, .pPO, .pCust)
    }
}

/// Assemble the situation description submitted to the LLM
ClassMethod BuildPrompt(pRObj As Logistics.Risk.RiskEvent, ByRef pAffected, ByRef pCont, ByRef pShip, ByRef pPO, ByRef pCust) As %String
{
    Set tL = "Typhoon impact situation:" _ $Char(10)
    If $IsObject(pRObj) {
        Set tLoc = $Select($IsObject(pRObj.Location): pRObj.Location.Name, 1: "")
        Set tL = tL _ "- Typhoon: " _ pRObj.Name _ " (type " _ pRObj.Type _ ", severity " _ pRObj.Severity _ "/10, wind " _ pRObj.WindSpeed _ " km/h, radius " _ pRObj.Radius _ " km)" _ $Char(10)
        Set tL = tL _ "- Area: " _ tLoc _ "; time window: " _ pRObj.StartTime _ " ~ " _ pRObj.EndTime _ $Char(10)
    }

    Set tL = tL _ "- Affected vessels:" _ $Char(10)
    Set tV = ""
    For {
        Set tV = $Order(pAffected(tV))
        Quit:tV=""
        Set tInfo = pAffected(tV)
        Set tVObj = ##class(Logistics.Transport.Vessel).%OpenId($ListGet(tV, 1))
        Set tVName = $Select($IsObject(tVObj): tVObj.Name, 1: "?")
        Set tWin = ##class(Logistics.Risk.Tools).secToTs($ListGet(tInfo, 2)) _ " ~ " _ ##class(Logistics.Risk.Tools).secToTs($ListGet(tInfo, 3))
        Set tL = tL _ "    - " _ tVName _ " (in typhoon segment, time window " _ tWin _ ")" _ $Char(10)
    }

    Set tL = tL _ "- Affected containers: " _ ..count(.pCont) _ "; affected shipments: " _ ..count(.pShip) _ $Char(10)
    Set tK = ""
    For { Set tK = $Order(pShip(tK))  Quit:tK=""
        Set tR = pShip(tK)
        Set tL = tL _ "    - Shipment " _ $Piece(tR, "|", 1) _ ": " _ $Piece(tR, "|", 2) _ " -> " _ $Piece(tR, "|", 3) _ " (" _ $Piece(tR, "|", 4) _ ")" _ $Char(10)
    }
    Set tL = tL _ "- Affected purchase orders:" _ $Char(10)
    Set tK = ""
    For { Set tK = $Order(pPO(tK))  Quit:tK=""
        Set tL = tL _ "    - " _ $Piece(pPO(tK), "|", 1) _ " (" _ $Piece(pPO(tK), "|", 2) _ ")" _ $Char(10)
    }
    Set tL = tL _ "- Affected customers:" _ $Char(10)
    Set tK = ""
    For { Set tK = $Order(pCust(tK))  Quit:tK=""
        Set tL = tL _ "    - " _ tK _ $Char(10)
    }
    Set tL = tL _ $Char(10) _ "Please provide risk-mitigation recommendations based on the above."
    Quit tL
}

/// Built-in rule-based recommendations (fallback when the LLM is unavailable)
ClassMethod fallback(ByRef pAffected, ByRef pShip, ByRef pPO, ByRef pCust)
{
    Set tV = ""
    For {
        Set tV = $Order(pAffected(tV))
        Quit:tV=""
        Set tVObj = ##class(Logistics.Transport.Vessel).%OpenId($ListGet(tV, 1))
        Set tVName = $Select($IsObject(tVObj): tVObj.Name, 1: "?")
        Do ..rec("high", "Vessel diversion / speed adjustment", "Vessel <b>" _ ..esc(tVName) _ "</b> will transit the affected segment within the typhoon time window. Recommend slowing to wait it out or diverting to an alternate route, avoiding the typhoon core.")
    }
    Set tK = ""
    For { Set tK = $Order(pShip(tK))  Quit:tK=""
        Do ..rec("mid", "Shipment alert and rescheduling", "Shipment <b>" _ ..esc($Piece(pShip(tK), "|", 1)) _ "</b> (" _ ..esc($Piece(pShip(tK), "|", 2)) _ " &#8594; " _ ..esc($Piece(pShip(tK), "|", 3)) _ ") is likely to be delayed. Recommend early alerting and re-planning the ETA.")
    }
    Set tK = ""
    For { Set tK = $Order(pPO(tK))  Quit:tK=""
        Do ..rec("mid", "Notify buyer and adjust delivery date", "Purchase order <b>" _ ..esc($Piece(pPO(tK), "|", 1)) _ "</b> delivery may be delayed. Recommend notifying the buyer early and renegotiating the delivery date.")
    }
    Set tK = ""
    For { Set tK = $Order(pCust(tK))  Quit:tK=""
        Do ..rec("low", "Customer communication", "Customer <b>" _ ..esc(tK) _ "</b> has orders involving affected cargo. Recommend proactively communicating the expected delay and offering alternatives.")
    }
}

/// Render a single recommendation
ClassMethod rec(pLevel As %String, pTitle As %String, pText As %String)
{
    Write "<div class='rec rec-", pLevel, "'>"
    Write "<div class='rec-title'>", ..esc(pTitle), "</div>"
    Write "<div class='rec-text'>", pText, "</div>"
    Write "</div>"
}

/// Render a KPI card
ClassMethod kpi(pTitle As %String, pValue As %Integer, pIcon As %String)
{
    Write "<div class='kpi'><div class='kpi-ico'>", pIcon, "</div><div class='kpi-num'>", +pValue, "</div><div class='kpi-lbl'>", ..esc(pTitle), "</div></div>"
}

/// Convert newlines to <br>
ClassMethod nl2br(pText As %String) As %String
{
    Quit $Replace($Replace(pText, $Char(13, 10), "<br>"), $Char(10), "<br>")
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
     _ ".alert{margin:20px 24px;background:#fff7ed;border:1px solid #fed7aa;border-left:5px solid #f97316;border-radius:12px;padding:16px 20px;display:flex;gap:16px;align-items:center}"
     _ ".alert-icon{font-size:32px}.alert-title{font-size:17px;font-weight:700;color:#9a3412}.alert-meta{color:#7c2d12;font-size:13px;margin-top:4px}"
     _ ".badge{font-size:12px;padding:2px 8px;border-radius:6px;background:#f97316;color:#fff;vertical-align:middle}"
     _ ".kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin:0 24px 20px}"
     _ ".kpi{background:#fff;border-radius:12px;padding:18px;box-shadow:0 1px 4px rgba(0,0,0,.06);display:flex;flex-direction:column;align-items:center}"
     _ ".kpi-ico{font-size:26px}.kpi-num{font-size:34px;font-weight:800;color:#1e293b;line-height:1.1}.kpi-lbl{color:#64748b;font-size:13px;margin-top:2px}"
     _ ".card{background:#fff;border-radius:14px;padding:20px 24px;margin:0 24px 20px;box-shadow:0 1px 6px rgba(0,0,0,.06)}"
     _ ".card h2{margin:0 0 10px;font-size:18px}.hint{color:#94a3b8;font-size:12px;font-weight:400}"
     _ ".map{width:100%}.mapsvg{width:100%;height:auto;display:block;background:#dbeafe;border:1px solid #cbd5e1;border-radius:10px}"
     _ ".map-cap{color:#94a3b8;font-size:12px;margin-top:8px}"
     _ ".grid{stroke:#bcd2ec;stroke-width:.5}"
     _ ".storm{fill:#ef4444;opacity:.10}.storm2{fill:#ef4444;opacity:.16}"
     _ ".storm-ico{font-size:24px;text-anchor:middle;dominant-baseline:central}"
     _ ".storm-lbl{font-size:13px;fill:#b91c1c;text-anchor:middle;font-weight:700}"
     _ ".mk{stroke:#fff;stroke-width:1.5}.mk-affected{fill:#ef4444}.mk-spatial{fill:#f59e0b}.mk-normal{fill:#64748b}"
     _ ".pulse{fill:#ef4444}"
     _ ".mk-lbl{font-size:11px;fill:#334155}.mk-lbl-affected{fill:#b91c1c;font-weight:700}.mk-lbl-spatial{fill:#b45309;font-weight:600}"
     _ ".tbl{width:100%;border-collapse:collapse;font-size:13px}.tbl th,.tbl td{text-align:left;padding:9px 12px;border-bottom:1px solid #eef2f7}.tbl th{color:#64748b;font-weight:600;background:#f8fafc}"
     _ ".tbl tr.hot td{background:#fef2f2}"
     _ ".grid3{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}"
     _ "@media(max-width:900px){.grid3{grid-template-columns:1fr}.kpis{grid-template-columns:repeat(2,1fr)}}"
     _ ".ent{background:#f8fafc;border:1px solid #eef2f7;border-radius:10px;padding:14px}"
     _ ".ent-h{font-weight:700;font-size:14px;margin-bottom:10px;color:#334155}"
     _ ".ent-row{padding:8px 0;border-bottom:1px dashed #e2e8f0;font-size:13px}.ent-row:last-child{border-bottom:none}"
     _ ".ent-row.cust{color:#7c3aed}.ent-sub{color:#94a3b8;font-size:12px;margin-top:2px}"
     _ ".tag{display:inline-block;background:#e0e7ff;color:#3730a3;border-radius:6px;padding:1px 7px;font-size:11px;margin-left:4px}"
     _ ".llm{white-space:normal;line-height:1.7;font-size:14px;color:#1e293b}"
     _ ".llm-note{background:#fffbeb;border:1px solid #fde68a;color:#92400e;border-radius:8px;padding:10px 12px;font-size:13px;margin-bottom:14px}"
     _ ".rec{border-left:4px solid #cbd5e1;background:#f8fafc;border-radius:8px;padding:12px 14px;margin-bottom:12px}"
     _ ".rec-title{font-weight:700;font-size:14px;margin-bottom:4px}.rec-text{font-size:13px;color:#475569;line-height:1.5}"
     _ ".rec-high{border-left-color:#ef4444;background:#fef2f2}.rec-mid{border-left-color:#f59e0b;background:#fffbeb}.rec-low{border-left-color:#10b981;background:#ecfdf5}"
     _ ".muted{color:#94a3b8}.foot{text-align:center;color:#94a3b8;font-size:12px;padding:16px 24px 30px}"
}

}
