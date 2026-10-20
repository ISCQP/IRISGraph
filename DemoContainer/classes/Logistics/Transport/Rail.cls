/// 铁路车辆节点：铁运运输资产，继承 TransportAsset 公共字段。
/// Rail vehicle node: a rail transport asset, inheriting the common fields of TransportAsset.
/// Author: QP
/// Version: 1.0
Class Logistics.Transport.Rail Extends Logistics.Transport.TransportAsset
{

/// 车皮/车厢编号
/// Wagon/car number
Property WagonNo As %String;

Storage Default
{
<Data name="RailDefaultData">
<Subscript>"Rail"</Subscript>
<Value name="1">
<Value>WagonNo</Value>
</Value>
</Data>
<DefaultData>RailDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
