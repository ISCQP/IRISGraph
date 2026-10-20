/// 地理位置节点（统一抽象）：国家/地区/城市/港口/机场/仓库/铁路场站/海域/大洋/航路点等物流网络节点。
/// Geographic location node (unified abstraction): logistics network nodes such as country/region/city/port/airport/warehouse/rail terminal/sea area/ocean/waypoint.
/// 通过 Type 区分子类型，避免为每种地点建独立类，便于图上统一做 passes_through / located_in 推理。
/// Subtypes are distinguished by Type, avoiding a separate class per location kind, enabling uniform passes_through / located_in reasoning on the graph.
/// Author: QP
/// Version: 1.0
Class Logistics.Geography.Location Extends (%Persistent, Graph.Object.Base)
{

/// 位置名称
/// Location name
Property Name As %String;

/// 纬度
/// Latitude
Property Latitude As %Double;

/// 经度
/// Longitude
Property Longitude As %Double;

/// 位置类型
/// Location type
Property Type As %String(VALUELIST = ",Country,Region,City,Port,Airport,Warehouse,RailTerminal,SeaArea,Ocean,Waypoint");

/// 上级归属位置（located_in：本位置 → 上级位置，如 Port located_in Country）
/// Parent location it belongs to (located_in: this location → parent location, e.g. Port located_in Country)
Property LocatedIn As Logistics.Geography.Location(Direction = "FROM", Relation = "located_in");

/// 连通的地点集合（connected_to，如 Port connected_to SeaArea）
/// Set of connected locations (connected_to, e.g. Port connected_to SeaArea)
Property ConnectedTo As list Of Logistics.Geography.Location(Direction = "FROM", Relation = "connected_to");

Storage Default
{
<Data name="LocationDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Name</Value>
</Value>
<Value name="3">
<Value>Latitude</Value>
</Value>
<Value name="4">
<Value>Longitude</Value>
</Value>
<Value name="5">
<Value>Type</Value>
</Value>
<Value name="6">
<Value>LocatedIn</Value>
</Value>
<Value name="7">
<Value>ConnectedTo</Value>
</Value>
</Data>
<DataLocation>^Logistics.Geography.LocationD</DataLocation>
<DefaultData>LocationDefaultData</DefaultData>
<IdLocation>^Logistics.Geography.LocationD</IdLocation>
<IndexLocation>^Logistics.Geography.LocationI</IndexLocation>
<StreamLocation>^Logistics.Geography.LocationS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndex On (LocatedIn) As Graph.Object.Index;

Index GraphIndexEConnectedTo On (ConnectedTo(ELEMENTS)) As Graph.Object.Index;

}
