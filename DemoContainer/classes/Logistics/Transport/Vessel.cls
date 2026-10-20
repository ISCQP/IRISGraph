/// 船舶节点：海运运输资产，含 IMO/MMSI/吃水；assigned_to 关联航次（边声明在 Voyage 侧）。
/// Vessel node: a sea transport asset, including IMO/MMSI/draft; assigned_to links to voyages (edge declared on the Voyage side).
/// Author: QP
/// Version: 1.0
Class Logistics.Transport.Vessel Extends Logistics.Transport.TransportAsset
{

/// 国际海事组织编号 (IMO Number)
/// International Maritime Organization number (IMO Number)
Property IMO As %String;

/// 水上移动通信业务标识码 (MMSI)
/// Maritime Mobile Service Identity (MMSI)
Property MMSI As %String;

/// 吃水深度
/// Draft depth
Property Draft As %Double;

/// 该船执行的航次集合（一对多；assigned_to 边声明在 Voyage 侧）
/// Set of voyages executed by this vessel (one-to-many; assigned_to edge declared on the Voyage side)
Relationship Voyages As Logistics.Route.Voyage [ Cardinality = many, Inverse = Vessel ];

Storage Default
{
<Data name="VesselDefaultData">
<Subscript>"Vessel"</Subscript>
<Value name="1">
<Value>IMO</Value>
</Value>
<Value name="2">
<Value>MMSI</Value>
</Value>
<Value name="3">
<Value>Draft</Value>
</Value>
</Data>
<DefaultData>VesselDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
