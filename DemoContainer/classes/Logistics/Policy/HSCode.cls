/// Harmonized System Code (HS Code)
/// 国际商品统一分类编码：关税、贸易管制与合规分类的国际标准商品编码；作为 Product ↔ Policy 的连接节点。
/// International standard commodity classification code: the international standard product code for tariffs, trade control and compliance classification; serves as the connecting node between Product ↔ Policy.
/// Author: QP
/// Version: 1.0
Class Logistics.Policy.HSCode Extends (%Persistent, Graph.Object.Base)
{

/// HS 编码（协调制度编码）
/// HS code (Harmonized System code)
Property Code As %String;

/// 编码对应的商品描述
/// Commodity description for the code
Property Description As %String;

Storage Default
{
<Data name="HSCodeDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Code</Value>
</Value>
<Value name="3">
<Value>Description</Value>
</Value>
</Data>
<DataLocation>^Logistics.Policy.HSCodeD</DataLocation>
<DefaultData>HSCodeDefaultData</DefaultData>
<IdLocation>^Logistics.Policy.HSCodeD</IdLocation>
<IndexLocation>^Logistics.Policy.HSCodeI</IndexLocation>
<StreamLocation>^Logistics.Policy.HSCodeS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
