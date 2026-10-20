/// 销售订单节点：面向客户的销售单据；contains 关联产品，可与采购/货运联动做收入风险推理。
/// Sales order node: a customer-facing sales document; contains links to products, and can be combined with procurement/shipment for revenue risk reasoning.
/// Author: QP
/// Version: 1.0
Class Logistics.Business.SalesOrder Extends (%Persistent, Graph.Object.Base)
{

/// 销售订单号
/// Sales order number
Property SONumber As %String;

/// 下单日期
/// Order date
Property OrderDate As %TimeStamp;

/// 客户名称
/// Customer name
Property Customer As %String;

/// 订单状态
/// Order status
Property Status As %String;

/// 订单包含的产品集合（contains：SalesOrder → Product）
/// Set of products contained in the order (contains: SalesOrder → Product)
Property Products As list Of Logistics.Business.Product(Direction = "FROM", Relation = "so_contains_product");

Storage Default
{
<Data name="SalesOrderDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>SONumber</Value>
</Value>
<Value name="3">
<Value>OrderDate</Value>
</Value>
<Value name="4">
<Value>Customer</Value>
</Value>
<Value name="5">
<Value>Status</Value>
</Value>
<Value name="6">
<Value>Products</Value>
</Value>
</Data>
<DataLocation>^Logistics.Business.SalesOrderD</DataLocation>
<DefaultData>SalesOrderDefaultData</DefaultData>
<IdLocation>^Logistics.Business.SalesOrderD</IdLocation>
<IndexLocation>^Logistics.Business.SalesOrderI</IndexLocation>
<StreamLocation>^Logistics.Business.SalesOrderS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndexEProducts On (Products(ELEMENTS)) As Graph.Object.Index;

}
