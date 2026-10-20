/// 航段节点（图推理最关键）：航路中的一段；route_contains_segment 关联航路，
/// Route segment node (most critical for graph reasoning): a leg of a route; route_contains_segment links to the route,
/// passes_through 关联途经地点，affects_segment（来自 RiskEvent）承接风险影响。
/// passes_through links to waypoints, affects_segment (from RiskEvent) takes over the risk impact.
/// Author: QP
/// Version: 1.0
Class Logistics.Route.RouteSegment Extends (%Persistent, Graph.Object.Base)
{

/// 航段标识
/// Segment identifier
Property SegmentID As %String;

/// 航段名称（如 Taiwan Strait / Bab el-Mandeb / Singapore Strait）
/// Segment name (e.g. Taiwan Strait / Bab el-Mandeb / Singapore Strait)
Property Name As %String;

/// 航段在所属航路中的顺序（从 1 起，用于按航次出发时间推算船到达该航段的时间窗）
/// Sequence of the segment within its route (starting from 1; used to estimate the time window of a vessel reaching this segment based on voyage departure time)
Property Sequence As %Integer;

/// 航段距离
/// Segment distance
Property Distance As %Double;

/// 预计时长（小时）
/// Expected duration (hours)
Property ExpectedDuration As %Double;

/// 所属航路（多对一；route_contains_segment：Route → RouteSegment）
/// Owning route (many-to-one; route_contains_segment: Route → RouteSegment)
Relationship Route As Logistics.Route.Route(Direction = "FROM", Relation = "route_contains_segment") [ Cardinality = one, Inverse = Segments ];

/// 起点位置（segment_start）
/// Start location (segment_start)
Property StartLocation As Logistics.Geography.Location(Direction = "FROM", Relation = "segment_start");

/// 终点位置（segment_end）
/// End location (segment_end)
Property EndLocation As Logistics.Geography.Location(Direction = "FROM", Relation = "segment_end");

/// 途经地点集合（passes_through：RouteSegment → Location）
/// Set of waypoints (passes_through: RouteSegment → Location)
Property PassesThrough As list Of Logistics.Geography.Location(Direction = "FROM", Relation = "passes_through");

/// 该航段承受的风险影响集合（一对多；边声明在 RouteImpact 侧）
/// Set of risk impacts borne by this segment (one-to-many; edge declared on the RouteImpact side)
Relationship RouteImpacts As Logistics.Risk.RouteImpact [ Cardinality = many, Inverse = RouteSegment ];

Storage Default
{
<Data name="RouteSegmentDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>SegmentID</Value>
</Value>
<Value name="3">
<Value>Name</Value>
</Value>
<Value name="4">
<Value>Distance</Value>
</Value>
<Value name="5">
<Value>ExpectedDuration</Value>
</Value>
<Value name="6">
<Value>Route</Value>
</Value>
<Value name="7">
<Value>StartLocation</Value>
</Value>
<Value name="8">
<Value>EndLocation</Value>
</Value>
<Value name="9">
<Value>PassesThrough</Value>
</Value>
<Value name="10">
<Value>Sequence</Value>
</Value>
</Data>
<DataLocation>^Logistics.Route.RouteSegmentD</DataLocation>
<DefaultData>RouteSegmentDefaultData</DefaultData>
<IdLocation>^Logistics.Route.RouteSegmentD</IdLocation>
<IndexLocation>^Logistics.Route.RouteSegmentI</IndexLocation>
<StreamLocation>^Logistics.Route.RouteSegmentS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndex On (EndLocation, Route, StartLocation) As Graph.Object.Index;

Index GraphIndexEPassesThrough On (PassesThrough(ELEMENTS)) As Graph.Object.Index;

}
