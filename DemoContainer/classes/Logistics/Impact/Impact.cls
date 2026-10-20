/// 影响节点（建议由 AI 计算而非人工维护）：延误、库存风险、生产风险、收入风险、碳影响、
/// Impact node (recommended to be computed by AI rather than maintained manually): delay, inventory risk, production risk, revenue risk, carbon impact,
/// 替代航路/替代供应商等。causes（RiskEvent → Impact）承接风险，impact_affects_* 向下游传播，
/// alternative route/alternative supplier, etc. causes (RiskEvent → Impact) takes over the risk, impact_affects_* propagates downstream,
/// 形成完整影响传播链：Risk → Impact → Shipment / PO / Supplier。
/// forming a complete impact propagation chain: Risk → Impact → Shipment / PO / Supplier.
/// Author: QP
/// Version: 1.0
Class Logistics.Impact.Impact Extends (%Persistent, Graph.Object.Base)
{

/// 影响类型
/// Impact type
Property Type As %String(VALUELIST = ",Delay,InventoryRisk,ProductionRisk,RevenueRisk,CarbonImpact,AlternativeRoute,AlternativeSupplier");

/// 严重程度
/// Severity
Property Severity As %Integer;

/// 发生概率（0~1）
/// Occurrence probability (0~1)
Property Probability As %Double;

/// 延误时长（小时；Type=Delay 时有效）
/// Delay duration (hours; valid when Type=Delay)
Property DelayHours As %Double;

/// 影响天数（如库存可支撑/短缺天数）
/// Number of impacted days (e.g. inventory coverage/shortage days)
Property Days As %Double;

/// 描述
/// Description
Property Description As %String(MAXLEN = 2000);

/// 引发该影响的风险事件（causes：RiskEvent → Impact；Inverse=1 使边由风险指向影响）
/// Risk event that triggers this impact (causes: RiskEvent → Impact; Inverse=1 makes the edge point from risk to impact)
Property Cause As Logistics.Risk.RiskEvent(Direction = "FROM", Inverse = 1, Relation = "causes");

/// 受影响的货运（impact_affects_shipment：Impact → Shipment）
/// Affected shipment (impact_affects_shipment: Impact → Shipment)
Property AffectedShipment As Logistics.Transport.Shipment(Direction = "FROM", Relation = "impact_affects_shipment");

/// 受影响的采购订单（impact_affects_po：Impact → PurchaseOrder）
/// Affected purchase order (impact_affects_po: Impact → PurchaseOrder)
Property AffectedPO As Logistics.Business.PurchaseOrder(Direction = "FROM", Relation = "impact_affects_po");

/// 受影响的供应商（impact_affects_supplier：Impact → Supplier）
/// Affected supplier (impact_affects_supplier: Impact → Supplier)
Property AffectedSupplier As Logistics.Business.Supplier(Direction = "FROM", Relation = "impact_affects_supplier");

Storage Default
{
<Data name="ImpactDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Type</Value>
</Value>
<Value name="3">
<Value>Severity</Value>
</Value>
<Value name="4">
<Value>Probability</Value>
</Value>
<Value name="5">
<Value>DelayHours</Value>
</Value>
<Value name="6">
<Value>Days</Value>
</Value>
<Value name="7">
<Value>Description</Value>
</Value>
<Value name="8">
<Value>Cause</Value>
</Value>
<Value name="9">
<Value>AffectedShipment</Value>
</Value>
<Value name="10">
<Value>AffectedPO</Value>
</Value>
<Value name="11">
<Value>AffectedSupplier</Value>
</Value>
</Data>
<DataLocation>^Logistics.Impact.ImpactD</DataLocation>
<DefaultData>ImpactDefaultData</DefaultData>
<IdLocation>^Logistics.Impact.ImpactD</IdLocation>
<IndexLocation>^Logistics.Impact.ImpactI</IndexLocation>
<StreamLocation>^Logistics.Impact.ImpactS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndex On (AffectedPO, AffectedShipment, AffectedSupplier, Cause) As Graph.Object.Index;

}
