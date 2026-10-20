/// 图定义参数类
/// Graph definition parameter class
/// Author: QP
/// Version: 1.0
/// Last Modified Date: 2026/03/11
Class Graph.Object.PropertyParameters [ System = 2 ]
{

/// 边的类型
/// Edge type
/// 例如：Inquiry-Supplier
/// e.g.: Inquiry-Supplier
Parameter Relation As STRING;

/// 边的方向
/// Edge direction
Parameter Direction As STRING [ Constraint = "FROM,TO", Flags = ENUM ];

/// 是否按反方向记录边
/// Whether to record the edge in the reverse direction
Parameter Inverse As STRING [ Constraint = "1,0", Flags = ENUM ];

/// 是否用图表达
/// Whether to express as a graph
Parameter GraphUse As BOOLEAN;

}
