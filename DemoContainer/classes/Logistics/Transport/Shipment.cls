/// 货运节点（真正的物流单元）：一批货物的运输执行单据；contains 集装箱，has_leg 运输段。
/// Shipment node (the true logistics unit): the transport execution document for a batch of cargo; contains containers, has_leg transport legs.
/// Author: QP
/// Version: 1.0
Class Logistics.Transport.Shipment Extends (%Persistent, Graph.Object.Base)
{

/// 运单号
/// Shipment number
Property ShipmentNo As %String;

/// 运输方式（海运/空运/陆运等）
/// Transport mode (sea/air/land freight, etc.)
Property Mode As %String;

/// 起运地（shipment_origin）
/// Origin (shipment_origin)
Property Origin As Logistics.Geography.Location(Direction = "FROM", Relation = "shipment_origin");

/// 目的地（shipment_destination）
/// Destination (shipment_destination)
Property Destination As Logistics.Geography.Location(Direction = "FROM", Relation = "shipment_destination");

/// 预计到达时间 (Estimated Time of Arrival)
/// Estimated Time of Arrival (ETA)
Property ETA As %TimeStamp;

/// 运单状态
/// Shipment status
Property Status As %String;

/// 装载的集装箱集合（一对多；contains 边声明在 Container 侧）
/// Set of loaded containers (one-to-many; contains edge declared on the Container side)
Relationship Containers As Logistics.Asset.Container [ Cardinality = many, Inverse = Shipment ];

/// 运输段集合（一对多；has_leg 边声明在 TransportLeg 侧）
/// Set of transport legs (one-to-many; has_leg edge declared on the TransportLeg side)
Relationship Legs As Logistics.Transport.TransportLeg [ Cardinality = many, Inverse = Shipment ];

Storage Default
{
<Data name="ShipmentDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>ShipmentNo</Value>
</Value>
<Value name="3">
<Value>Mode</Value>
</Value>
<Value name="4">
<Value>Origin</Value>
</Value>
<Value name="5">
<Value>Destination</Value>
</Value>
<Value name="6">
<Value>ETA</Value>
</Value>
<Value name="7">
<Value>Status</Value>
</Value>
</Data>
<DataLocation>^Logistics.Transport.ShipmentD</DataLocation>
<DefaultData>ShipmentDefaultData</DefaultData>
<IdLocation>^Logistics.Transport.ShipmentD</IdLocation>
<IndexLocation>^Logistics.Transport.ShipmentI</IndexLocation>
<StreamLocation>^Logistics.Transport.ShipmentS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndex On (Destination, Origin) As Graph.Object.Index;

}
