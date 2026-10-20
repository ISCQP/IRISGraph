/// 风险航路影响（连接节点）：某风险事件对某航段的具体影响及严重程度。
/// Risk route impact (connecting node): the specific impact and severity of a risk event on a route segment.
/// riskimpact_of_risk / riskimpact_of_segment 使影响从 RiskEvent 与 RouteSegment 双向可达。
/// riskimpact_of_risk / riskimpact_of_segment make the impact bidirectionally reachable from both RiskEvent and RouteSegment.
/// Author: QP
/// Version: 1.0
Class Logistics.Risk.RouteImpact Extends (%Persistent, Graph.Object.Base)
{

/// 风险事件（多对一；riskimpact_of_risk：RiskEvent → RouteImpact）
/// Risk event (many-to-one; riskimpact_of_risk: RiskEvent → RouteImpact)
Relationship RiskEvent As Logistics.Risk.RiskEvent(Direction = "FROM", Relation = "riskimpact_of_risk") [ Cardinality = one, Inverse = RouteImpacts ];

/// 受影响航段（多对一；riskimpact_of_segment：RouteSegment → RouteImpact）
/// Affected route segment (many-to-one; riskimpact_of_segment: RouteSegment → RouteImpact)
Relationship RouteSegment As Logistics.Route.RouteSegment(Direction = "FROM", Relation = "riskimpact_of_segment") [ Cardinality = one, Inverse = RouteImpacts ];

/// 影响严重程度（数值越大越严重）
/// Impact severity (higher value means more severe)
Property Severity As %Integer;

Storage Default
{
<Data name="RouteImpactDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>RiskEvent</Value>
</Value>
<Value name="3">
<Value>RouteSegment</Value>
</Value>
<Value name="4">
<Value>Severity</Value>
</Value>
</Data>
<DataLocation>^Logistics.Risk.RouteImpactD</DataLocation>
<DefaultData>RouteImpactDefaultData</DefaultData>
<IdLocation>^Logistics.Risk.RouteImpactD</IdLocation>
<IndexLocation>^Logistics.Risk.RouteImpactI</IndexLocation>
<StreamLocation>^Logistics.Risk.RouteImpactS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndex On (RiskEvent, RouteSegment) As Graph.Object.Index;

}
