/// 卡车节点：公路运输资产，继承 TransportAsset 公共字段。
/// Truck node: a road transport asset, inheriting the common fields of TransportAsset.
/// Author: QP
/// Version: 1.0
Class Logistics.Transport.Truck Extends Logistics.Transport.TransportAsset
{

/// 车牌号
/// License plate number
Property PlateNumber As %String;

Storage Default
{
<Data name="TruckDefaultData">
<Subscript>"Truck"</Subscript>
<Value name="1">
<Value>PlateNumber</Value>
</Value>
</Data>
<DefaultData>TruckDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
