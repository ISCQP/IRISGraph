Include %occInclude

/// 图索引（自定义功能索引 Custom Functional Index）
/// Graph index (custom functional index)
/// 
/// 在对象/SQL 记录的插入、更新、删除时自动维护图数据 ^GraphData.OUT / ^GraphData.OWN。
/// Automatically maintains graph data ^GraphData.OUT / ^GraphData.OWN on object/SQL record insert, update, and delete.
/// 图字典 ^GraphData.Dic 仍由 Graph.Object.Base 的 GraphDictionary() 在编译期维护。
/// The graph dictionary ^GraphData.Dic is still maintained at compile time by GraphDictionary() of Graph.Object.Base.
/// 
/// 索引由 Graph.Object.IndexProjection 在每个 Graph.Object.Base 具体子类编译时自动注入，无需手工声明：
/// The index is auto-injected by Graph.Object.IndexProjection when each concrete Graph.Object.Base subclass is compiled; no manual declaration needed:
///     GraphIndex             -- 所有标量图属性
///     GraphIndex             -- all scalar graph properties
///     GraphIndexE<集合属性>   -- 每个 list/array 图属性（On Prop(ELEMENTS)，子值填充触发维护）
///     GraphIndexE<CollectionProp>  -- each list/array graph property (On Prop(ELEMENTS), sub-value population triggers maintenance)
/// 维护时会扫描本类所有带 Direction 的图属性并重建全部图边（幂等），
/// During maintenance it scans all graph properties of this class that have Direction and rebuilds all graph edges (idempotent),
/// 因此多个索引同时触发只会造成重复但正确的重建。
/// so multiple indices triggering at once only cause a duplicate but correct rebuild.
/// 
/// 存储：
/// Storage:
///     ^GraphData.OUT(Layer, SourceNodeOID, TargetNodeOID, Relation) = ""         // 图边（供查询）
///     ^GraphData.OUT(Layer, SourceNodeOID, TargetNodeOID, Relation) = ""         // graph edge (for queries)
///     ^GraphData.OWN(Layer, OwnerNodeOID, SourceNodeOID, Relation, TargetNodeOID) = ""    // 各节点拥有的边（供增删改维护）
///     ^GraphData.OWN(Layer, OwnerNodeOID, SourceNodeOID, Relation, TargetNodeOID) = ""    // edges owned by each node (for insert/update/delete maintenance)
///     ^GraphData.Dic(SourceType, Relation, TargetType, Inverse) = PropName         // 图字典（由 Graph.Object.Base 维护）
///     ^GraphData.Dic(SourceType, Relation, TargetType, Inverse) = PropName         // graph dictionary (maintained by Graph.Object.Base)
///     其中 NodeOID = $ListBuild(Id, ClassName)
///     where NodeOID = $ListBuild(Id, ClassName)
/// 
/// Author: QP
/// Version: 2.0
/// Last Modified Date: 2026/07/26
Class Graph.Object.Index Extends %Library.FunctionalIndex [ System = 3 ]
{

/// 插入记录：扫描本类所有图属性（带 Direction 参数），为每个非空属性新增出边
/// Insert record: scan all graph properties of this class (with Direction parameter) and add an outgoing edge for each non-empty property
ClassMethod InsertIndex(pID As %RawString, pArg... As %Binary) [ CodeMode = generator, ServerOnly = 1 ]
{
    If %mode = "method" Quit $$$OK

    Set tGP = ..genGraphProps(%class)
    Quit:$ListLength(tGP)=0 $$$OK

    $$$GENERATE(" Set tOwner = $ListBuild(pID_"""", """ _ %class _ """)")
    $$$GENERATE(" Set tObj = ..%OpenId(pID)")
    $$$GENERATE(" If $IsObject(tObj) {")
    Set tLines = ..genAddEdges(tGP)
    For tJ=1:1:$ListLength(tLines) { $$$GENERATE($ListGet(tLines, tJ)) }
    $$$GENERATE(" }")
    Quit $$$OK
}

/// 更新记录：先按 owner 清除本对象所有旧边，再按当前属性值重建边
/// Update record: first clear all old edges of this object by owner, then rebuild edges from current property values
ClassMethod UpdateIndex(pID As %RawString, pArg... As %Binary) [ CodeMode = generator, ServerOnly = 1 ]
{
    If %mode = "method" Quit $$$OK

    Set tGP = ..genGraphProps(%class)
    Quit:$ListLength(tGP)=0 $$$OK

    $$$GENERATE(" Set tOwner = $ListBuild(pID_"""", """ _ %class _ """)")
    $$$GENERATE(" Do ##class(Graph.Object.Index).RemoveOwned(tOwner)")
    $$$GENERATE(" Set tObj = ..%OpenId(pID)")
    $$$GENERATE(" If $IsObject(tObj) {")
    Set tLines = ..genAddEdges(tGP)
    For tJ=1:1:$ListLength(tLines) { $$$GENERATE($ListGet(tLines, tJ)) }
    $$$GENERATE(" }")
    Quit $$$OK
}

/// 删除记录：按 owner 清除本对象拥有的所有边（无需读取属性旧值）
/// Delete record: clear all edges owned by this object by owner (no need to read old property values)
ClassMethod DeleteIndex(pID As %RawString, pArg... As %Binary) [ CodeMode = generator, ServerOnly = 1 ]
{
    If %mode = "method" Quit $$$OK
    $$$GENERATE(" Do ##class(Graph.Object.Index).RemoveOwned($ListBuild(pID_"""", """ _ %class _ """))")
    Quit $$$OK
}

/// 清空索引：清除本类所有对象拥有的边（用于 BUILD INDEX 重建）
/// Purge index: clear edges owned by all objects of this class (used for BUILD INDEX rebuild)
ClassMethod PurgeIndex() [ CodeMode = generator, ServerOnly = 1 ]
{
    If %mode = "method" Quit $$$OK
    $$$GENERATE(" Do ##class(Graph.Object.Index).PurgeClass(""" _ %class _ """)")
    Quit $$$OK
}

/// 批量操作前置钩子（BUILD INDEX），空操作
/// Bulk operation pre-hook (BUILD INDEX), no-op
ClassMethod SortBeginIndex() [ CodeMode = generator, ServerOnly = 1 ]
{
    If %mode = "method" Quit $$$OK
    $$$GENERATE(" Quit")
    Quit $$$OK
}

/// 批量操作后置钩子（BUILD INDEX），空操作
/// Bulk operation post-hook (BUILD INDEX), no-op
ClassMethod SortEndIndex(pCommit As %Integer = 1) [ CodeMode = generator, ServerOnly = 1 ]
{
    If %mode = "method" Quit $$$OK
    $$$GENERATE(" Quit")
    Quit $$$OK
}

/// 运行期：新增一条图边，并登记到 owner 的拥有边集合
/// Runtime: add one graph edge and register it into the owner's owned-edge set
/// - 正向边 ^GraphData.OUT + 入边索引 ^GraphData.IN 统一经 Graph.Store.AddEdge 写入
/// - forward edge ^GraphData.OUT + incoming-edge index ^GraphData.IN are written uniformly via Graph.Store.AddEdge
/// - 拥有边 ^GraphData.OWN(ownerOID, 源OID, Relation, 目标OID) = "" 为模型图专有，由本类维护
/// - owned edge ^GraphData.OWN(ownerOID, SourceOID, Relation, TargetOID) = "" is specific to the model graph, maintained by this class
ClassMethod AddEdge(pSrc As %Binary, pRel As %String, pTgt As %Binary, pOwner As %Binary)
{
    Set tSC = $$$OK
    // 层不可写时直接抛出，避免对象保存成功而图边被默默丢弃
    // Throw when the layer is not writable so a save cannot silently drop graph edges
    Set tLayer = ##class(Graph.Object.Index).ownerLayer(pOwner)
    $$$ThrowOnError(##class(Graph.Layer).CheckWrite(tLayer))
    Try 
    {
        Do ##class(Graph.Store).AddEdge(pSrc, pRel, pTgt, 1, tLayer)          // 正向边 OUT + 入边索引 IN | forward edge OUT + incoming-edge index IN
        Set ^GraphData.OWN(tLayer, pOwner, pSrc, pRel, pTgt) = ""            // 拥有边 OWN（模型图专有，供增删改维护） | owned edge OWN (specific to the model graph, for insert/update/delete maintenance)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 解析 owner 所属的写入层：类参数 GRAPHLAYER > 进程上下文 > 默认写入层
/// Resolve the write layer of an owner: class parameter GRAPHLAYER > process context > default write layer
/// 注意：本类的方法会被复制进模型类，因此方法之间必须用 ##class(Graph.Object.Index) 全限定调用，不能用 ..
/// Note: this class's methods are copied into model classes, so they must call each other via ##class(Graph.Object.Index), never ..
ClassMethod ownerLayer(pOwner As %Binary) As %String [ Internal ]
{
    Quit ##class(Graph.Layer).WriteLayer($Select($ListValid(pOwner): ##class(Graph.Layer).ClassLayer($ListGet(pOwner, 2)), 1: ""))
}

/// 运行期：清除 owner 拥有的所有图边
/// Runtime: clear all graph edges owned by owner
ClassMethod RemoveOwned(pOwner As %Binary)
{
    // 逐层清除（即使类参数 GRAPHLAYER 后来改过，也不会漏删）；失败时抛出
    // Clear layer by layer (so a later GRAPHLAYER change cannot leave edges behind); throw on failure
    Set tLayer = ""
    For
    {
        Set tLayer = $Order(^GraphData.OWN(tLayer))
        Quit:tLayer=""
        Continue:'$Data(^GraphData.OWN(tLayer, pOwner))
        $$$ThrowOnError(##class(Graph.Object.Index).removeOwnedLayer(tLayer, pOwner))
    }
    Quit $$$OK
}

/// 清除 owner 在指定层拥有的图边 / Clear the edges owned by owner in one layer
ClassMethod removeOwnedLayer(pLayer As %String, pOwner As %Binary) As %Status [ Internal ]
{
    Set tSC = $$$OK
    Try 
    {
        Set tSrc = ""
        For 
        {
            Set tSrc = $Order(^GraphData.OWN(pLayer, pOwner, tSrc))
            Quit:tSrc=""
            Set tRel = ""
            For 
            {
                Set tRel = $Order(^GraphData.OWN(pLayer, pOwner, tSrc, tRel))
                Quit:tRel=""
                Set tTgt = ""
                For 
                {
                    Set tTgt = $Order(^GraphData.OWN(pLayer, pOwner, tSrc, tRel, tTgt))
                    Quit:tTgt=""
                    $$$ThrowOnError(##class(Graph.Store).RemoveEdge(tSrc, tRel, tTgt, 1, pLayer))   // 删正向边 OUT + 入边索引 IN | delete forward edge OUT + incoming-edge index IN
                }
            }
        }
        Kill ^GraphData.OWN(pLayer, pOwner)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 运行期：清除某个类的所有对象拥有的图边
/// Runtime: clear graph edges owned by all objects of a given class
ClassMethod PurgeClass(pClass As %String)
{
    Set tSC = $$$OK
    Try 
    {
        Set tLayers = ##class(Graph.Layer).Present()
        For tLI = 1:1:$ListLength(tLayers)
        {
        Set tLayer = $List(tLayers, tLI), tOwner = ""
        For 
        {
            Set tOwner = $Order(^GraphData.OWN(tLayer, tOwner))
            Quit:tOwner=""
            Continue:'$ListValid(tOwner)
            Continue:$List(tOwner,2)'=pClass
            Do ##class(Graph.Object.Index).RemoveOwned(tOwner)
        }
        }
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}

/// 编译期辅助：读取类参数 Auto（控制是否按 schema 自动为属性注入图参数），未定义时默认 "0"。
/// Compile-time helper: read class parameter Auto (controls whether graph parameters are auto-injected into properties by schema); defaults to "0" when undefined.
ClassMethod classAuto(pClass As %String) As %String [ Internal ]
{
    Set tP = ##class(%Dictionary.CompiledParameter).%OpenId(pClass _ "||Auto")
    Quit $Select($IsObject(tP):tP.Default, 1:"0")
}

/// 编译期辅助：在 Auto 语义下判定单个属性是否应成为“图属性”，并返回其有效 (Direction, Relation, Inverse)。
/// Compile-time helper: under Auto semantics, decide whether a single property should become a "graph property" and return its effective (Direction, Relation, Inverse).
/// 仅供索引投影 Graph.Object.IndexProjection 在编译期决定“注入哪些属性的图参数”使用。
/// Used only by the index projection Graph.Object.IndexProjection at compile time to decide "which properties' graph parameters to inject".
///   pAuto     类参数 Auto（1=开启自动注入）
///   pAuto     class parameter Auto (1 = enable auto-injection)
///   pName/pType/pColl        属性名 / (元素)类型 / Collection(""/list/array)
///   pName/pType/pColl        property name / (element) type / Collection(""/list/array)
///   pCard     Cardinality(""/one/many/parent/children)
///   pDir/pRel/pInv/pGraphUse  属性参数 Direction/Relation/Inverse/GraphUse
///   pDir/pRel/pInv/pGraphUse  property parameters Direction/Relation/Inverse/GraphUse
/// 规则：
/// Rules:
///   - 显式声明 Direction 的属性始终纳入（保持既有手工定义行为，不再注入）；
///   - properties that explicitly declare Direction are always included (keep existing manual-definition behavior, no injection);
///   - GraphUse=0 显式排除；
///   - GraphUse=0 explicitly excludes;
///   - Auto=1 时，对“持久化对象引用”自动纳入（方向 TO），但排除：
///   - when Auto=1, "persistent object references" are auto-included (direction TO), but excluding:
///       %SerialObject 内嵌对象、字面量数据类型、父子关系父方(children)、一对多关系一方(many)；
///       %SerialObject embedded objects, literal datatypes, parent-child relationship parent side (children), one-to-many relationship one side (many);
///     自动纳入时，用户手动设置的 Relation/Inverse 优先保留（未设置才用默认：关系=属性名，Inverse=0）。
///     when auto-including, the user's manually set Relation/Inverse take priority (defaults are used only when unset: relation=property name, Inverse=0).
/// 返回 ""=非图属性；否则 $LB(有效Direction, 有效Relation, 有效Inverse)。
/// Returns "" = not a graph property; otherwise $LB(effectiveDirection, effectiveRelation, effectiveInverse).
ClassMethod effGraphProp(pAuto As %String, pName As %String, pType As %String, pColl As %String, pCard As %String, pDir As %String, pRel As %String, pInv As %String, pGraphUse As %String) As %List [ Internal ]
{
    Quit:$Extract(pName,1)="%" ""
    Quit:pGraphUse=0 ""
    // 显式声明 Direction 的属性始终纳入
    // Properties that explicitly declare Direction are always included
    If pDir'="" 
    {
        Set:pRel="" pRel=pName
        Set:pInv="" pInv=0
        Quit $ListBuild(pDir, pRel, pInv)
    }
    // 未显式声明：仅当 Auto 开启时按 schema 自动纳入
    // Not explicitly declared: auto-include by schema only when Auto is enabled
    Quit:pAuto'=1 ""
    // 目标必须是持久化对象类型（排除字面量数据类型与 %SerialObject 内嵌对象）
    // Target must be a persistent object type (excluding literal datatypes and %SerialObject embedded objects)
    Set tTC = ##class(%Dictionary.CompiledClass).%OpenId(pType)
    Quit:'$IsObject(tTC) ""
    Quit:tTC.ClassType'="persistent" ""
    // 排除父子关系父方(children)、一对多关系一方(many)——计算侧集合，非存储引用
    // Exclude parent-child relationship parent side (children) and one-to-many relationship one side (many) -- computed-side collections, not stored references
    Quit:pCard="children" ""
    Quit:pCard="many" ""
    // 保留用户手动设置的 Relation/Inverse，未设置才用默认
    // Keep the user's manually set Relation/Inverse; use defaults only when unset
    Set:pRel="" pRel=pName
    Set:pInv="" pInv=0
    Quit $ListBuild("TO", pRel, pInv)
}

/// 编译期辅助：扫描 pClass 的所有图属性（带 Direction 参数；Auto 自动纳入者已由投影在编译期注入 Direction）
/// Compile-time helper: scan all graph properties of pClass (with Direction parameter; Auto auto-included ones already had Direction injected by the projection at compile time)
/// 返回 %List，每个元素为 $LB(Name, Direction, Relation, Inverse, Cardinality, Type, Collection)
/// Returns %List; each element is $LB(Name, Direction, Relation, Inverse, Cardinality, Type, Collection)
ClassMethod genGraphProps(pClass As %String) As %List [ Internal ]
{
    Set tResult = ""
    Set tCC = ##class(%Dictionary.CompiledClass).%OpenId(pClass)
    Quit:'$IsObject(tCC) tResult
    For tI=1:1:tCC.Properties.Count() 
    {
        Set tProp = tCC.Properties.GetAt(tI)
        Continue:$Extract(tProp.Name,1)="%"
        Set tDir = tProp.Parameters.GetAt("Direction")
        Continue:tDir=""
        Set tRel = tProp.Parameters.GetAt("Relation")
        Set:tRel="" tRel=tProp.Name
        Set tInv = tProp.Parameters.GetAt("Inverse")
        Set:tInv="" tInv=0
        Set tResult = tResult _ $ListBuild($ListBuild(tProp.Name, tDir, tRel, tInv, tProp.Cardinality, tProp.Type, tProp.Collection))
    }
    Quit tResult
}

/// 编译期辅助：为每个图属性生成“读取当前值并建边”的运行期代码（%List of 代码行）
/// Compile-time helper: for each graph property, generate runtime code that "reads the current value and builds edges" (%List of code lines)
/// 前提：生成的代码运行时已存在 tObj（本对象）与 tOwner（本节点 OID），且处于 If $IsObject(tObj) 块内
/// Precondition: at runtime the generated code already has tObj (this object) and tOwner (this node OID), and runs inside an If $IsObject(tObj) block
/// - 标量引用属性：读取引用对象的 %Id() 建一条边
/// - scalar reference property: read the referenced object's %Id() and build one edge
/// - list/array 集合属性：遍历元素，逐个建边
/// - list/array collection property: iterate elements and build an edge for each
ClassMethod genAddEdges(pGraphProps As %List) As %List [ Internal ]
{
    Set tQ = $Char(34)   // 双引号，避免转义地狱 | double quote, avoids escaping hell
    Set tLines = ""
    For tI=1:1:$ListLength(pGraphProps) 
    {
        Set tM = $ListGet(pGraphProps, tI)
        Set tName = $List(tM, 1), tRel = $List(tM, 3), tInv = $List(tM, 4), tCard = $List(tM, 5), tType = $List(tM, 6), tColl = $ListGet(tM, 7)
        // 一对多/父子关系的一方/父方，或显式 Inverse=1：反方向记边（源=引用对象，目标=本对象）
        // One-to-many/parent-child relationship one/parent side, or explicit Inverse=1: record edge in reverse direction (source=referenced object, target=this object)
        Set tRev = ((tCard = "parent") || (tCard = "one") || (tInv = 1))
        // 生成一条以 tGV(目标Id) + tGT(目标类型) 为终点的建边语句（按方向）
        // Generate an edge-building statement ending at tGV(target Id) + tGT(target type) (per direction)
        // 目标类型 tGT 运行期取引用对象的实际类（多态引用时，声明类型可能是基类）
        // Target type tGT is taken at runtime from the referenced object's actual class (for polymorphic references the declared type may be the base class)
        If tRev 
        {
            Set tEdge = "If tGV'=" _ tQ _ tQ _ " Do ##class(Graph.Object.Index).AddEdge($ListBuild(tGV,tGT)," _ tQ _ tRel _ tQ _ ",tOwner,tOwner)"
        }
        Else 
        {
            Set tEdge = "If tGV'=" _ tQ _ tQ _ " Do ##class(Graph.Object.Index).AddEdge(tOwner," _ tQ _ tRel _ tQ _ ",$ListBuild(tGV,tGT),tOwner)"
        }
        If (tColl = "list") || (tColl = "array") 
        {
            // 集合：遍历元素逐个建边
            // Collection: iterate elements and build an edge for each
            Set tLines = tLines _ $ListBuild("  Set tGC = tObj." _ tName)
            Set tLines = tLines _ $ListBuild("  If $IsObject(tGC) {")
            Set tLines = tLines _ $ListBuild("   Set tGK = " _ tQ _ tQ)
            Set tLines = tLines _ $ListBuild("   For  { Set tGK = tGC.Next(tGK)  Quit:tGK=" _ tQ _ tQ _ "   Set tGI = tGC.GetAt(tGK)  Set tGV = $Select($IsObject(tGI):tGI.%Id(),1:tGI)  Set tGT = $Select($IsObject(tGI):tGI.%ClassName(1),1:" _ tQ _ tType _ tQ _ ")  " _ tEdge _ " }")
            Set tLines = tLines _ $ListBuild("  }")
        }
        Else 
        {
            // 标量引用
            // Scalar reference
            Set tLines = tLines _ $ListBuild("  Set tGI = tObj." _ tName)
            Set tLines = tLines _ $ListBuild("  Set tGV = $Select($IsObject(tGI):tGI.%Id(),1:" _ tQ _ tQ _ ")")
            Set tLines = tLines _ $ListBuild("  Set tGT = $Select($IsObject(tGI):tGI.%ClassName(1),1:" _ tQ _ tType _ tQ _ ")")
            Set tLines = tLines _ $ListBuild("  " _ tEdge)
        }
    }
    Quit tLines
}

}
