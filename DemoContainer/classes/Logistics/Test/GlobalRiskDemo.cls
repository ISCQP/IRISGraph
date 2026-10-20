/// 全球大规模航运风险演示 · 复用现有 Logistics.UI.RiskDemo 页面（无需改动 UI）
/// Global large-scale shipping risk demo · reuses the existing Logistics.UI.RiskDemo page (no UI changes needed)
/// 
/// 目的：在不修改任何 UI 的前提下，生成「大规模」物流图数据，验证图查询引擎
/// Purpose: without modifying any UI, generate "large-scale" logistics graph data to verify that the graph query engine
/// （Graph.Tools 的 SingleHop / MultiHop / BFS）在成千上万个节点/边规模下依旧
/// (Graph.Tools' SingleHop / MultiHop / BFS) stays fast at the scale of tens of thousands of nodes/edges,
/// 快速，同时让现有 RiskDemo 页面正常渲染 KPI 与影响子图。
/// while the existing RiskDemo page still renders the KPIs and impact subgraph correctly.
/// 
/// 数据契约（与 PersianGulfDemo 完全一致，故 RiskDemo 页面开箱即用）：
/// Data contract (identical to PersianGulfDemo, so the RiskDemo page works out of the box):
///   - ^LogiDemo("obj",Cls,Id)   —— 每个对象登记，供 Cleanup 统一清除；
///   - ^LogiDemo("obj",Cls,Id)   —— every object registered, for unified cleanup by Cleanup;
///   - ^LogiDemo("key","risk")    —— 触发态风险 OID（页面据此渲染影响态）；
///   - ^LogiDemo("key","risk")    —— triggered-state risk OID (the page renders the impact state from it);
///   - ^LogiDemo("key","segment") —— 关键航段 OID（页面反向多跳统计途经货运）。
///   - ^LogiDemo("key","segment") —— key segment OID (the page reverse-multi-hops to count transiting shipments).
/// 
/// 规模拆分（关键设计）：
/// Scale split (key design):
///   RiskDemo 的影响子图用 BFS(risk,8) 把「可达」节点全部推入 vis-network，且不截断。
///   RiskDemo's impact subgraph uses BFS(risk,8) to push all "reachable" nodes into vis-network, without truncation.
///   因此把数据分成两部分，locations 互不相交，避免受影响子图无限膨胀：
///   Therefore the data is split into two parts with disjoint locations, to prevent the affected subgraph from growing without bound:
///     [受影响] pAffected 条货运，经风险咽喉航段（Malacca），每条各生成一个 Impact，
///     [affected] pAffected shipments passing through the risk chokepoint segment (Malacca), each generating one Impact,
///              串联 Vessel/Voyage/Container/PO/Supplier/Product —— 这部分进入 vis 图；
///              chained through Vessel/Voyage/Container/PO/Supplier/Product —— this part enters the vis graph;
///     [对照]   pShipments-pAffected 条货运，经绕行航线（Cape），独立港口/供应商，
///     [control] pShipments-pAffected shipments via the detour route (Cape), with independent ports/suppliers,
///              不与风险相连 —— 只贡献引擎规模，不进入 vis 图。
///              not connected to the risk —— they only contribute engine scale and do not enter the vis graph.
///   => vis 图规模 ≈ pAffected，KPI 与引擎规模 ≈ pShipments。默认让浏览器可用，
///   => vis graph size ≈ pAffected, while KPI and engine scale ≈ pShipments. Defaults keep the browser usable,
///      而引擎查询无论多大都保持快速（本演示真正的看点）。
///      while engine queries stay fast at any size (the real highlight of this demo).
/// 
/// 用法：
/// Usage:
///     Do ##class(Logistics.Test.GlobalRiskDemo).Setup()          // 默认 300 货运 / 30 受影响
///     Do ##class(Logistics.Test.GlobalRiskDemo).Setup()          // Default 300 shipments / 30 affected
///     Do ##class(Logistics.Test.GlobalRiskDemo).Setup(1000, 40)  // 自定义规模（受影响数越大 vis 图越大）
///     Do ##class(Logistics.Test.GlobalRiskDemo).Setup(1000, 40)  // Custom scale (the larger the affected count, the larger the vis graph)
///     然后打开（不要带 ?action 参数，否则会调用 PersianGulfDemo 覆盖数据）：
///     Then open (do not pass the ?action parameter, otherwise PersianGulfDemo will be called and overwrite the data):
///         /csp/healthshare/nehr/Logistics.UI.RiskDemo.cls
///     Do ##class(Logistics.Test.GlobalRiskDemo).Cleanup()        // 清除本演示数据
///     Do ##class(Logistics.Test.GlobalRiskDemo).Cleanup()        // Remove this demo's data
/// 
/// 注意：UI 上的「触发风险 / 重置」按钮会调用 PersianGulfDemo，从而覆盖本演示数据；
/// Note: the "trigger risk / reset" buttons in the UI call PersianGulfDemo and thus overwrite this demo's data;
///       若要重看本演示，重新运行 Setup() 即可。
///       to view this demo again, simply re-run Setup().
/// Author: QP
/// Version: 1.0
Class Logistics.Test.GlobalRiskDemo Extends %RegisteredObject
{

/// 保存对象：登记到 ^LogiDemo 以便清理，返回 OID = $LB(Id, ClassName)
/// Save the object: register into ^LogiDemo for later cleanup, return OID = $LB(Id, ClassName)
ClassMethod save(pObj) As %List
{
    Set tSC = pObj.%Save()
    If $$$ISERR(tSC) $$$ThrowStatus(tSC)
    Set tCls = $ClassName(pObj), tId = pObj.%Id()
    Set ^LogiDemo("obj", tCls, tId) = ""
    Quit $ListBuild(tId, tCls)
}

/// 新建并保存一个 Location
/// Create and save a Location
ClassMethod loc(pName As %String, pType As %String) As %RegisteredObject
{
    Set o = ##class(Logistics.Geography.Location).%New()
    Set o.Name = pName, o.Type = pType
    Do ..save(o)
    Quit o
}

/// 构造大规模数据：pShipments 总货运数，pAffected 经风险咽喉的受影响货运数
/// Build large-scale data: pShipments total shipments, pAffected shipments through the risk chokepoint that are affected
ClassMethod Setup(pShipments As %Integer = 300, pAffected As %Integer = 30) As %Status
{
    Set tSC = $$$OK
    Try {
        // 复用 PersianGulfDemo 的清理逻辑（同样登记在 ^LogiDemo）
        // Reuse PersianGulfDemo's cleanup logic (also registered in ^LogiDemo)
        Do ##class(Logistics.Test.PersianGulfDemo).Cleanup()
        Set:pAffected>pShipments pAffected = pShipments
        Set tStart = $ZHorolog

        // ---------- 咽喉点 Chokepoints ----------
        // ---------- Chokepoints ----------
        Set choke = ..loc("Strait of Malacca", "SeaArea")
        Set altChoke = ..loc("Cape of Good Hope", "SeaArea")

        // ---------- 港口（受影响侧 / 对照侧互不相交）----------
        // ---------- Ports (affected side / control side are disjoint) ----------
        Set aPortNames = $ListBuild("Shanghai Port", "Singapore Port", "Port Klang", "Rotterdam Port", "Hamburg Port")
        Set cPortNames = $ListBuild("Los Angeles Port", "Busan Port", "Santos Port", "Mumbai Port", "Long Beach Port")
        Set nA = $ListLength(aPortNames), nC = $ListLength(cPortNames)
        For i = 1:1:nA { Set aPort(i) = ..loc($ListGet(aPortNames, i), "Port") }
        For i = 1:1:nC { Set cPort(i) = ..loc($ListGet(cPortNames, i), "Port") }

        // ---------- 政策 / 供应商 / 商品池（受影响侧）----------
        // ---------- Policy / Supplier / Product pool (affected side) ----------
        Set hs = ##class(Logistics.Policy.HSCode).%New(), hs.Code = "8542", hs.Description = "Electronic integrated circuits"
        Do ..save(hs)
        Set nSup = 8
        For i = 1:1:nSup {
            Set s = ##class(Logistics.Business.Supplier).%New()
            Set s.SupplierCode = "SUP-"_i, s.Name = "Supplier "_i, s.Tier = (i#3)+1, s.Industry = "Electronics", s.RiskScore = ($Random(60)+20)/100
            Do ..save(s)
            Set supObj(i) = s
            Set p = ##class(Logistics.Business.Product).%New()
            Set p.SKU = "SKU-"_i, p.Name = "Component "_i, p.HSCode = hs, p.Supplier = s
            Do ..save(p)
            Set prodObj(i) = p
        }

        // ---------- 航线 Routes ----------
        // ---------- Routes ----------
        Set riskRoute = ##class(Logistics.Route.Route).%New(), riskRoute.RouteID = "R-MALACCA", riskRoute.RouteName = "Asia-Europe via Malacca"
        Do ..save(riskRoute)
        Set altRoute = ##class(Logistics.Route.Route).%New(), altRoute.RouteID = "R-CAPE", altRoute.RouteName = "Asia-Europe via Cape"
        Do ..save(altRoute)

        // ---------- 航段 Segments（风险航线全部途经咽喉）----------
        // ---------- Segments (all risk-route segments pass through the chokepoint) ----------
        Set seg1 = ##class(Logistics.Route.RouteSegment).%New()
        Set seg1.SegmentID = "SEG-MAL-1", seg1.Name = "Malacca Strait Segment", seg1.Route = riskRoute, seg1.StartLocation = aPort(1), seg1.EndLocation = choke
        Do seg1.PassesThrough.Insert(choke)
        Do ..save(seg1)
        Set seg2 = ##class(Logistics.Route.RouteSegment).%New()
        Set seg2.SegmentID = "SEG-MAL-2", seg2.Name = "Malacca Approach Segment", seg2.Route = riskRoute, seg2.StartLocation = choke, seg2.EndLocation = aPort(4)
        Do seg2.PassesThrough.Insert(choke)
        Do ..save(seg2)
        Set segC = ##class(Logistics.Route.RouteSegment).%New()
        Set segC.SegmentID = "SEG-CAPE", segC.Name = "Cape Segment", segC.Route = altRoute, segC.StartLocation = altChoke, segC.EndLocation = altChoke
        Do segC.PassesThrough.Insert(altChoke)
        Do ..save(segC)

        // ---------- 风险事件 RiskEvent ----------
        // ---------- RiskEvent ----------
        Set risk = ##class(Logistics.Risk.RiskEvent).%New()
        Set risk.Name = "Malacca Strait Crisis 2026", risk.Type = "War", risk.Severity = 9, risk.Forecast = "Strait blockade disrupting the Asia-Europe lane for weeks"
        Set risk.Location = choke
        Do risk.AffectedSegments.Insert(seg1)
        Do risk.AffectedSegments.Insert(seg2)
        Do ..save(risk)

        Set ri1 = ##class(Logistics.Risk.RouteImpact).%New(), ri1.RiskEvent = risk, ri1.RouteSegment = seg1, ri1.Severity = 9
        Do ..save(ri1)
        Set ri2 = ##class(Logistics.Risk.RouteImpact).%New(), ri2.RiskEvent = risk, ri2.RouteSegment = seg2, ri2.Severity = 7
        Do ..save(ri2)

        // ---------- 受影响货运（途经咽喉）+ 每条一个 Impact ----------
        // ---------- Affected shipments (transiting the chokepoint) + one Impact each ----------
        Set firstShp = "", firstPO = "", firstSup = ""
        For i = 1:1:pAffected {
            Set v = ##class(Logistics.Transport.Vessel).%New()
            Set v.AssetID = "V-A"_i, v.Name = "MV Affected "_i, v.IMO = "IMOA"_i, v.CurrentLocation = choke
            Do ..save(v)
            Set vy = ##class(Logistics.Route.Voyage).%New()
            Set vy.VoyageNo = "VY-A"_i, vy.Carrier = "GlobalLine", vy.Vessel = v, vy.Route = riskRoute
            Do ..save(vy)
            Set shp = ##class(Logistics.Transport.Shipment).%New()
            Set shp.ShipmentNo = "SHP-A"_i, shp.Mode = "Sea", shp.Origin = aPort($Random(nA)+1), shp.Destination = aPort($Random(nA)+1), shp.Status = "InTransit"
            Do ..save(shp)
            Set ct = ##class(Logistics.Asset.Container).%New()
            Set ct.ContainerNo = "CT-A"_i, ct.ISOCode = "42G1", ct.Shipment = shp, ct.CurrentTransport = v
            Do ..save(ct)
            Set si = (i # nSup) + 1
            Set po = ##class(Logistics.Business.PurchaseOrder).%New()
            Set po.PONumber = "PO-A"_i, po.Status = "Open", po.Shipment = shp
            Do po.Products.Insert(prodObj(si))
            Do ..save(po)
            Set imp = ##class(Logistics.Impact.Impact).%New()
            Set imp.Type = "Delay", imp.DelayHours = 48 + $Random(200), imp.Probability = (50 + $Random(50))/100, imp.Severity = 5 + $Random(5)
            Set imp.Description = "Malacca disruption delays shipment SHP-A"_i
            Set imp.Cause = risk, imp.AffectedShipment = shp, imp.AffectedPO = po, imp.AffectedSupplier = supObj(si)
            Do ..save(imp)
            If i = 1 {
                Set firstShp = $ListBuild(shp.%Id(), $ClassName(shp))
                Set firstPO = $ListBuild(po.%Id(), $ClassName(po))
                Set firstSup = $ListBuild(supObj(si).%Id(), $ClassName(supObj(si)))
            }
        }

        // ---------- 对照货运（绕行 Cape，港口/供应商互不相交，不与风险相连）----------
        // ---------- Control shipments (detour via Cape, disjoint ports/suppliers, not connected to the risk) ----------
        Set tControl = pShipments - pAffected
        For i = 1:1:tControl {
            Set v = ##class(Logistics.Transport.Vessel).%New()
            Set v.AssetID = "V-C"_i, v.Name = "MV Control "_i, v.IMO = "IMOC"_i, v.CurrentLocation = altChoke
            Do ..save(v)
            Set vy = ##class(Logistics.Route.Voyage).%New()
            Set vy.VoyageNo = "VY-C"_i, vy.Carrier = "CapeLine", vy.Vessel = v, vy.Route = altRoute
            Do ..save(vy)
            Set shp = ##class(Logistics.Transport.Shipment).%New()
            Set shp.ShipmentNo = "SHP-C"_i, shp.Mode = "Sea", shp.Origin = cPort($Random(nC)+1), shp.Destination = cPort($Random(nC)+1), shp.Status = "InTransit"
            Do ..save(shp)
            Set ct = ##class(Logistics.Asset.Container).%New()
            Set ct.ContainerNo = "CT-C"_i, ct.ISOCode = "42G1", ct.Shipment = shp, ct.CurrentTransport = v
            Do ..save(ct)
        }

        // ---------- 写入 UI 契约键 ----------
        // ---------- Write the UI contract keys ----------
        Set ^LogiDemo("key", "segment") = $ListBuild(seg1.%Id(), $ClassName(seg1))
        Set ^LogiDemo("key", "risk") = $ListBuild(risk.%Id(), $ClassName(risk))
        Set:firstShp'="" ^LogiDemo("key", "shipment") = firstShp
        Set:firstPO'="" ^LogiDemo("key", "po") = firstPO
        Set:firstSup'="" ^LogiDemo("key", "supplier") = firstSup

        Set tElapsed = $ZHorolog - tStart
        Write "GlobalRiskDemo 构造完成：总货运 ", pShipments, "（受影响 ", pAffected, " / 对照 ", tControl, "），耗时 ", $FNumber(tElapsed, "", 2), " 秒。", !
        Write "打开 UI（不要带 ?action 参数）：/csp/healthshare/nehr/Logistics.UI.RiskDemo.cls", !
    }
    Catch ex {
        Set tSC = ex.AsStatus()
        Write !, "GlobalRiskDemo.Setup 异常: ", $System.Status.GetOneErrorText(tSC), !
    }
    Quit tSC
}

/// 清除本演示创建的所有数据（复用 PersianGulfDemo 的清理逻辑）
/// Remove all data created by this demo (reuses PersianGulfDemo's cleanup logic)
ClassMethod Cleanup() As %Status
{
    Quit ##class(Logistics.Test.PersianGulfDemo).Cleanup()
}

}
