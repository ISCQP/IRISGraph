/// 接触追踪的**时空在场**原子事实表：某人于某时间窗出现在某地点。
/// Spatiotemporal PRESENCE fact for contact tracing: a person was at a location during a time window.
/// 
/// 这是三间分析（人际 / 时间 / 空间）的最小事实：人-地-时。人际接触是**派生**的——两条在场
/// 记录在同一地点且时间窗重叠时，才产生一条 CTContact 人-人接触边。EMR 里这张表天然来自
/// 就诊/移动事件 HS.SDA3.Encounter（putEvent 的 eventStartDate/eventEndDate + institution）。
/// This is the atomic fact of the 3-axis (person/time/space) model. Person-person contact is DERIVED:
/// two presences that share a location and overlap in time yield one CTContact edge. In an EMR this
/// table falls out of encounter/ADT events (HS.SDA3.Encounter: eventStartDate/eventEndDate + institution).
/// Author: QP
/// Version: 1.0
/// Last Modified Date: 2026/08/11
Class EMR.Test.CTPresence Extends %Persistent [ DdlAllowed ]
{

Property PersonId As %Integer;

Property LocId As %Integer;

Property TStart As %Integer;

Property TEnd As %Integer;

Index PersonIdx On PersonId;

Index LocIdx On LocId;

Storage Default
{
<Data name="CTPresenceDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>PersonId</Value>
</Value>
<Value name="3">
<Value>LocId</Value>
</Value>
<Value name="4">
<Value>TStart</Value>
</Value>
<Value name="5">
<Value>TEnd</Value>
</Value>
</Data>
<DataLocation>^EMR.Test.CTPresenceD</DataLocation>
<DefaultData>CTPresenceDefaultData</DefaultData>
<IdLocation>^EMR.Test.CTPresenceD</IdLocation>
<IndexLocation>^EMR.Test.CTPresenceI</IndexLocation>
<StreamLocation>^EMR.Test.CTPresenceS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
