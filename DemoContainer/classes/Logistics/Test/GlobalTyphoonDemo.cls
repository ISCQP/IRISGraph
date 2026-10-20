/// 大规模台风风险演示 · 复用现有 Logistics.UI.TyphoonDemo 页面（无需改动 UI）
/// Large-scale typhoon risk demo · reuses the existing Logistics.UI.TyphoonDemo page (no UI changes needed)
/// 
/// 目的：在不修改任何 UI 的前提下，生成「大规模」船舶/航线数据，验证时空判定
/// Purpose: without modifying any UI, generate "large-scale" vessel/route data to verify that the spatio-temporal decision
/// （Logistics.Risk.Tools.AnalyzeRisk：图遍历空间命中 + ETD 推算时间窗重叠）在
/// (Logistics.Risk.Tools.AnalyzeRisk: graph-traversal spatial hit + ETD-derived time-window overlap)
/// 大量船舶下依旧快速，同时让现有 TyphoonDemo 页面正常渲染地图/KPI/影响图。
/// stays fast under a large number of vessels, while the existing TyphoonDemo page still renders the map/KPI/impact graph correctly.
/// 
/// 数据契约（与 Logistics.Test.TyphoonDemo 完全一致，故页面开箱即用）：
/// Data contract (identical to Logistics.Test.TyphoonDemo, so the page works out of the box):
///   - ^LogiTyphoon("obj",Cls,Id)   —— 每个对象登记，供 Cleanup 统一清除；
///   - ^LogiTyphoon("obj",Cls,Id)   —— every object registered, for unified cleanup by Cleanup;
///   - ^LogiTyphoon("key","risk")    —— 台风 RiskEvent OID（页面据此分析渲染）；
///   - ^LogiTyphoon("key","risk")    —— typhoon RiskEvent OID (the page analyzes and renders from it);
///   - ^LogiTyphoon("key","region")  —— 台风覆盖区域 OID（台湾海峡）。
///   - ^LogiTyphoon("key","region")  —— typhoon coverage region OID (Taiwan Strait).
///   船舶须带 Latitude/Longitude（地图坐标，lon∈[8,140]、lat∈[-45,42]）。
///   Vessels must carry Latitude/Longitude (map coordinates, lon∈[8,140], lat∈[-45,42]).
/// 
/// 三类船（由 ETD 与航线精确控制）：
/// Three vessel classes (precisely controlled by ETD and route):
///   [affected 红] 走台湾海峡航线，ETD 使「过台湾海峡航段的时间窗」与台风窗口重叠
///   [affected, red] takes the Taiwan Strait route; ETD makes the "Taiwan Strait segment time window" overlap the typhoon window
///                 —— 进入 KPI、受影响清单与 vis 影响图（每船串一条业务链）；
///                 —— enters the KPI, affected list, and vis impact graph (each vessel chains one business chain);
///   [spatial 琥珀] 走台湾海峡航线，但 ETD 偏后 → 台风已过，空间命中但时间不重叠；
///   [spatial, amber] takes the Taiwan Strait route, but with a later ETD → the typhoon has passed; spatial hit but no time overlap;
///   [normal 灰]   走绕行好望角航线，空间上不经过台湾海峡。
///   [normal, gray]   takes the Cape of Good Hope detour route, spatially not passing through the Taiwan Strait.
/// 
/// 规模拆分（关键设计）：
/// Scale split (key design):
///   地图渲染「全部」船舶 → 船越多地图越密（默认总数适中，浏览器可用）；
///   the map renders "all" vessels → the more vessels, the denser the map (default total is moderate, browser usable);
///   vis 影响图只含 affected 船的业务链 ≈ pAffected × ~8 节点（默认约 200 节点）；
///   the vis impact graph contains only the affected vessels' business chains ≈ pAffected × ~8 nodes (default about 200 nodes);
///   时空分析引擎无论多少船都保持快速（本演示真正的看点）。
///   the spatio-temporal analysis engine stays fast regardless of vessel count (the real highlight of this demo).
/// 
/// 用法：
/// Usage:
///     Do ##class(Logistics.Test.GlobalTyphoonDemo).Setup()            // 默认 25/15/40
///     Do ##class(Logistics.Test.GlobalTyphoonDemo).Setup()            // Default 25/15/40
///     Do ##class(Logistics.Test.GlobalTyphoonDemo).Setup(40, 20, 80)  // affected/spatial/normal
///     然后打开（不要点页面「Rebuild demo data」，那会调用 TyphoonDemo 覆盖数据）：
///     Then open (do not click "Rebuild demo data" on the page, that calls TyphoonDemo and overwrites the data):
///         /csp/healthshare/nehr/Logistics.UI.TyphoonDemo.cls
///     Do ##class(Logistics.Test.GlobalTyphoonDemo).Cleanup()          // 清除本演示数据
///     Do ##class(Logistics.Test.GlobalTyphoonDemo).Cleanup()          // Remove this demo's data
/// Author: QP
/// Version: 1.0
Class Logistics.Test.GlobalTyphoonDemo Extends %RegisteredObject
{

/// 保存对象：登记到 ^LogiTyphoon 以便清理，返回 OID = $LB(Id, ClassName)
/// Save the object: register into ^LogiTyphoon for later cleanup, return OID = $LB(Id, ClassName)
ClassMethod save(pObj) As %List
{
    Set tSC = pObj.%Save()
    If $$$ISERR(tSC) $$$ThrowStatus(tSC)
    Set tCls = $ClassName(pObj), tId = pObj.%Id()
    Set ^LogiTyphoon("obj", tCls, tId) = ""
    Quit $ListBuild(tId, tCls)
}

/// 新建并保存一个 Location（可选经纬度）
/// Create and save a Location (optional latitude/longitude)
ClassMethod loc(pName As %String, pType As %String, pLat As %Numeric = "", pLon As %Numeric = "") As %RegisteredObject
{
    Set o = ##class(Logistics.Geography.Location).%New()
    Set o.Name = pName, o.Type = pType
    Set:pLat'="" o.Latitude = pLat
    Set:pLon'="" o.Longitude = pLon
    Do ..save(o)
    Quit o
}

/// 构造大规模数据：pAffected 受影响船、pSpatial 空间命中但时间已过、pNormal 绕行正常船
/// Build large-scale data: pAffected affected vessels, pSpatial spatial-hit-but-time-passed vessels, pNormal detouring normal vessels
ClassMethod Setup(pAffected As %Integer = 25, pSpatial As %Integer = 15, pNormal As %Integer = 40) As %Status
{
    Set tSC = $$$OK
    Try {
        // 复用 TyphoonDemo 的清理逻辑（同样登记在 ^LogiTyphoon）
        // Reuse TyphoonDemo's cleanup logic (also registered in ^LogiTyphoon)
        Do ##class(Logistics.Test.TyphoonDemo).Cleanup()
        Set tStart = $ZHorolog

        // ---------- 地理 Geography ----------
        // ---------- Geography ----------
        Set taiwanStrait = ..loc("Taiwan Strait", "SeaArea", 24.5, 119.5)
        Set eastChinaSea = ..loc("East China Sea", "SeaArea")
        Set southChinaSea = ..loc("South China Sea", "SeaArea")
        Set cape = ..loc("Cape of Good Hope", "SeaArea")
        Set shanghai = ..loc("Shanghai Port", "Port")
        Set singapore = ..loc("Singapore Port", "Port")
        Set rotterdam = ..loc("Rotterdam Port", "Port")
        Set busan = ..loc("Busan Port", "Port")
        Set kaohsiung = ..loc("Kaohsiung Port", "Port")
        Set hongkong = ..loc("Hong Kong Port", "Port")
        Set tNPort = 6
        Set tPort(1) = shanghai, tPort(2) = singapore, tPort(3) = rotterdam
        Set tPort(4) = busan, tPort(5) = kaohsiung, tPort(6) = hongkong

        // ---------- 航线 R-TWX-01：经台湾海峡（3 段有序）----------
        // ---------- Route R-TWX-01: via the Taiwan Strait (3 ordered segments) ----------
        Set routeTW = ##class(Logistics.Route.Route).%New(), routeTW.RouteID = "R-TWX-01", routeTW.RouteName = "Asia-Europe via Taiwan Strait"
        Do ..save(routeTW)
        Set seg1 = ##class(Logistics.Route.RouteSegment).%New()
        Set seg1.SegmentID = "SEG-ECS", seg1.Name = "East China Sea Leg", seg1.Sequence = 1, seg1.ExpectedDuration = 24, seg1.Route = routeTW, seg1.StartLocation = shanghai, seg1.EndLocation = taiwanStrait
        Do seg1.PassesThrough.Insert(shanghai), seg1.PassesThrough.Insert(eastChinaSea)
        Do ..save(seg1)
        Set segTW = ##class(Logistics.Route.RouteSegment).%New()
        Set segTW.SegmentID = "SEG-TWS", segTW.Name = "Taiwan Strait Leg", segTW.Sequence = 2, segTW.ExpectedDuration = 18, segTW.Route = routeTW, segTW.StartLocation = taiwanStrait, segTW.EndLocation = southChinaSea
        Do segTW.PassesThrough.Insert(taiwanStrait)
        Do ..save(segTW)
        Set seg3 = ##class(Logistics.Route.RouteSegment).%New()
        Set seg3.SegmentID = "SEG-SCS", seg3.Name = "South China Sea Leg", seg3.Sequence = 3, seg3.ExpectedDuration = 30, seg3.Route = routeTW, seg3.StartLocation = southChinaSea, seg3.EndLocation = singapore
        Do seg3.PassesThrough.Insert(southChinaSea), seg3.PassesThrough.Insert(singapore)
        Do ..save(seg3)

        // ---------- 航线 R-CAPE-01：绕行好望角（空间对照，不经台湾海峡）----------
        // ---------- Route R-CAPE-01: Cape of Good Hope detour (spatial control, not via the Taiwan Strait) ----------
        Set routeCape = ##class(Logistics.Route.Route).%New(), routeCape.RouteID = "R-CAPE-01", routeCape.RouteName = "Asia-Europe via Cape"
        Do ..save(routeCape)
        Set segC = ##class(Logistics.Route.RouteSegment).%New()
        Set segC.SegmentID = "SEG-CAPE", segC.Name = "Cape Leg", segC.Sequence = 1, segC.ExpectedDuration = 40, segC.Route = routeCape, segC.StartLocation = cape, segC.EndLocation = cape
        Do segC.PassesThrough.Insert(cape)
        Do ..save(segC)

        // ---------- 商品 / 客户池（受影响业务链复用）----------
        // ---------- Product / Customer pool (reused by the affected business chains) ----------
        Set tNProd = 6
        For i = 1:1:tNProd {
            Set p = ##class(Logistics.Business.Product).%New()
            Set p.SKU = "SKU-"_i, p.Name = "Cargo "_i
            Do ..save(p)
            Set tProd(i) = p
        }
        Set tCustList = $ListBuild("ACME Retail GmbH", "Nordic Traders AB", "Pacific Imports Ltd", "Sahara Foods LLC", "Alpine Electronics", "Maple Distributors", "Orient Textiles", "Bavaria Motors")
        Set tNCust = $ListLength(tCustList)

        // ---------- 台风 RiskEvent（区域 + 48h 时间窗）----------
        // ---------- Typhoon RiskEvent (region + 48h time window) ----------
        Set typhoon = ##class(Logistics.Risk.RiskEvent).%New()
        Set typhoon.Name = "Typhoon Muifa 2026", typhoon.Type = "Typhoon", typhoon.Severity = 8, typhoon.Radius = 350, typhoon.WindSpeed = 200
        Set typhoon.Forecast = "48h typhoon over the Taiwan Strait"
        Set typhoon.Location = taiwanStrait
        Set typhoon.StartTime = "2026-08-10 12:00:00", typhoon.EndTime = "2026-08-12 12:00:00"
        Do ..save(typhoon)

        // 过台湾海峡航段的时间窗 = ETD + 24h(前序 ECS) ~ + 42h。据此选 ETD 命中/避开台风窗口。
        // Taiwan Strait segment time window = ETD + 24h (preceding ECS) ~ + 42h. ETD is chosen accordingly to hit/avoid the typhoon window.
        Set affS0 = ##class(Logistics.Risk.Tools).tsToSec("2026-08-09 06:00:00")
        Set affS1 = ##class(Logistics.Risk.Tools).tsToSec("2026-08-11 00:00:00")
        Set spS0 = ##class(Logistics.Risk.Tools).tsToSec("2026-08-14 00:00:00")
        Set spS1 = ##class(Logistics.Risk.Tools).tsToSec("2026-08-19 00:00:00")

        // ---------- 受影响船（红）：台湾海峡航线 + ETD 命中台风窗 + 业务链 ----------
        // ---------- Affected vessels (red): Taiwan Strait route + ETD hitting the typhoon window + business chain ----------
        For i = 1:1:pAffected {
            Set v = ##class(Logistics.Transport.Vessel).%New()
            Set v.AssetID = "V-A"_i, v.Name = "MV Affected "_i, v.IMO = "IMOA"_i, v.CurrentLocation = taiwanStrait
            Set v.Latitude = 22 + ($Random(50)/10), v.Longitude = 118 + ($Random(40)/10)
            Do ..save(v)
            Set vy = ##class(Logistics.Route.Voyage).%New()
            Set vy.VoyageNo = "VT-A"_i, vy.Carrier = "GlobalLine", vy.Vessel = v, vy.Route = routeTW
            Set vy.ETD = ##class(Logistics.Risk.Tools).secToTs(affS0 + $Random(affS1 - affS0))
            Do ..save(vy)
            Set pi = ($Random(tNProd)) + 1
            Set shp = ##class(Logistics.Transport.Shipment).%New()
            Set shp.ShipmentNo = "SHP-A"_i, shp.Mode = "Sea", shp.Origin = tPort($Random(tNPort)+1), shp.Destination = rotterdam, shp.Status = "InTransit"
            Do ..save(shp)
            Set c1 = ##class(Logistics.Asset.Container).%New()
            Set c1.ContainerNo = "CTA"_i_"A", c1.ISOCode = "45G1", c1.Status = "Laden", c1.CurrentTransport = v, c1.Shipment = shp
            Do ..save(c1)
            Set c2 = ##class(Logistics.Asset.Container).%New()
            Set c2.ContainerNo = "CTA"_i_"B", c2.ISOCode = "22G1", c2.Status = "Laden", c2.CurrentTransport = v, c2.Shipment = shp
            Do ..save(c2)
            Set po = ##class(Logistics.Business.PurchaseOrder).%New()
            Set po.PONumber = "PO-A"_i, po.Status = "Open", po.Shipment = shp
            Do po.Products.Insert(tProd(pi))
            Do ..save(po)
            Set so = ##class(Logistics.Business.SalesOrder).%New()
            Set so.SONumber = "SO-A"_i, so.Customer = $ListGet(tCustList, ($Random(tNCust))+1), so.Status = "Confirmed"
            Do so.Products.Insert(tProd(pi))
            Do ..save(so)
        }

        // ---------- 空间命中但时间已过（琥珀）：台湾海峡航线 + ETD 偏后 ----------
        // ---------- Spatial hit but time passed (amber): Taiwan Strait route + later ETD ----------
        For i = 1:1:pSpatial {
            Set v = ##class(Logistics.Transport.Vessel).%New()
            Set v.AssetID = "V-S"_i, v.Name = "MV Clear "_i, v.IMO = "IMOS"_i, v.CurrentLocation = shanghai
            Set v.Latitude = 10 + ($Random(220)/10), v.Longitude = 110 + ($Random(150)/10)
            Do ..save(v)
            Set vy = ##class(Logistics.Route.Voyage).%New()
            Set vy.VoyageNo = "VT-S"_i, vy.Carrier = "GlobalLine", vy.Vessel = v, vy.Route = routeTW
            Set vy.ETD = ##class(Logistics.Risk.Tools).secToTs(spS0 + $Random(spS1 - spS0))
            Do ..save(vy)
        }

        // ---------- 绕行正常船（灰）：好望角航线，空间不经台湾海峡 ----------
        // ---------- Detouring normal vessels (gray): Cape route, spatially not via the Taiwan Strait ----------
        For i = 1:1:pNormal {
            Set v = ##class(Logistics.Transport.Vessel).%New()
            Set v.AssetID = "V-N"_i, v.Name = "MV Normal "_i, v.IMO = "IMON"_i, v.CurrentLocation = cape
            Set v.Latitude = -35 + ($Random(650)/10), v.Longitude = 20 + ($Random(950)/10)
            Do ..save(v)
            Set vy = ##class(Logistics.Route.Voyage).%New()
            Set vy.VoyageNo = "VT-N"_i, vy.Carrier = "CapeLine", vy.Vessel = v, vy.Route = routeCape
            Set vy.ETD = ##class(Logistics.Risk.Tools).secToTs(affS0 + $Random(spS1 - affS0))
            Do ..save(vy)
        }

        // ---------- 写入 UI 契约键 ----------
        // ---------- Write the UI contract keys ----------
        Set ^LogiTyphoon("key", "risk") = $ListBuild(typhoon.%Id(), $ClassName(typhoon))
        Set ^LogiTyphoon("key", "region") = $ListBuild(taiwanStrait.%Id(), $ClassName(taiwanStrait))

        Set tElapsed = $ZHorolog - tStart
        Set tTotal = pAffected + pSpatial + pNormal
        Write "GlobalTyphoonDemo 构造完成：船舶总数 ", tTotal, "（受影响 ", pAffected, " / 空间命中时间已过 ", pSpatial, " / 正常 ", pNormal, "），耗时 ", $FNumber(tElapsed, "", 2), " 秒。", !
        Write "打开 UI（不要点 Rebuild demo data）：/csp/healthshare/nehr/Logistics.UI.TyphoonDemo.cls", !
    }
    Catch ex {
        Set tSC = ex.AsStatus()
        Write !, "GlobalTyphoonDemo.Setup 异常: ", $System.Status.GetOneErrorText(tSC), !
    }
    Quit tSC
}

/// 清除本演示创建的所有数据（复用 TyphoonDemo 的清理逻辑）
/// Remove all data created by this demo (reuses TyphoonDemo's cleanup logic)
ClassMethod Cleanup() As %Status
{
    Quit ##class(Logistics.Test.TyphoonDemo).Cleanup()
}

}
