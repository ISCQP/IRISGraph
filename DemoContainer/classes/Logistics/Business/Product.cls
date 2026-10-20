/// 产品/物料节点：可被采购与运输的商品；classified_as 关联 HS 编码，supplies 关联供应商。
/// Product/material node: goods that can be purchased and shipped; classified_as links to HS code, supplies links to supplier.
/// Author: QP
/// Version: 1.0
Class Logistics.Business.Product Extends (%Persistent, Graph.Object.Base)
{

/// 库存单位编码 (Stock Keeping Unit)
/// Stock Keeping Unit code
Property SKU As %String;

/// 产品名称/描述
/// Product name/description
Property Name As %String;

/// 归类的 HS 海关编码（classified_as：Product → HSCode）
/// Classified HS customs code (classified_as: Product → HSCode)
Property HSCode As Logistics.Policy.HSCode(Direction = "FROM", Relation = "classified_as");

/// 重量
/// Weight
Property Weight As %Double;

/// 体积
/// Volume
Property Volume As %Double;

/// 温控要求（如冷藏、冷冻）
/// Temperature control requirement (e.g. refrigerated, frozen)
Property TemperatureRequirement As %String;

/// 供应该产品的供应商（多对一；supplies：Supplier → Product）
/// The supplier that supplies this product (many-to-one; supplies: Supplier → Product)
Relationship Supplier As Logistics.Business.Supplier(Direction = "FROM", Relation = "supplies") [ Cardinality = one, Inverse = Products ];

Storage Default
{
<Data name="ProductDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>SKU</Value>
</Value>
<Value name="3">
<Value>Name</Value>
</Value>
<Value name="4">
<Value>HSCode</Value>
</Value>
<Value name="5">
<Value>Weight</Value>
</Value>
<Value name="6">
<Value>Volume</Value>
</Value>
<Value name="7">
<Value>TemperatureRequirement</Value>
</Value>
<Value name="8">
<Value>Supplier</Value>
</Value>
</Data>
<DataLocation>^Logistics.Business.ProductD</DataLocation>
<DefaultData>ProductDefaultData</DefaultData>
<IdLocation>^Logistics.Business.ProductD</IdLocation>
<IndexLocation>^Logistics.Business.ProductI</IndexLocation>
<StreamLocation>^Logistics.Business.ProductS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndex On (HSCode, Supplier) As Graph.Object.Index;

}
