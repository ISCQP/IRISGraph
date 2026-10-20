/// 供应商节点：提供产品的企业，含分级、行业与风险评分，用于供应链风险与替代供应商推理。
/// Supplier node: an enterprise that provides products, with tier, industry and risk score, used for supply chain risk and alternative supplier reasoning.
/// supplies 边（Supplier → Product）声明在 Product 侧。
/// The supplies edge (Supplier → Product) is declared on the Product side.
/// Author: QP
/// Version: 1.0
Class Logistics.Business.Supplier Extends (%Persistent, Graph.Object.Base)
{

/// 供应商编码
/// Supplier code
Property SupplierCode As %String;

/// 供应商名称
/// Supplier name
Property Name As %String;

/// 所在国家/地区（supplier_in_country）
/// Country/region located in (supplier_in_country)
Property Country As Logistics.Geography.Location(Direction = "FROM", Relation = "supplier_in_country");

/// 供应商层级（如一级、二级供应商）
/// Supplier tier (e.g. tier-1, tier-2 supplier)
Property Tier As %Integer;

/// 所属行业
/// Industry
Property Industry As %String;

/// 风险评分（数值越高风险越大）
/// Risk score (higher value means higher risk)
Property RiskScore As %Double;

/// 供应的产品集合（一对多；supplies 边声明在 Product 侧）
/// Set of supplied products (one-to-many; the supplies edge is declared on the Product side)
Relationship Products As Logistics.Business.Product [ Cardinality = many, Inverse = Supplier ];

Storage Default
{
<Data name="SupplierDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>SupplierCode</Value>
</Value>
<Value name="3">
<Value>Name</Value>
</Value>
<Value name="4">
<Value>Country</Value>
</Value>
<Value name="5">
<Value>Tier</Value>
</Value>
<Value name="6">
<Value>Industry</Value>
</Value>
<Value name="7">
<Value>RiskScore</Value>
</Value>
</Data>
<DataLocation>^Logistics.Business.SupplierD</DataLocation>
<DefaultData>SupplierDefaultData</DefaultData>
<IdLocation>^Logistics.Business.SupplierD</IdLocation>
<IndexLocation>^Logistics.Business.SupplierI</IndexLocation>
<StreamLocation>^Logistics.Business.SupplierS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndex On (Country) As Graph.Object.Index;

}
