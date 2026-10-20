/// 航次节点：船舶的一次具体航行；assigned_to 关联船舶，uses 关联航路。
/// Voyage node: a specific voyage of a vessel; assigned_to links to the vessel, uses links to the route.
/// Author: QP
/// Version: 1.0
Class Logistics.Route.Voyage Extends (%Persistent, Graph.Object.Base)
{

/// 航次编号
/// Voyage number
Property VoyageNo As %String;

/// 承运人
/// Carrier
Property Carrier As %String;

/// 预计到达时间 (ETA)
/// Estimated Time of Arrival (ETA)
Property ETA As %TimeStamp;

/// 预计离港时间 (ETD)
/// Estimated Time of Departure (ETD)
Property ETD As %TimeStamp;

/// 执行该航次的船舶（多对一；assigned_to：Vessel → Voyage）
/// Vessel executing this voyage (many-to-one; assigned_to: Vessel → Voyage)
Relationship Vessel As Logistics.Transport.Vessel(Direction = "FROM", Relation = "assigned_to") [ Cardinality = one, Inverse = Voyages ];

/// 使用的航路（uses：Voyage → Route）
/// Route used (uses: Voyage → Route)
Property Route As Logistics.Route.Route(Direction = "FROM", Relation = "uses");

Storage Default
{
<Data name="VoyageDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>VoyageNo</Value>
</Value>
<Value name="3">
<Value>Carrier</Value>
</Value>
<Value name="4">
<Value>ETA</Value>
</Value>
<Value name="5">
<Value>ETD</Value>
</Value>
<Value name="6">
<Value>Vessel</Value>
</Value>
<Value name="7">
<Value>Route</Value>
</Value>
</Data>
<DataLocation>^Logistics.Route.VoyageD</DataLocation>
<DefaultData>VoyageDefaultData</DefaultData>
<IdLocation>^Logistics.Route.VoyageD</IdLocation>
<IndexLocation>^Logistics.Route.VoyageI</IndexLocation>
<StreamLocation>^Logistics.Route.VoyageS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndex On (Route, Vessel) As Graph.Object.Index;

}
