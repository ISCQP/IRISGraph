/// IoT 传感器节点：安装于集装箱，采集温度/湿度/位置等；has_sensor（Container → Sensor）。
/// IoT sensor node: installed on a container, collecting temperature/humidity/location, etc.; has_sensor (Container → Sensor).
/// Author: QP
/// Version: 1.0
Class Logistics.IoT.Sensor Extends (%Persistent, Graph.Object.Base)
{

/// 传感器编号
/// Sensor ID
Property SensorID As %String;

/// 传感器类型（如温度、湿度、震动、GPS）
/// Sensor type (e.g. temperature, humidity, vibration, GPS)
Property Type As %String;

/// 计量单位
/// Unit of measurement
Property Unit As %String;

/// 所属集装箱（多对一；has_sensor：Container → Sensor）
/// The container it belongs to (many-to-one; has_sensor: Container → Sensor)
Relationship Container As Logistics.Asset.Container(Direction = "FROM", Relation = "has_sensor") [ Cardinality = one, Inverse = Sensors ];

/// 该传感器的读数集合（一对多；has_reading 边声明在 SensorReading 侧）
/// Set of readings for this sensor (one-to-many; the has_reading edge is declared on the SensorReading side)
Relationship Readings As Logistics.IoT.SensorReading [ Cardinality = many, Inverse = Sensor ];

Storage Default
{
<Data name="SensorDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>SensorID</Value>
</Value>
<Value name="3">
<Value>Type</Value>
</Value>
<Value name="4">
<Value>Unit</Value>
</Value>
<Value name="5">
<Value>Container</Value>
</Value>
</Data>
<DataLocation>^Logistics.IoT.SensorD</DataLocation>
<DefaultData>SensorDefaultData</DefaultData>
<IdLocation>^Logistics.IoT.SensorD</IdLocation>
<IndexLocation>^Logistics.IoT.SensorI</IndexLocation>
<StreamLocation>^Logistics.IoT.SensorS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndex On (Container) As Graph.Object.Index;

}
