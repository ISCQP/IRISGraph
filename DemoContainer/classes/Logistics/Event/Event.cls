/// 领域事件节点：来自各类数据源的原始事件记录（集成入口/消息总线），用于回溯与审计。
/// Domain event node: raw event records from various data sources (integration entry point/message bus), used for traceback and audit.
/// Author: QP
/// Version: 1.0
Class Logistics.Event.Event Extends (%Persistent, Graph.Object.Base)
{

/// 事件来源系统/数据源
/// Event source system/data source
Property Source As %String;

/// 事件类型
/// Event type
Property Type As %String;

/// 事件发生时间戳
/// Event occurrence timestamp
Property Timestamp As %TimeStamp;

/// 事件负载（原始报文/JSON 内容）
/// Event payload (raw message/JSON content)
Property Payload As %String(MAXLEN = 100000);

Storage Default
{
<Data name="EventDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Source</Value>
</Value>
<Value name="3">
<Value>Type</Value>
</Value>
<Value name="4">
<Value>Timestamp</Value>
</Value>
<Value name="5">
<Value>Payload</Value>
</Value>
</Data>
<DataLocation>^Logistics.Event.EventD</DataLocation>
<DefaultData>EventDefaultData</DefaultData>
<IdLocation>^Logistics.Event.EventD</IdLocation>
<IndexLocation>^Logistics.Event.EventI</IndexLocation>
<StreamLocation>^Logistics.Event.EventS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
