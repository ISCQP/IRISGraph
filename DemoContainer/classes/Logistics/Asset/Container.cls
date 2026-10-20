/// 集装箱节点（IoT 核心）：承载货物、搭载传感器；contains（来自 Shipment）、loaded_on 运输资产。
/// Container node (IoT core): carries cargo, mounts sensors; contains (from Shipment), loaded_on transport asset.
/// IoT 数据建议以 SensorReading 节点持续追加，快照字段仅保留最新值。
/// IoT data is recommended to be continuously appended as SensorReading nodes; snapshot fields keep only the latest value.
/// Author: QP
/// Version: 1.0
Class Logistics.Asset.Container Extends (%Persistent, Graph.Object.Base)
{

/// 集装箱编号
/// Container number
Property ContainerNo As %String;

/// ISO 箱型代码
/// ISO container type code
Property ISOCode As %String;

/// 箱主
/// Container owner
Property Owner As %String;

/// 当前状态
/// Current status
Property Status As %String;

/// 温度快照（最新值；历史见 SensorReading）
/// Temperature snapshot (latest value; history in SensorReading)
Property Temperature As %Double;

/// 湿度快照
/// Humidity snapshot
Property Humidity As %Double;

/// 箱门状态
/// Door status
Property DoorStatus As %String;

/// 电量
/// Battery level
Property Battery As %Double;

/// 震动
/// Shock
Property Shock As %Double;

/// 倾斜
/// Tilt
Property Tilt As %Double;

/// GPS 纬度快照（最新定位；历史见 SensorReading）
/// GPS latitude snapshot (latest position; history in SensorReading)
Property Latitude As %Double;

/// GPS 经度快照（最新定位；历史见 SensorReading）
/// GPS longitude snapshot (latest position; history in SensorReading)
Property Longitude As %Double;

/// 最近一次 GPS 定位时间
/// Time of the most recent GPS fix
Property LastGPSTime As %TimeStamp;

/// 所属货运（多对一；contains：Shipment → Container）
/// Owning shipment (many-to-one; contains: Shipment → Container)
Relationship Shipment As Logistics.Transport.Shipment(Direction = "FROM", Relation = "contains") [ Cardinality = one, Inverse = Containers ];

/// 当前装载的运输资产（loaded_on：Container → TransportAsset）
/// Currently loaded transport asset (loaded_on: Container → TransportAsset)
Property CurrentTransport As Logistics.Transport.TransportAsset(Direction = "FROM", Relation = "loaded_on");

/// 箱上安装的传感器集合（一对多；has_sensor 边声明在 Sensor 侧）
/// Set of sensors installed on the container (one-to-many; has_sensor edge declared on the Sensor side)
Relationship Sensors As Logistics.IoT.Sensor [ Cardinality = many, Inverse = Container ];

Storage Default
{
<Data name="ContainerDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>ContainerNo</Value>
</Value>
<Value name="3">
<Value>ISOCode</Value>
</Value>
<Value name="4">
<Value>Owner</Value>
</Value>
<Value name="5">
<Value>Status</Value>
</Value>
<Value name="6">
<Value>Temperature</Value>
</Value>
<Value name="7">
<Value>Humidity</Value>
</Value>
<Value name="8">
<Value>DoorStatus</Value>
</Value>
<Value name="9">
<Value>Battery</Value>
</Value>
<Value name="10">
<Value>Shock</Value>
</Value>
<Value name="11">
<Value>Tilt</Value>
</Value>
<Value name="12">
<Value>Shipment</Value>
</Value>
<Value name="13">
<Value>CurrentTransport</Value>
</Value>
<Value name="14">
<Value>Latitude</Value>
</Value>
<Value name="15">
<Value>Longitude</Value>
</Value>
<Value name="16">
<Value>LastGPSTime</Value>
</Value>
</Data>
<DataLocation>^Logistics.Asset.ContainerD</DataLocation>
<DefaultData>ContainerDefaultData</DefaultData>
<IdLocation>^Logistics.Asset.ContainerD</IdLocation>
<IndexLocation>^Logistics.Asset.ContainerI</IndexLocation>
<StreamLocation>^Logistics.Asset.ContainerS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndex On (CurrentTransport, Shipment) As Graph.Object.Index;

}
