/// Typhoon risk impact tracking - graph demo + test (combined spatial + temporal determination)
/// 
/// Scenario: typhoon "Muifa" covers the Taiwan Strait (a SeaArea) within a specific 48-hour window.
/// A vessel is deemed affected only when BOTH conditions hold:
///   (spatial) the vessel's route has a segment that passes_through the typhoon-covered area;
///   (temporal) from the voyage ETD + cumulative segment durations, the vessel's "time window crossing that segment"
///          overlaps the typhoon window [StartTime, EndTime].
/// A vessel that only satisfies the spatial condition (route crosses the area) but is time-clear is not affected.
/// 
/// Data (edges maintained automatically by Graph.Object.Index on %Save):
///   Route R-TW-01 (via Taiwan Strait) has 3 ordered segments: East China Sea(24h) -> Taiwan Strait(18h) -> South China Sea(30h);
///   Route R-CAPE-01 (via Cape of Good Hope, spatial control, not via Taiwan Strait).
///   Three vessels:
///     MV Pacific  VT-1 ETD=2026-08-10 00:00 on R-TW-01 -> Taiwan Strait window=08-11 00:00~18:00 -> overlaps typhoon -> affected
///     MV Orient   VT-2 ETD=2026-08-15 00:00 on R-TW-01 -> Taiwan Strait window=08-16 00:00~18:00 -> typhoon has passed -> not affected
///     MV Southern VT-3 ETD=2026-08-10 00:00 on R-CAPE-01 -> not via Taiwan Strait -> spatially excluded -> not affected
///   Typhoon: Type=Typhoon, Location=Taiwan Strait, StartTime=2026-08-10 12:00, EndTime=2026-08-12 12:00 (48h).
/// 
/// Graph trace:
///   [1] Spatial: typhoon area <- passes_through reverse-lookup of segments covered by the typhoon
///   [2] Topology: segment <- route_contains_segment <- uses <- assigned_to reverse-trace of candidate vessels
///   [3] Temporal: for each candidate vessel, compute the window crossing the typhoon segment from ETD + cumulative durations, overlap-check against the typhoon window
/// 
/// Usage:
///     Do ##class(Logistics.Test.TyphoonDemo).Run()      // build data + trace + assert
///     Do ##class(Logistics.Test.TyphoonDemo).Setup()    // build data only
///     Do ##class(Logistics.Test.TyphoonDemo).Trace()    // trace only (requires Setup first)
///     Do ##class(Logistics.Test.TyphoonDemo).Cleanup()  // remove test data
/// Author: QP
/// Version: 1.0
Class Logistics.Test.TyphoonDemo Extends %RegisteredObject
{

/// One-shot run: build data -> graph trace -> assertions
ClassMethod Run() As %Status
{
    Set tSC = ..Setup()
    If $$$ISERR(tSC) {
        Write !, "Setup failed: ", $System.Status.GetOneErrorText(tSC), !
        Quit tSC
    }
    Do ..Trace()
    Quit ..Assert()
}

/// Save object: register into ^LogiTyphoon for cleanup, return OID = $LB(Id, ClassName)
ClassMethod save(pObj) As %List
{
    Set tSC = pObj.%Save()
    If $$$ISERR(tSC) $$$ThrowStatus(tSC)
    Set tCls = $ClassName(pObj), tId = pObj.%Id()
    Set ^LogiTyphoon("obj", tCls, tId) = ""
    Quit $ListBuild(tId, tCls)
}

/// Build demo data (geography / routes+ordered segments / vessels+voyages / typhoon)
ClassMethod Setup() As %Status
{
    Set tSC = $$$OK
    Try {
        Do ..Cleanup()

        // ---------- Geography ----------
        Set shanghai = ##class(Logistics.Geography.Location).%New(), shanghai.Name = "Shanghai Port", shanghai.Type = "Port"
        Do ..save(shanghai)
        Set Shenzhen = ##class(Logistics.Geography.Location).%New(), Shenzhen.Name = "Shenzhen Port", Shenzhen.Type = "Port"
        Do ..save(Shenzhen)
        Set Zhuhai = ##class(Logistics.Geography.Location).%New(), Zhuhai.Name = "Zhuhai Port", Zhuhai.Type = "Port"
        Do ..save(Zhuhai)
        Set Fangcheng = ##class(Logistics.Geography.Location).%New(), Fangcheng.Name = "Fangcheng Port", Fangcheng.Type = "Port"
        Do ..save(Fangcheng)
        Set eastChinaSea = ##class(Logistics.Geography.Location).%New(), eastChinaSea.Name = "East China Sea", eastChinaSea.Type = "SeaArea"
        Do ..save(eastChinaSea)
        Set southChinaSea = ##class(Logistics.Geography.Location).%New(), southChinaSea.Name = "South China Sea", southChinaSea.Type = "SeaArea"
        Do ..save(southChinaSea)
        Set GulfofThailand = ##class(Logistics.Geography.Location).%New(), GulfofThailand.Name = "Gulf of Thailand", GulfofThailand.Type = "SeaArea"
        Do ..save(GulfofThailand)
        Set StraitofMalacca = ##class(Logistics.Geography.Location).%New(), StraitofMalacca.Name = "Strait of Malacca", StraitofMalacca.Type = "SeaArea"
        Do ..save(StraitofMalacca)
        Set JavaSea = ##class(Logistics.Geography.Location).%New(), JavaSea.Name = "Java Sea", JavaSea.Type = "SeaArea"
        Do ..save(JavaSea)
        Set taiwanStrait = ##class(Logistics.Geography.Location).%New(), taiwanStrait.Name = "Taiwan Strait", taiwanStrait.Type = "SeaArea"
        Set taiwanStrait.Latitude = 24.5, taiwanStrait.Longitude = 119.5
        Do ..save(taiwanStrait)
        Set SuluSea = ##class(Logistics.Geography.Location).%New(), SuluSea.Name = "Sulu Sea", SuluSea.Type = "SeaArea"
        Do ..save(SuluSea)
        Set singapore = ##class(Logistics.Geography.Location).%New(), singapore.Name = "Singapore Port", singapore.Type = "Port"
        Do ..save(singapore)
        Set cape = ##class(Logistics.Geography.Location).%New(), cape.Name = "Cape of Good Hope", cape.Type = "SeaArea"
        Do ..save(cape)
        Set HaiPhong = ##class(Logistics.Geography.Location).%New(), HaiPhong.Name = "Hai Phong Port", HaiPhong.Type = "Port"
        Do ..save(HaiPhong)
        Set Saigon = ##class(Logistics.Geography.Location).%New(), Saigon.Name = "Saigon Port", Saigon.Type = "Port"
        Do ..save(Saigon)
        Set DaNang = ##class(Logistics.Geography.Location).%New(), DaNang.Name = "Da Nang Port", DaNang.Type = "Port"
        Do ..save(DaNang)
        Set Bangkok = ##class(Logistics.Geography.Location).%New(), Bangkok.Name = "Bangkok Port", Bangkok.Type = "Port"
        Do ..save(Bangkok)
        Set LaemChabang = ##class(Logistics.Geography.Location).%New(), LaemChabang.Name = "Laem Chabang Port", LaemChabang.Type = "Port"
        Do ..save(LaemChabang)
        Set Songkhla = ##class(Logistics.Geography.Location).%New(), Songkhla.Name = "Songkhla Port", Songkhla.Type = "Port"
        Do ..save(Songkhla)
        Set Manila = ##class(Logistics.Geography.Location).%New(), Manila.Name = "Manila Port", Manila.Type = "Port"
        Do ..save(Manila)
        Set Cebu = ##class(Logistics.Geography.Location).%New(), Cebu.Name = "Cebu Port", Cebu.Type = "Port"
        Do ..save(Cebu)
        Set Bataan = ##class(Logistics.Geography.Location).%New(), Bataan.Name = "Bataan Port", Bataan.Type = "Port"
        Do ..save(Bataan)
        Set Chattogram = ##class(Logistics.Geography.Location).%New(), Chattogram.Name = "Chattogram Port", Chattogram.Type = "Port"
        Do ..save(Chattogram)
        Set rotterdam = ##class(Logistics.Geography.Location).%New(), rotterdam.Name = "Rotterdam Port", rotterdam.Type = "Port"
        Do ..save(rotterdam)

        // ---------- Route R-TW-01: via Taiwan Strait (3 ordered segments) ----------
        Set routeTW = ##class(Logistics.Route.Route).%New(), routeTW.RouteID = "R-TW-01", routeTW.RouteName = "Asia-Europe via Taiwan Strait"
        Do ..save(routeTW)

        Set seg1 = ##class(Logistics.Route.RouteSegment).%New()
        Set seg1.SegmentID = "SEG-ECS", seg1.Name = "East China Sea Leg", seg1.Sequence = 1, seg1.ExpectedDuration = 24, seg1.Route = routeTW, seg1.StartLocation = shanghai, seg1.EndLocation = taiwanStrait
        Do seg1.PassesThrough.Insert(shanghai), seg1.PassesThrough.Insert(eastChinaSea)
        Do ..save(seg1)

        Set seg2 = ##class(Logistics.Route.RouteSegment).%New()
        Set seg2.SegmentID = "SEG-TWS", seg2.Name = "Taiwan Strait Leg", seg2.Sequence = 2, seg2.ExpectedDuration = 18, seg2.Route = routeTW, seg2.StartLocation = taiwanStrait, seg2.EndLocation = southChinaSea
        Do seg2.PassesThrough.Insert(taiwanStrait)
        Do ..save(seg2)

        Set seg3 = ##class(Logistics.Route.RouteSegment).%New()
        Set seg3.SegmentID = "SEG-SCS", seg3.Name = "South China Sea Leg", seg3.Sequence = 3, seg3.ExpectedDuration = 30, seg3.Route = routeTW, seg3.StartLocation = southChinaSea, seg3.EndLocation = singapore
        Do seg3.PassesThrough.Insert(southChinaSea), seg3.PassesThrough.Insert(singapore)
        Do ..save(seg3)

        // ---------- Route R-CAPE-01: via Cape of Good Hope (spatial control, not via Taiwan Strait) ----------
        Set routeCape = ##class(Logistics.Route.Route).%New(), routeCape.RouteID = "R-CAPE-01", routeCape.RouteName = "Asia-Europe via Cape"
        Do ..save(routeCape)
        Set segC = ##class(Logistics.Route.RouteSegment).%New()
        Set segC.SegmentID = "SEG-CAPE", segC.Name = "Cape Leg", segC.Sequence = 1, segC.ExpectedDuration = 40, segC.Route = routeCape, segC.StartLocation = cape, segC.EndLocation = cape
        Do segC.PassesThrough.Insert(cape)
        Do ..save(segC)

        // ---------- Vessel (with current lat/lon for map display) ----------
        Set pacific = ##class(Logistics.Transport.Vessel).%New()
        Set pacific.AssetID = "V-PAC", pacific.Name = "MV Pacific", pacific.IMO = "IMO3333333", pacific.CurrentLocation = shanghai
        Set pacific.Latitude = 24.6, pacific.Longitude = 119.6
        Do ..save(pacific)
        Set orient = ##class(Logistics.Transport.Vessel).%New()
        Set orient.AssetID = "V-ORI", orient.Name = "MV Orient", orient.IMO = "IMO4444444", orient.CurrentLocation = shanghai
        Set orient.Latitude = 31.2, orient.Longitude = 122.6
        Do ..save(orient)
        Set southern = ##class(Logistics.Transport.Vessel).%New()
        Set southern.AssetID = "V-SOU", southern.Name = "MV Southern", southern.IMO = "IMO5555555", southern.CurrentLocation = shanghai
        Set southern.Latitude = -34.4, southern.Longitude = 18.5
        Do ..save(southern)

        // ---------- Voyage (different ETD determines the arrival time at the Taiwan Strait) ----------
        Set vtPac = ##class(Logistics.Route.Voyage).%New()
        Set vtPac.VoyageNo = "VT-1", vtPac.Carrier = "PacificLine", vtPac.Vessel = pacific, vtPac.Route = routeTW, vtPac.ETD = "2026-08-10 00:00:00"
        Do ..save(vtPac)
        Set vtOri = ##class(Logistics.Route.Voyage).%New()
        Set vtOri.VoyageNo = "VT-2", vtOri.Carrier = "PacificLine", vtOri.Vessel = orient, vtOri.Route = routeTW, vtOri.ETD = "2026-08-15 00:00:00"
        Do ..save(vtOri)
        Set vtSou = ##class(Logistics.Route.Voyage).%New()
        Set vtSou.VoyageNo = "VT-3", vtSou.Carrier = "CapeLine", vtSou.Vessel = southern, vtSou.Route = routeCape, vtSou.ETD = "2026-08-10 00:00:00"
        Do ..save(vtSou)

        // ================= RCL Asia-South Asia/Middle East route extension =================
        // ---------- New sea areas & ports ----------
        Set andamanSea = ##class(Logistics.Geography.Location).%New(), andamanSea.Name = "Andaman Sea", andamanSea.Type = "SeaArea"
        Do ..save(andamanSea)
        Set bayOfBengal = ##class(Logistics.Geography.Location).%New(), bayOfBengal.Name = "Bay of Bengal", bayOfBengal.Type = "SeaArea"
        Do ..save(bayOfBengal)
        Set arabianSea = ##class(Logistics.Geography.Location).%New(), arabianSea.Name = "Arabian Sea", arabianSea.Type = "SeaArea"
        Do ..save(arabianSea)
        Set persianGulf = ##class(Logistics.Geography.Location).%New(), persianGulf.Name = "Persian Gulf", persianGulf.Type = "SeaArea"
        Do ..save(persianGulf)
        Set redSea = ##class(Logistics.Geography.Location).%New(), redSea.Name = "Red Sea", redSea.Type = "SeaArea"
        Do ..save(redSea)
        Set philippineSea = ##class(Logistics.Geography.Location).%New(), philippineSea.Name = "Philippine Sea", philippineSea.Type = "SeaArea"
        Do ..save(philippineSea)

        Set yangon = ##class(Logistics.Geography.Location).%New(), yangon.Name = "Yangon Port", yangon.Type = "Port"
        Do ..save(yangon)
        Set chennai = ##class(Logistics.Geography.Location).%New(), chennai.Name = "Chennai Port", chennai.Type = "Port"
        Do ..save(chennai)
        Set colombo = ##class(Logistics.Geography.Location).%New(), colombo.Name = "Colombo Port", colombo.Type = "Port"
        Do ..save(colombo)
        Set mumbai = ##class(Logistics.Geography.Location).%New(), mumbai.Name = "Mumbai Port", mumbai.Type = "Port"
        Do ..save(mumbai)
        Set jebelAli = ##class(Logistics.Geography.Location).%New(), jebelAli.Name = "Jebel Ali Port", jebelAli.Type = "Port"
        Do ..save(jebelAli)
        Set jeddah = ##class(Logistics.Geography.Location).%New(), jeddah.Name = "Jeddah Port", jeddah.Type = "Port"
        Do ..save(jeddah)

        // ---------- Route R-BOB-01: Singapore -> Bay of Bengal (RCL Bay of Bengal line, via Andaman Sea) ----------
        Set routeBOB = ##class(Logistics.Route.Route).%New(), routeBOB.RouteID = "R-BOB-01", routeBOB.RouteName = "RCL Singapore-Bay of Bengal"
        Do ..save(routeBOB)
        Set bobSeg1 = ##class(Logistics.Route.RouteSegment).%New()
        Set bobSeg1.SegmentID = "SEG-BOB-MAL", bobSeg1.Name = "Malacca Leg", bobSeg1.Sequence = 1, bobSeg1.ExpectedDuration = 20, bobSeg1.Route = routeBOB, bobSeg1.StartLocation = singapore, bobSeg1.EndLocation = andamanSea
        Do bobSeg1.PassesThrough.Insert(singapore), bobSeg1.PassesThrough.Insert(StraitofMalacca)
        Do ..save(bobSeg1)
        Set bobSeg2 = ##class(Logistics.Route.RouteSegment).%New()
        Set bobSeg2.SegmentID = "SEG-BOB-AND", bobSeg2.Name = "Andaman Sea Leg", bobSeg2.Sequence = 2, bobSeg2.ExpectedDuration = 24, bobSeg2.Route = routeBOB, bobSeg2.StartLocation = andamanSea, bobSeg2.EndLocation = bayOfBengal
        Do bobSeg2.PassesThrough.Insert(andamanSea), bobSeg2.PassesThrough.Insert(yangon)
        Do ..save(bobSeg2)
        Set bobSeg3 = ##class(Logistics.Route.RouteSegment).%New()
        Set bobSeg3.SegmentID = "SEG-BOB-BEN", bobSeg3.Name = "Bay of Bengal Leg", bobSeg3.Sequence = 3, bobSeg3.ExpectedDuration = 30, bobSeg3.Route = routeBOB, bobSeg3.StartLocation = bayOfBengal, bobSeg3.EndLocation = Chattogram
        Do bobSeg3.PassesThrough.Insert(bayOfBengal), bobSeg3.PassesThrough.Insert(chennai), bobSeg3.PassesThrough.Insert(Chattogram)
        Do ..save(bobSeg3)

        // ---------- Route R-GULF-01: Singapore -> Persian Gulf (RCL Gulf line, via Andaman Sea/Arabian Sea) ----------
        Set routeGulf = ##class(Logistics.Route.Route).%New(), routeGulf.RouteID = "R-GULF-01", routeGulf.RouteName = "RCL Singapore-Persian Gulf"
        Do ..save(routeGulf)
        Set gulfSeg1 = ##class(Logistics.Route.RouteSegment).%New()
        Set gulfSeg1.SegmentID = "SEG-GULF-AND", gulfSeg1.Name = "Malacca-Andaman Leg", gulfSeg1.Sequence = 1, gulfSeg1.ExpectedDuration = 40, gulfSeg1.Route = routeGulf, gulfSeg1.StartLocation = singapore, gulfSeg1.EndLocation = arabianSea
        Do gulfSeg1.PassesThrough.Insert(singapore), gulfSeg1.PassesThrough.Insert(StraitofMalacca), gulfSeg1.PassesThrough.Insert(andamanSea)
        Do ..save(gulfSeg1)
        Set gulfSeg2 = ##class(Logistics.Route.RouteSegment).%New()
        Set gulfSeg2.SegmentID = "SEG-GULF-ARB", gulfSeg2.Name = "Arabian Sea Leg", gulfSeg2.Sequence = 2, gulfSeg2.ExpectedDuration = 36, gulfSeg2.Route = routeGulf, gulfSeg2.StartLocation = arabianSea, gulfSeg2.EndLocation = persianGulf
        Do gulfSeg2.PassesThrough.Insert(arabianSea), gulfSeg2.PassesThrough.Insert(colombo), gulfSeg2.PassesThrough.Insert(mumbai)
        Do ..save(gulfSeg2)
        Set gulfSeg3 = ##class(Logistics.Route.RouteSegment).%New()
        Set gulfSeg3.SegmentID = "SEG-GULF-PG", gulfSeg3.Name = "Persian Gulf Leg", gulfSeg3.Sequence = 3, gulfSeg3.ExpectedDuration = 20, gulfSeg3.Route = routeGulf, gulfSeg3.StartLocation = persianGulf, gulfSeg3.EndLocation = jebelAli
        Do gulfSeg3.PassesThrough.Insert(persianGulf), gulfSeg3.PassesThrough.Insert(jebelAli)
        Do ..save(gulfSeg3)

        // ---------- Route R-RED-01: Singapore -> Red Sea (RCL Red Sea line, via Arabian Sea) ----------
        Set routeRed = ##class(Logistics.Route.Route).%New(), routeRed.RouteID = "R-RED-01", routeRed.RouteName = "RCL Singapore-Red Sea"
        Do ..save(routeRed)
        Set redSeg1 = ##class(Logistics.Route.RouteSegment).%New()
        Set redSeg1.SegmentID = "SEG-RED-ARB", redSeg1.Name = "Arabian Sea Leg", redSeg1.Sequence = 1, redSeg1.ExpectedDuration = 60, redSeg1.Route = routeRed, redSeg1.StartLocation = singapore, redSeg1.EndLocation = redSea
        Do redSeg1.PassesThrough.Insert(singapore), redSeg1.PassesThrough.Insert(arabianSea)
        Do ..save(redSeg1)
        Set redSeg2 = ##class(Logistics.Route.RouteSegment).%New()
        Set redSeg2.SegmentID = "SEG-RED-RS", redSeg2.Name = "Red Sea Leg", redSeg2.Sequence = 2, redSeg2.ExpectedDuration = 24, redSeg2.Route = routeRed, redSeg2.StartLocation = redSea, redSeg2.EndLocation = jeddah
        Do redSeg2.PassesThrough.Insert(redSea), redSeg2.PassesThrough.Insert(jeddah)
        Do ..save(redSeg2)

        // ---------- Route R-PHIL-01: Manila -> Philippine Sea (RCL Philippine Sea line) ----------
        Set routePhil = ##class(Logistics.Route.Route).%New(), routePhil.RouteID = "R-PHIL-01", routePhil.RouteName = "RCL Manila-Philippine Sea"
        Do ..save(routePhil)
        Set philSeg1 = ##class(Logistics.Route.RouteSegment).%New()
        Set philSeg1.SegmentID = "SEG-PHIL", philSeg1.Name = "Philippine Sea Leg", philSeg1.Sequence = 1, philSeg1.ExpectedDuration = 30, philSeg1.Route = routePhil, philSeg1.StartLocation = Manila, philSeg1.EndLocation = Cebu
        Do philSeg1.PassesThrough.Insert(Manila), philSeg1.PassesThrough.Insert(philippineSea), philSeg1.PassesThrough.Insert(Cebu)
        Do ..save(philSeg1)

        // ---------- RCL vessels (with current lat/lon) ----------
        Set andamanStar = ##class(Logistics.Transport.Vessel).%New()
        Set andamanStar.AssetID = "V-AND", andamanStar.Name = "MV Andaman Star", andamanStar.IMO = "IMO6111111", andamanStar.CurrentLocation = singapore
        Set andamanStar.Latitude = 8.5, andamanStar.Longitude = 95.5
        Do ..save(andamanStar)
        Set bengalTrader = ##class(Logistics.Transport.Vessel).%New()
        Set bengalTrader.AssetID = "V-BEN", bengalTrader.Name = "MV Bengal Trader", bengalTrader.IMO = "IMO6222222", bengalTrader.CurrentLocation = singapore
        Set bengalTrader.Latitude = 15.0, bengalTrader.Longitude = 89.0
        Do ..save(bengalTrader)
        Set gulfVoyager = ##class(Logistics.Transport.Vessel).%New()
        Set gulfVoyager.AssetID = "V-GLF", gulfVoyager.Name = "MV Gulf Voyager", gulfVoyager.IMO = "IMO6333333", gulfVoyager.CurrentLocation = singapore
        Set gulfVoyager.Latitude = 15.0, gulfVoyager.Longitude = 62.0
        Do ..save(gulfVoyager)
        Set redSeaStar = ##class(Logistics.Transport.Vessel).%New()
        Set redSeaStar.AssetID = "V-RED", redSeaStar.Name = "MV Red Sea Star", redSeaStar.IMO = "IMO6444444", redSeaStar.CurrentLocation = singapore
        Set redSeaStar.Latitude = 20.0, redSeaStar.Longitude = 38.5
        Do ..save(redSeaStar)
        Set philStar = ##class(Logistics.Transport.Vessel).%New()
        Set philStar.AssetID = "V-PHI", philStar.Name = "MV Philippine Star", philStar.IMO = "IMO6555555", philStar.CurrentLocation = Manila
        Set philStar.Latitude = 14.6, philStar.Longitude = 130.0
        Do ..save(philStar)

        // ---------- RCL voyages ----------
        Set vtBob = ##class(Logistics.Route.Voyage).%New()
        Set vtBob.VoyageNo = "VT-BOB", vtBob.Carrier = "RCL", vtBob.Vessel = bengalTrader, vtBob.Route = routeBOB, vtBob.ETD = "2026-08-12 00:00:00"
        Do ..save(vtBob)
        Set vtAnd = ##class(Logistics.Route.Voyage).%New()
        Set vtAnd.VoyageNo = "VT-AND", vtAnd.Carrier = "RCL", vtAnd.Vessel = andamanStar, vtAnd.Route = routeBOB, vtAnd.ETD = "2026-08-18 00:00:00"
        Do ..save(vtAnd)
        Set vtGulf = ##class(Logistics.Route.Voyage).%New()
        Set vtGulf.VoyageNo = "VT-GULF", vtGulf.Carrier = "RCL", vtGulf.Vessel = gulfVoyager, vtGulf.Route = routeGulf, vtGulf.ETD = "2026-08-11 00:00:00"
        Do ..save(vtGulf)
        Set vtRed = ##class(Logistics.Route.Voyage).%New()
        Set vtRed.VoyageNo = "VT-RED", vtRed.Carrier = "RCL", vtRed.Vessel = redSeaStar, vtRed.Route = routeRed, vtRed.ETD = "2026-08-13 00:00:00"
        Do ..save(vtRed)
        Set vtPhil = ##class(Logistics.Route.Voyage).%New()
        Set vtPhil.VoyageNo = "VT-PHIL", vtPhil.Carrier = "RCL", vtPhil.Vessel = philStar, vtPhil.Route = routePhil, vtPhil.ETD = "2026-08-10 06:00:00"
        Do ..save(vtPhil)

        // ================= Business entities of affected vessel MV Pacific (containers / shipments / purchase orders / customers) =================
        // Graph chain: Vessel <-loaded_on- Container <-contains- Shipment <-fulfilled_by- PurchaseOrder -po_contains_product-> Product <-so_contains_product- SalesOrder(.Customer)
        Set shpTW = ##class(Logistics.Transport.Shipment).%New()
        Set shpTW.ShipmentNo = "SHP-TW-001", shpTW.Mode = "Sea", shpTW.Origin = shanghai, shpTW.Destination = rotterdam, shpTW.Status = "InTransit"
        Do ..save(shpTW)

        Set cntA = ##class(Logistics.Asset.Container).%New()
        Set cntA.ContainerNo = "TCLU1234567", cntA.ISOCode = "45G1", cntA.Status = "Laden", cntA.CurrentTransport = pacific, cntA.Shipment = shpTW
        Do ..save(cntA)
        Set cntB = ##class(Logistics.Asset.Container).%New()
        Set cntB.ContainerNo = "MSKU7654321", cntB.ISOCode = "22G1", cntB.Status = "Laden", cntB.CurrentTransport = pacific, cntB.Shipment = shpTW
        Do ..save(cntB)

        Set prodTW = ##class(Logistics.Business.Product).%New()
        Set prodTW.SKU = "SKU-ELEC-01", prodTW.Name = "Consumer Electronics"
        Do ..save(prodTW)

        Set poTW = ##class(Logistics.Business.PurchaseOrder).%New()
        Set poTW.PONumber = "PO-88001", poTW.Status = "Open", poTW.Shipment = shpTW
        Do poTW.Products.Insert(prodTW)
        Do ..save(poTW)

        Set soTW = ##class(Logistics.Business.SalesOrder).%New()
        Set soTW.SONumber = "SO-55001", soTW.Customer = "ACME Retail GmbH", soTW.Status = "Confirmed"
        Do soTW.Products.Insert(prodTW)
        Do ..save(soTW)

        // ---------- Typhoon RiskEvent (area + 48h time window) ----------
        Set typhoon = ##class(Logistics.Risk.RiskEvent).%New()
        Set typhoon.Name = "Typhoon Muifa 2026", typhoon.Type = "Typhoon", typhoon.Severity = 7, typhoon.Radius = 300, typhoon.WindSpeed = 180
        Set typhoon.Forecast = "48h typhoon over the Taiwan Strait"
        Set typhoon.Location = taiwanStrait
        Set typhoon.StartTime = "2026-08-10 12:00:00", typhoon.EndTime = "2026-08-12 12:00:00"
        Do ..save(typhoon)

        // ---------- Record key nodes for reuse in tracing/assertions ----------
        Set ^LogiTyphoon("key", "risk") = $ListBuild(typhoon.%Id(), $ClassName(typhoon))
        Set ^LogiTyphoon("key", "region") = $ListBuild(taiwanStrait.%Id(), $ClassName(taiwanStrait))
        Set ^LogiTyphoon("key", "pacific") = $ListBuild(pacific.%Id(), $ClassName(pacific))
        Set ^LogiTyphoon("key", "orient") = $ListBuild(orient.%Id(), $ClassName(orient))
        Set ^LogiTyphoon("key", "southern") = $ListBuild(southern.%Id(), $ClassName(southern))

        Write "Typhoon demo data built.", !
    }
    Catch ex {
        Set tSC = ex.AsStatus()
        Write !, "Setup exception: ", $System.Status.GetOneErrorText(tSC), !
    }
    Quit tSC
}

/// Graph trace: spatial + temporal impact determination for the typhoon
ClassMethod Trace() As %Status
{
    Set tRisk = $Get(^LogiTyphoon("key", "risk"))
    If tRisk = "" { Write "Please run Setup() first.", ! Quit $$$OK }
    Set tRiskObj = ##class(Logistics.Risk.Tools).openOID(tRisk)

    Write !, "=====================================================", !
    Write "  Typhoon Risk Impact Trace (spatial + temporal)", !
    Write "=====================================================", !
    Write "Typhoon: ", ##class(Logistics.Risk.Tools).Label(tRisk), !
    Write "Time window: ", tRiskObj.StartTime, " ~ ", tRiskObj.EndTime, " (48h)", !

    // [1] Spatial: segments covered by the typhoon area
    Do ##class(Graph.Tools).SingleHop($Get(^LogiTyphoon("key", "region")), "passes_through", 1, .tSegRes)
    Write !, "[1] Segments covered by the typhoon area (region <-passes_through- segment):", !
    For tI = 1:1:tSegRes.%Size() { Write "      - ", ##class(Logistics.Risk.Tools).Label(tSegRes.%Get(tI - 1).OID), ! }

    // [2]+[3] Combined spatial+temporal determination (calls the generic risk analysis)
    Do ##class(Logistics.Risk.Tools).AnalyzeRisk(tRisk, .tSpatial, .tAffected)
    Write !, "[2] Candidate vessels whose route spatially crosses the typhoon area:", !
    Set tV = ""
    For { Set tV = $Order(tSpatial(tV))  Quit:tV=""  Write "      - ", ##class(Logistics.Risk.Tools).Label(tV), "  (via ", ##class(Logistics.Risk.Tools).Label(tSpatial(tV)), ")", ! }

    Write !, "[3] After applying the time window -- vessels actually affected:", !
    Set tV = ""
    For {
        Set tV = $Order(tAffected(tV))
        Quit:tV=""
        Set tInfo = tAffected(tV)
        Write "      - ", ##class(Logistics.Risk.Tools).Label(tV), "  typhoon-segment window ", ##class(Logistics.Risk.Tools).secToTs($List(tInfo, 2)), " ~ ", ##class(Logistics.Risk.Tools).secToTs($List(tInfo, 3)), " (overlaps the typhoon)", !
    }

    Write !, "[3'] Vessels crossing the area but time-clear, not affected:", !
    Set tV = ""
    For {
        Set tV = $Order(tSpatial(tV))
        Quit:tV=""
        Continue:$Data(tAffected(tV))
        Set tWin = ##class(Logistics.Risk.Tools).segWindow(..voyageOfVessel(tV), ..segInRegionOfVessel(tV))
        Write "      - ", ##class(Logistics.Risk.Tools).Label(tV), $Select(tWin="":"", 1:"  typhoon-segment window "_##class(Logistics.Risk.Tools).secToTs($List(tWin, 1))_" ~ "_##class(Logistics.Risk.Tools).secToTs($List(tWin, 2))_" (typhoon has passed)"), !
    }
    Quit $$$OK
}

/// Trace helper: OID of the voyage a vessel runs on the route through the typhoon area (used to print its off-window)
ClassMethod voyageOfVessel(pVesOID As %List) As %List
{
    Do ##class(Graph.Tools).SingleHop(pVesOID, "assigned_to", 0, .tR)
    Quit $Select(tR.%Size()>0: tR.%Get(0).TargetOID, 1: "")
}

/// Trace helper: OID of the segment on a vessel's route that lies in the typhoon area
ClassMethod segInRegionOfVessel(pVesOID As %List) As %List
{
    Set tVoy = ..voyageOfVessel(pVesOID)
    Quit:tVoy="" ""
    Set tVoyObj = ##class(Logistics.Risk.Tools).openOID(tVoy)
    Quit:'$IsObject(tVoyObj) ""
    Set tRoute = tVoyObj.Route
    Quit:'$IsObject(tRoute) ""
    Set tRegionObj = ##class(Logistics.Risk.Tools).openOID($Get(^LogiTyphoon("key", "region")))
    Set tRegionName = $Select($IsObject(tRegionObj): tRegionObj.Name, 1: "")
    Set tFound = ""
    For tI = 1:1:tRoute.Segments.Count() {
        Set tS = tRoute.Segments.GetAt(tI)
        For tJ = 1:1:tS.PassesThrough.Count() {
            If tS.PassesThrough.GetAt(tJ).Name = tRegionName {
                Set tFound = $ListBuild(tS.%Id(), $ClassName(tS))
                Quit
            }
        }
        Quit:tFound'=""
    }
    Quit tFound
}

/// Assertion tests
ClassMethod Assert() As %Status
{
    Do ##class(Logistics.Risk.Tools).AnalyzeRisk($Get(^LogiTyphoon("key", "risk")), .tSpatial, .tAffected)
    Set tPass = 1
    Write !, "----------------- Test Cases -----------------", !

    Set tPac = $Get(^LogiTyphoon("key", "pacific"))
    Set tOri = $Get(^LogiTyphoon("key", "orient"))
    Set tSou = $Get(^LogiTyphoon("key", "southern"))

    // T1: MV Pacific spatially crosses + time overlaps -> affected
    Do ..report("T1 MV Pacific affected (via Taiwan Strait and time overlaps)", $Data(tAffected(tPac)) > 0, .tPass)
    // T2: MV Orient spatially crosses but time-clear -> not affected
    Do ..report("T2 MV Orient via Taiwan Strait but typhoon has passed -> not affected", ($Data(tSpatial(tOri)) > 0) && ($Data(tAffected(tOri)) = 0), .tPass)
    // T3: MV Southern route not via Taiwan Strait -> spatially excluded
    Do ..report("T3 MV Southern via Cape of Good Hope -> spatially excluded, not affected", ($Data(tSpatial(tSou)) = 0) && ($Data(tAffected(tSou)) = 0), .tPass)

    Write "--------------------------------------------", !
    Write $Select(tPass: ">>> ALL PASSED", 1: ">>> FAILED"), !
    Quit $Select(tPass: $$$OK, 1: $$$ERROR(5001, "TyphoonDemo has failing test cases"))
}

/// Print a single assertion result
ClassMethod report(pName As %String, pOK As %Boolean, ByRef pPass As %Boolean)
{
    Write "  [", $Select(pOK: "PASS", 1: "FAIL"), "] ", pName, !
    Set:'pOK pPass = 0
}

/// Remove all test data created by this demo (deletion triggers Graph.Object.Index edge cleanup)
ClassMethod Cleanup() As %Status
{
    For tPass = 1:1:2 {
        Set tCls = ""
        For {
            Set tCls = $Order(^LogiTyphoon("obj", tCls))
            Quit:tCls=""
            Set tId = ""
            For {
                Set tId = $Order(^LogiTyphoon("obj", tCls, tId))
                Quit:tId=""
                Try {
                    Set tSC = $ClassMethod(tCls, "%DeleteId", tId)
                    Kill:$$$ISOK(tSC) ^LogiTyphoon("obj", tCls, tId)
                } Catch { }
            }
        }
    }
    Kill ^LogiTyphoon
    Quit $$$OK
}

}
