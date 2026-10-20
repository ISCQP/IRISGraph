/// 采购订单节点：向供应商下达的采购单据；contains 关联产品，fulfilled_by 关联货运。
/// Purchase order node: a procurement document issued to a supplier; contains links to products, fulfilled_by links to a shipment.
/// Author: QP
/// Version: 1.0
Class Logistics.Business.PurchaseOrder Extends (%Persistent, Graph.Object.Base)
{

/// 采购订单号
/// Purchase order number
Property PONumber As %String;

/// 下单日期
/// Order date
Property OrderDate As %TimeStamp;

/// 预计到货时间
/// Expected arrival time
Property ExpectedArrival As %TimeStamp;

/// 订单状态
/// Order status
Property Status As %String;

/// 订单包含的产品集合（contains：PO → Product）
/// Set of products contained in the order (contains: PO → Product)
Property Products As list Of Logistics.Business.Product(Direction = "FROM", Relation = "po_contains_product");

/// 履约该订单的货运（fulfilled_by：PO → Shipment）
/// The shipment that fulfills this order (fulfilled_by: PO → Shipment)
Property Shipment As Logistics.Transport.Shipment(Direction = "FROM", Relation = "fulfilled_by");

Storage Default
{
<Data name="PurchaseOrderDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>PONumber</Value>
</Value>
<Value name="3">
<Value>OrderDate</Value>
</Value>
<Value name="4">
<Value>ExpectedArrival</Value>
</Value>
<Value name="5">
<Value>Status</Value>
</Value>
<Value name="6">
<Value>Products</Value>
</Value>
<Value name="7">
<Value>Shipment</Value>
</Value>
</Data>
<DataLocation>^Logistics.Bus31F.PurchaseOrderD</DataLocation>
<DefaultData>PurchaseOrderDefaultData</DefaultData>
<IdLocation>^Logistics.Bus31F.PurchaseOrderD</IdLocation>
<IndexLocation>^Logistics.Bus31F.PurchaseOrderI</IndexLocation>
<StreamLocation>^Logistics.Bus31F.PurchaseOrderS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

Index GraphIndex On (Shipment) As Graph.Object.Index;

Index GraphIndexEProducts On (Products(ELEMENTS)) As Graph.Object.Index;

}
