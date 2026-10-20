/// 贸易政策/法规节点：关税、制裁、出口管制、进口限制、CBAM 等；通过 affects 边作用于 HS Code，
/// Trade policy/regulation node: tariffs, sanctions, export controls, import restrictions, CBAM, etc.; acts on HS Code via the affects edge,
/// 进而沿 HSCode ← Product ← PO ← Shipment 传播，快速识别受影响的货运。
/// then propagates along HSCode ← Product ← PO ← Shipment to quickly identify affected shipments.
/// Author: QP
/// Version: 1.0
Class Logistics.Policy.Policy Extends (%Persistent, Graph.Object.Base)
{

/// 政策名称
/// Policy name
Property Name As %String;

/// 适用国家/地区（policy_in_country）
/// Applicable country/region (policy_in_country)
Property Country As Logistics.Geography.Location(Direction = "FROM", Relation = "policy_in_country");

/// 生效日期
/// Effective date
Property EffectiveDate As %Date;

/// 政策类型
/// Policy type
Property Type As %String(VALUELIST = ",Tariff,Sanction,ExportControl,ImportRestriction,CBAM");

/// 作用的 HS 编码集合（affects：Policy → HSCode）
/// Set of affected HS codes (affects: Policy → HSCode)
Property AffectedHSCodes As list Of Logistics.Policy.HSCode(Direction = "FROM", Relation = "policy_affects_hscode");

Storage Default
{
<Data name="PolicyDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Name</Value>
</Value>
<Value name="3">
<Value>Country</Value>
</Value>
<Value name="4">
<Value>EffectiveDate</Value>
</Value>
<Value name="5">
<Value>Type</Value>
</Value>
<Value name="6">
<Value>AffectedHSCodes</Value>
</Value>
</Data>
<DataLocation>^Logistics.Policy.PolicyD</DataLocation>
<DefaultData>PolicyDefaultData</DefaultData>
<IdLocation>^Logistics.Policy.PolicyD</IdLocation>
<IndexLocation>^Logistics.Policy.PolicyI</IndexLocation>
<StreamLocation>^Logistics.Policy.PolicyS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndex On (Country) As Graph.Object.Index;

Index GraphIndexEAffectedHSCodes On (AffectedHSCodes(ELEMENTS)) As Graph.Object.Index;

}
