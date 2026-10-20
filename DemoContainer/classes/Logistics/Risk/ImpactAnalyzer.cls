/// 风险业务影响分析 · 承接 Logistics.Risk.Tools.AnalyzeRisk 的下游。
/// Risk business-impact analysis · downstream of Logistics.Risk.Tools.AnalyzeRisk.
/// 
/// AnalyzeRisk 回答「哪些船受影响」；本类回答「受影响的船进一步波及了哪些业务实体」，
/// AnalyzeRisk answers "which vessels are affected"; this class answers "which business entities the affected vessels further impact",
/// 并构造「风险影响子图」的抽象表示（OID 节点 + 关系边），供 UI 层转成可视化格式。
/// and builds an abstract representation of the "risk impact subgraph" (OID nodes + relationship edges), for the UI layer to convert into a visualization format.
/// 
/// 物流业务链图追踪：
/// Logistics business-chain graph traversal:
///   Vessel <-loaded_on- Container <-contains- Shipment <-fulfilled_by- PurchaseOrder
///       -po_contains_product-> Product <-so_contains_product- SalesOrder(.Customer)
/// Author: QP
/// Version: 1.0
Class Logistics.Risk.ImpactAnalyzer Extends %RegisteredObject
{

/// 一站式风险影响分析：一次调用完成 空间+时间受影响船 → 业务实体 → 影响子图。
/// One-stop risk impact analysis: a single call performs spatial+temporal affected vessels → business entities → impact subgraph.
///   pRiskOID                风险事件 OID = $LB(Id, ClassName)
///   pRiskOID                risk event OID = $LB(Id, ClassName)
///   pSpatial / pAffected    同 Logistics.Risk.Tools.AnalyzeRisk
///   pSpatial / pAffected    same as Logistics.Risk.Tools.AnalyzeRisk
///   pCont/pShip/pPO/pCust    同 CollectBusiness（集装箱/货运/采购单/客户）
///   pCont/pShip/pPO/pCust    same as CollectBusiness (container/shipment/purchase order/customer)
///   pNodes/pEdges            同 ImpactGraph（影响子图抽象节点/边）
///   pNodes/pEdges            same as ImpactGraph (impact subgraph abstract nodes/edges)
ClassMethod Analyze(pRiskOID As %List, Output pSpatial, Output pAffected, Output pCont, Output pShip, Output pPO, Output pCust, Output pNodes, Output pEdges) As %Status
{
    Kill pSpatial, pAffected, pCont, pShip, pPO, pCust, pNodes, pEdges
    Set tSC = ##class(Logistics.Risk.Tools).AnalyzeRisk(pRiskOID, .pSpatial, .pAffected)
    Quit:$$$ISERR(tSC) tSC
    Do ..CollectBusiness(.pAffected, .pCont, .pShip, .pPO, .pCust)
    Do ..ImpactGraph(pRiskOID, .pAffected, .pNodes, .pEdges)
    Quit $$$OK
}

/// 节点 key：OID($LB(Id,Class)) -> "Id~Class"
/// Node key: OID($LB(Id,Class)) -> "Id~Class"
ClassMethod NodeKey(pOID As %List) As %String
{
    Quit $ListGet(pOID, 1) _ "~" _ $ListGet(pOID, 2)
}

/// 从受影响船舶出发，收集受影响的业务实体
/// Starting from the affected vessels, collect the affected business entities
///   pCont(containerId) = ContainerNo|ISO|Status|VesselName
///   pShip(shipmentId)  = ShipmentNo|Origin|Destination|Status
///   pPO(poId)          = PONumber|Status
///   pCust(customerName)= ""
ClassMethod CollectBusiness(ByRef pAffected, Output pCont, Output pShip, Output pPO, Output pCust)
{
    Kill pCont, pShip, pPO, pCust
    Set tV = ""
    For {
        Set tV = $Order(pAffected(tV))
        Quit:tV=""
        Set tVObj = ##class(Logistics.Transport.Vessel).%OpenId($ListGet(tV, 1))
        Set tVName = $Select($IsObject(tVObj): tVObj.Name, 1: "?")

        // Vessel <-loaded_on- Container
        Do ##class(Graph.Tools).SingleHop(tV, "loaded_on", 1, .rC)
        For i = 1:1:rC.%Size() {
            Set cOID = rC.%Get(i - 1).OID
            Set cId = $ListGet(cOID, 1)
            Set cObj = ##class(Logistics.Asset.Container).%OpenId(cId)
            If $IsObject(cObj) {
                Set:'$Data(pCont(cId)) pCont(cId) = cObj.ContainerNo _ "|" _ cObj.ISOCode _ "|" _ cObj.Status _ "|" _ tVName
            }

            // Container <-contains- Shipment
            Do ##class(Graph.Tools).SingleHop(cOID, "contains", 1, .rS)
            For j = 1:1:rS.%Size() {
                Set sOID = rS.%Get(j - 1).OID
                Set sId = $ListGet(sOID, 1)
                Set sObj = ##class(Logistics.Transport.Shipment).%OpenId(sId)
                If $IsObject(sObj), '$Data(pShip(sId)) {
                    Set tOrig = $Select($IsObject(sObj.Origin): sObj.Origin.Name, 1: "")
                    Set tDest = $Select($IsObject(sObj.Destination): sObj.Destination.Name, 1: "")
                    Set pShip(sId) = sObj.ShipmentNo _ "|" _ tOrig _ "|" _ tDest _ "|" _ sObj.Status
                }

                // Shipment <-fulfilled_by- PurchaseOrder
                Do ##class(Graph.Tools).SingleHop(sOID, "fulfilled_by", 1, .rP)
                For k = 1:1:rP.%Size() {
                    Set poOID = rP.%Get(k - 1).OID
                    Set poId = $ListGet(poOID, 1)
                    Set poObj = ##class(Logistics.Business.PurchaseOrder).%OpenId(poId)
                    If $IsObject(poObj), '$Data(pPO(poId)) {
                        Set pPO(poId) = poObj.PONumber _ "|" _ poObj.Status
                    }

                    // PurchaseOrder -po_contains_product-> Product
                    Do ##class(Graph.Tools).SingleHop(poOID, "po_contains_product", 0, .rPr)
                    For m = 1:1:rPr.%Size() {
                        Set prOID = rPr.%Get(m - 1).TargetOID

                        // Product <-so_contains_product- SalesOrder(.Customer)
                        Do ##class(Graph.Tools).SingleHop(prOID, "so_contains_product", 1, .rSo)
                        For n = 1:1:rSo.%Size() {
                            Set soOID = rSo.%Get(n - 1).OID
                            Set soObj = ##class(Logistics.Business.SalesOrder).%OpenId($ListGet(soOID, 1))
                            If $IsObject(soObj), (soObj.Customer '= "") {
                                Set pCust(soObj.Customer) = ""
                            }
                        }
                    }
                }
            }
        }
    }
}

/// 某船的航路/航次摘要（船 -assigned_to-> 航次 -uses-> 航路）
/// Route/voyage summary of a vessel (vessel -assigned_to-> voyage -uses-> route)
ClassMethod RouteInfo(pVesOID As %List) As %String
{
    Do ##class(Graph.Tools).SingleHop(pVesOID, "assigned_to", 0, .tR)
    Quit:tR.%Size()=0 ""
    Set tVoy = ##class(Logistics.Route.Voyage).%OpenId($ListGet(tR.%Get(0).TargetOID, 1))
    Quit:'$IsObject(tVoy) ""
    Set tTxt = ""
    If $IsObject(tVoy.Route) {
        Set tTxt = tVoy.Route.RouteID
        Set:tVoy.Route.RouteName'="" tTxt = tTxt _ " " _ tVoy.Route.RouteName
    }
    Set tTxt = tTxt _ " (Voyage " _ tVoy.VoyageNo
    Set:tVoy.ETD'="" tTxt = tTxt _ ", ETD " _ tVoy.ETD
    Set tTxt = tTxt _ ")"
    Quit $ZStrip(tTxt, "<W")
}

/// 构造风险影响子图（抽象表示，OID 节点 + 关系边；不含任何可视化格式）
/// Build the risk impact subgraph (abstract representation, OID nodes + relationship edges; contains no visualization format)
///   pNodes(key) = 节点 OID = $LB(Id, Class)
///   pNodes(key) = node OID = $LB(Id, Class)
///   pEdges(seq) = $LB(源key, 目标key, 关系名)
///   pEdges(seq) = $LB(source key, target key, relation name)
/// 子图路径：risk -> region -> segment -> route -> voyage -> vessel
/// Subgraph path: risk -> region -> segment -> route -> voyage -> vessel
///           -> container -> shipment -> PO -> product -> salesorder
ClassMethod ImpactGraph(pRisk As %List, ByRef pAffected, Output pNodes, Output pEdges)
{
    Kill pNodes, pEdges
    Kill tSeenE
    Set tSeq = 0

    Do ..addNode(pRisk, .pNodes)
    Do ##class(Graph.Tools).SingleHop(pRisk, "risk_at_location", 0, .rReg)
    For i = 1:1:rReg.%Size() {
        Set tReg = rReg.%Get(i - 1).TargetOID
        Do ..addNode(tReg, .pNodes)
        Do ..addEdge(pRisk, "risk_at_location", tReg, .tSeenE, .pEdges, .tSeq)
    }

    Set tV = ""
    For {
        Set tV = $Order(pAffected(tV))
        Quit:tV=""
        Set tInfo = pAffected(tV)
        Set tSeg = $ListGet(tInfo, 1)
        Do ..addNode(tV, .pNodes)
        Do ..addNode(tSeg, .pNodes)
        For i = 1:1:rReg.%Size() {
            Do ..addEdge(tSeg, "passes_through", rReg.%Get(i - 1).TargetOID, .tSeenE, .pEdges, .tSeq)
        }

        // vessel -> voyage -> route -> segment
        Do ##class(Graph.Tools).SingleHop(tV, "assigned_to", 0, .rVy)
        For a = 1:1:rVy.%Size() {
            Set tVoy = rVy.%Get(a - 1).TargetOID
            Do ..addNode(tVoy, .pNodes)
            Do ..addEdge(tV, "assigned_to", tVoy, .tSeenE, .pEdges, .tSeq)
            Do ##class(Graph.Tools).SingleHop(tVoy, "uses", 0, .rRt)
            For b = 1:1:rRt.%Size() {
                Set tRt = rRt.%Get(b - 1).TargetOID
                Do ..addNode(tRt, .pNodes)
                Do ..addEdge(tVoy, "uses", tRt, .tSeenE, .pEdges, .tSeq)
                Do ..addEdge(tRt, "route_contains_segment", tSeg, .tSeenE, .pEdges, .tSeq)
            }
        }

        // business chain downward
        Do ##class(Graph.Tools).SingleHop(tV, "loaded_on", 1, .rC)
        For i = 1:1:rC.%Size() {
            Set tC = rC.%Get(i - 1).OID
            Do ..addNode(tC, .pNodes)
            Do ..addEdge(tC, "loaded_on", tV, .tSeenE, .pEdges, .tSeq)
            Do ##class(Graph.Tools).SingleHop(tC, "contains", 1, .rS)
            For j = 1:1:rS.%Size() {
                Set tS = rS.%Get(j - 1).OID
                Do ..addNode(tS, .pNodes)
                Do ..addEdge(tS, "contains", tC, .tSeenE, .pEdges, .tSeq)
                Do ##class(Graph.Tools).SingleHop(tS, "fulfilled_by", 1, .rP)
                For k = 1:1:rP.%Size() {
                    Set tP = rP.%Get(k - 1).OID
                    Do ..addNode(tP, .pNodes)
                    Do ..addEdge(tP, "fulfilled_by", tS, .tSeenE, .pEdges, .tSeq)
                    Do ##class(Graph.Tools).SingleHop(tP, "po_contains_product", 0, .rPr)
                    For m = 1:1:rPr.%Size() {
                        Set tPr = rPr.%Get(m - 1).TargetOID
                        Do ..addNode(tPr, .pNodes)
                        Do ..addEdge(tP, "po_contains_product", tPr, .tSeenE, .pEdges, .tSeq)
                        Do ##class(Graph.Tools).SingleHop(tPr, "so_contains_product", 1, .rSo)
                        For n = 1:1:rSo.%Size() {
                            Set tSo = rSo.%Get(n - 1).OID
                            Do ..addNode(tSo, .pNodes)
                            Do ..addEdge(tSo, "so_contains_product", tPr, .tSeenE, .pEdges, .tSeq)
                        }
                    }
                }
            }
        }
    }
}

/// 追加去重节点：pNodes(key) = OID
/// Append a deduplicated node: pNodes(key) = OID
ClassMethod addNode(pOID As %List, ByRef pNodes)
{
    Quit:$ListGet(pOID, 1)=""
    Set pNodes(..NodeKey(pOID)) = pOID
}

/// 追加去重边：pEdges(seq) = $LB(源key, 目标key, 关系名)
/// Append a deduplicated edge: pEdges(seq) = $LB(source key, target key, relation name)
ClassMethod addEdge(pSrc As %List, pRel As %String, pTgt As %List, ByRef pSeen, ByRef pEdges, ByRef pSeq)
{
    Quit:$ListGet(pSrc, 1)=""
    Quit:$ListGet(pTgt, 1)=""
    Set tSK = ..NodeKey(pSrc), tTK = ..NodeKey(pTgt)
    Set tK = tSK _ "|" _ pRel _ "|" _ tTK
    Quit:$Data(pSeen(tK))
    Set pSeen(tK) = 1
    Set pSeq = pSeq + 1
    Set pEdges(pSeq) = $ListBuild(tSK, tTK, pRel)
}

}
