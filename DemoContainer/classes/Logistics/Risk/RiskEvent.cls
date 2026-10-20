/// 风险事件节点：地缘冲突、台风、地震、海盗、罢工、港口拥堵/关闭、疫情等；作为独立节点而非属性。
/// Risk event node: geopolitical conflict, typhoon, earthquake, piracy, strike, port congestion/closure, pandemic, etc.; modeled as an independent node rather than an attribute.
/// affects_segment 直接影响航段；risk_at_location 定位；经 RouteImpact / Impact 向下游传播。
/// affects_segment directly affects route segments; risk_at_location for positioning; propagates downstream via RouteImpact / Impact.
/// Author: QP
/// Version: 1.0
Class Logistics.Risk.RiskEvent Extends (%Persistent, Graph.Object.Base)
{

/// 风险事件名称
/// Risk event name
Property Name As %String;

/// 风险类型
/// Risk type
Property Type As %String(VALUELIST = ",Weather,Typhoon,Earthquake,Flood,Piracy,War,Strike,PortCongestion,PortClosure,Accident,Pandemic");

/// 严重程度（数值越大越严重）
/// Severity (higher value means more severe)
Property Severity As %Integer;

/// 开始时间
/// Start time
Property StartTime As %TimeStamp;

/// 结束时间
/// End time
Property EndTime As %TimeStamp;

/// 影响半径（公里，如台风）
/// Impact radius (kilometers, e.g. typhoon)
Property Radius As %Double;

/// 风力/强度（如台风风速）
/// Wind force/intensity (e.g. typhoon wind speed)
Property WindSpeed As %Double;

/// 预报/描述
/// Forecast/description
Property Forecast As %String(MAXLEN = 2000);

/// 发生/中心位置（risk_at_location）
/// Occurrence/center location (risk_at_location)
Property Location As Logistics.Geography.Location(Direction = "FROM", Relation = "risk_at_location");

/// 直接影响的航段集合（affects_segment：RiskEvent → RouteSegment）
/// Set of directly affected route segments (affects_segment: RiskEvent → RouteSegment)
Property AffectedSegments As list Of Logistics.Route.RouteSegment(Direction = "FROM", Relation = "affects_segment");

/// 该风险的航路影响明细集合（一对多；边声明在 RouteImpact 侧）
/// Set of route impact details for this risk (one-to-many; edge declared on the RouteImpact side)
Relationship RouteImpacts As Logistics.Risk.RouteImpact [ Cardinality = many, Inverse = RiskEvent ];

Storage Default
{
<Data name="RiskEventDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Name</Value>
</Value>
<Value name="3">
<Value>Type</Value>
</Value>
<Value name="4">
<Value>Severity</Value>
</Value>
<Value name="5">
<Value>StartTime</Value>
</Value>
<Value name="6">
<Value>EndTime</Value>
</Value>
<Value name="7">
<Value>Radius</Value>
</Value>
<Value name="8">
<Value>WindSpeed</Value>
</Value>
<Value name="9">
<Value>Forecast</Value>
</Value>
<Value name="10">
<Value>Location</Value>
</Value>
<Value name="11">
<Value>AffectedSegments</Value>
</Value>
</Data>
<DataLocation>^Logistics.Risk.RiskEventD</DataLocation>
<DefaultData>RiskEventDefaultData</DefaultData>
<IdLocation>^Logistics.Risk.RiskEventD</IdLocation>
<IndexLocation>^Logistics.Risk.RiskEventI</IndexLocation>
<StreamLocation>^Logistics.Risk.RiskEventS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndex On (Location) As Graph.Object.Index;

Index GraphIndexEAffectedSegments On (AffectedSegments(ELEMENTS)) As Graph.Object.Index;

}
