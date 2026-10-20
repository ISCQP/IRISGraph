/// 运输资产基类节点：船舶/飞机/铁路/卡车的公共字段（定位、航向、状态）；at_location 关联当前位置。
/// Transport asset base node: common fields for vessel/aircraft/rail/truck (position, heading, status); at_location links to the current location.
/// 子类 Vessel/Aircraft/Rail/Truck 继承扩展各自专有字段。
/// Subclasses Vessel/Aircraft/Rail/Truck inherit and extend their own specific fields.
/// Author: QP
/// Version: 1.0
Class Logistics.Transport.TransportAsset Extends (%Persistent, Graph.Object.Base)
{

/// 资产编号
/// Asset identifier
Property AssetID As %String;

/// 资产名称
/// Asset name
Property Name As %String;

/// 运营方
/// Operator
Property Operator As %String;

/// 当前所在位置（asset_at_location）
/// Current location (asset_at_location)
Property CurrentLocation As Logistics.Geography.Location(Direction = "FROM", Relation = "asset_at_location");

/// 当前纬度
/// Current latitude
Property Latitude As %Double;

/// 当前经度
/// Current longitude
Property Longitude As %Double;

/// 当前速度
/// Current speed
Property Speed As %Double;

/// 航向（行进方向角度）
/// Heading (direction of travel in degrees)
Property Heading As %Double;

/// 当前状态
/// Current status
Property Status As %String;

Storage Default
{
<Data name="TransportAssetDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>AssetID</Value>
</Value>
<Value name="3">
<Value>Name</Value>
</Value>
<Value name="4">
<Value>Operator</Value>
</Value>
<Value name="5">
<Value>CurrentLocation</Value>
</Value>
<Value name="6">
<Value>Latitude</Value>
</Value>
<Value name="7">
<Value>Longitude</Value>
</Value>
<Value name="8">
<Value>Speed</Value>
</Value>
<Value name="9">
<Value>Heading</Value>
</Value>
<Value name="10">
<Value>Status</Value>
</Value>
</Data>
<DataLocation>^Logistics.T87FE.TransportAssetD</DataLocation>
<DefaultData>TransportAssetDefaultData</DefaultData>
<IdLocation>^Logistics.T87FE.TransportAssetD</IdLocation>
<IndexLocation>^Logistics.T87FE.TransportAssetI</IndexLocation>
<StreamLocation>^Logistics.T87FE.TransportAssetS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndex On (CurrentLocation) As Graph.Object.Index;

}
