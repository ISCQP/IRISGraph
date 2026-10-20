/// 传感器读数节点：某传感器在某时刻的一条测量值；has_reading（Sensor → SensorReading）。
/// Sensor reading node: a single measurement value of a sensor at a given moment; has_reading (Sensor → SensorReading).
/// 以追加方式记录时序数据，供趋势分析与异常检测。
/// Records time-series data in append mode, for trend analysis and anomaly detection.
/// Author: QP
/// Version: 1.0
Class Logistics.IoT.SensorReading Extends (%Persistent, Graph.Object.Base)
{

/// 所属传感器（多对一；has_reading：Sensor → SensorReading）
/// The sensor it belongs to (many-to-one; has_reading: Sensor → SensorReading)
Relationship Sensor As Logistics.IoT.Sensor(Direction = "FROM", Relation = "has_reading") [ Cardinality = one, Inverse = Readings ];

/// 采集时间戳
/// Collection timestamp
Property Timestamp As %TimeStamp;

/// 测量值
/// Measured value
Property Value As %Double;

Storage Default
{
<Data name="SensorReadingDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Sensor</Value>
</Value>
<Value name="3">
<Value>Timestamp</Value>
</Value>
<Value name="4">
<Value>Value</Value>
</Value>
</Data>
<DataLocation>^Logistics.IoT.SensorReadingD</DataLocation>
<DefaultData>SensorReadingDefaultData</DefaultData>
<IdLocation>^Logistics.IoT.SensorReadingD</IdLocation>
<IndexLocation>^Logistics.IoT.SensorReadingI</IndexLocation>
<StreamLocation>^Logistics.IoT.SensorReadingS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndex On (Sensor) As Graph.Object.Index;

}
