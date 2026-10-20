/// 航路节点：由多个航段组成的运输路径。
/// Route node: a transport path composed of multiple route segments.
/// Author: QP
/// Version: 1.0
Class Logistics.Route.Route Extends (%Persistent, Graph.Object.Base)
{

/// 航路标识
/// Route identifier
Property RouteID As %String;

/// 航路名称
/// Route name
Property RouteName As %String;

/// 总距离
/// Total distance
Property Distance As %Double;

/// 预计总时长（小时）
/// Estimated total duration (hours)
Property EstimatedTime As %Double;

/// 组成该航路的航段集合（一对多；route_contains_segment 边声明在 RouteSegment 侧）
/// Set of segments composing this route (one-to-many; route_contains_segment edge declared on the RouteSegment side)
Relationship Segments As Logistics.Route.RouteSegment [ Cardinality = many, Inverse = Route ];

Storage Default
{
<Data name="RouteDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>RouteID</Value>
</Value>
<Value name="3">
<Value>RouteName</Value>
</Value>
<Value name="4">
<Value>Distance</Value>
</Value>
<Value name="5">
<Value>EstimatedTime</Value>
</Value>
</Data>
<DataLocation>^Logistics.Route.RouteD</DataLocation>
<DefaultData>RouteDefaultData</DefaultData>
<IdLocation>^Logistics.Route.RouteD</IdLocation>
<IndexLocation>^Logistics.Route.RouteI</IndexLocation>
<StreamLocation>^Logistics.Route.RouteS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
