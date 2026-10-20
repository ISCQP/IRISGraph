/// 运输段节点：Shipment 的一段运输（如 仓库→港口→船→目的港→客户），统一多式联运各段。
/// Transport leg node: a leg of a Shipment (e.g. warehouse→port→ship→destination port→customer), unifying the legs of multimodal transport.
/// has_leg 关联货运，leg_uses_asset 关联运输资产，leg_start/leg_end 关联起止位置。
/// has_leg links to the shipment, leg_uses_asset links to the transport asset, leg_start/leg_end link to the start/end locations.
/// Author: QP
/// Version: 1.0
Class Logistics.Transport.TransportLeg Extends (%Persistent, Graph.Object.Base)
{

/// 运输段序号
/// Transport leg number
Property LegNo As %Integer;

/// 运输方式（Truck/Ship/Rail/Air）
/// Transport mode (Truck/Ship/Rail/Air)
Property Mode As %String;

/// 起点位置（leg_start）
/// Start location (leg_start)
Property StartLocation As Logistics.Geography.Location(Direction = "FROM", Relation = "leg_start");

/// 终点位置（leg_end）
/// End location (leg_end)
Property EndLocation As Logistics.Geography.Location(Direction = "FROM", Relation = "leg_end");

/// 预计时长（小时）
/// Expected duration (hours)
Property Duration As %Double;

/// 预计到达时间
/// Estimated time of arrival
Property ETA As %TimeStamp;

/// 状态
/// Status
Property Status As %String;

/// 所属货运（多对一；has_leg：Shipment → TransportLeg）
/// Owning shipment (many-to-one; has_leg: Shipment → TransportLeg)
Relationship Shipment As Logistics.Transport.Shipment(Direction = "FROM", Relation = "has_leg") [ Cardinality = one, Inverse = Legs ];

/// 执行该段的运输资产（leg_uses_asset：TransportLeg → TransportAsset）
/// Transport asset executing this leg (leg_uses_asset: TransportLeg → TransportAsset)
Property Asset As Logistics.Transport.TransportAsset(Direction = "FROM", Relation = "leg_uses_asset");

Storage Default
{
<Data name="TransportLegDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>LegNo</Value>
</Value>
<Value name="3">
<Value>Mode</Value>
</Value>
<Value name="4">
<Value>StartLocation</Value>
</Value>
<Value name="5">
<Value>EndLocation</Value>
</Value>
<Value name="6">
<Value>Duration</Value>
</Value>
<Value name="7">
<Value>ETA</Value>
</Value>
<Value name="8">
<Value>Status</Value>
</Value>
<Value name="9">
<Value>Shipment</Value>
</Value>
<Value name="10">
<Value>Asset</Value>
</Value>
</Data>
<DataLocation>^Logistics.Tra87FE.TransportLegD</DataLocation>
<DefaultData>TransportLegDefaultData</DefaultData>
<IdLocation>^Logistics.Tra87FE.TransportLegD</IdLocation>
<IndexLocation>^Logistics.Tra87FE.TransportLegI</IndexLocation>
<StreamLocation>^Logistics.Tra87FE.TransportLegS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndex On (Asset, EndLocation, Shipment, StartLocation) As Graph.Object.Index;

}
