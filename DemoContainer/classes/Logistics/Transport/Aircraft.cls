/// 飞机节点：空运运输资产，继承 TransportAsset 公共字段。
/// Aircraft node: an air transport asset, inheriting the common fields of TransportAsset.
/// Author: QP
/// Version: 1.0
Class Logistics.Transport.Aircraft Extends Logistics.Transport.TransportAsset
{

/// ICAO 航空器/运营人代码
/// ICAO aircraft/operator code
Property ICAO As %String;

/// IATA 代码
/// IATA code
Property IATA As %String;

Storage Default
{
<Data name="AircraftDefaultData">
<Subscript>"Aircraft"</Subscript>
<Value name="1">
<Value>ICAO</Value>
</Value>
<Value name="2">
<Value>IATA</Value>
</Value>
</Data>
<DefaultData>AircraftDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
