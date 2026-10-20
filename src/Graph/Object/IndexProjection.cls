Include %occInclude

/// 图索引投影（编译期自动注入功能索引）
/// Graph index projection (auto-inject functional index at compile time)
/// 
/// 作为 Graph.Object.Base 的投影，在每个 **具体子类** 编译时自动为其补上一个固定名为
/// As a projection of Graph.Object.Base, when each **concrete subclass** is compiled it automatically adds for it a functional index with the fixed name
/// GraphIndex 的功能索引，并把该类所有图属性（带 Direction 参数）自动加入 On 子句：
/// GraphIndex, and automatically adds all graph properties of that class (with Direction parameter) into the On clause:
///     Index GraphIndex On (图属性1, 图属性2, ...) As Graph.Object.Index;
///     Index GraphIndex On (graphProp1, graphProp2, ...) As Graph.Object.Index;
/// 
/// 说明：
/// Notes:
/// - 纯 objectgenerator 方法只能生成方法体，无法向类定义注入 Index；投影的
/// - a pure objectgenerator method can only generate a method body and cannot inject an Index into the class definition; the projection's
///   CreateProjection 回调在编译期触发，可修改类定义并重新编译，是正确的机制。
///   CreateProjection callback fires at compile time, can modify the class definition and recompile, which is the correct mechanism.
/// - 通过进程私有全局 ^||GraphIdxProj 做重入保护，避免重新编译时无限递归。
/// - reentrancy protection via the process-private global ^||GraphIdxProj avoids infinite recursion during recompilation.
/// - 抽象类（无 extent）、无图属性的类会被跳过。
/// - abstract classes (no extent) and classes without graph properties are skipped.
/// 
/// Author: QP
/// Version: 1.0
/// Last Modified Date: 2026/07/10
Class Graph.Object.IndexProjection Extends %Projection.AbstractProjection [ System = 3 ]
{

ClassMethod CreateProjection(pClassName As %String, ByRef pParameters As %String, pModified As %String, pQstruct) As %Status
{
    Set tSC = $$$OK
    // 抽象基类本身不处理
    // The abstract base class itself is not processed
    Quit:pClassName="Graph.Object.Base" $$$OK
    // 重入保护：本方法内触发的重新编译会再次进入本回调，此时直接返回
    // Reentrancy protection: recompilation triggered within this method re-enters this callback; return directly in that case
    Quit:$Data(^||GraphIdxProj(pClassName)) $$$OK

    Try 
    {
        Set tDef = ##class(%Dictionary.ClassDefinition).%OpenId(pClassName)
        Quit:'$IsObject(tDef)                                // 打不开则保持 tSC=$$$OK | if it can't be opened, keep tSC=$$$OK
        // 抽象类没有 extent，无需索引
        // Abstract classes have no extent and need no index
        Quit:tDef.Abstract

        Set tChanged = 0
        Set tAuto = ##class(Graph.Object.Index).classAuto(pClassName)

        // 扫描本类局部属性：判定图属性；Auto 自动纳入者，显式把 Direction/Relation/Inverse 参数注入类定义
        // Scan this class's local properties: determine graph properties; for Auto auto-included ones, explicitly inject Direction/Relation/Inverse parameters into the class definition
        // 之后图字典 GraphDictionary、边维护 genGraphProps 只需按已注入的 Direction 参数工作
        // Afterwards the graph dictionary GraphDictionary and edge maintenance genGraphProps only need to work by the injected Direction parameter
        Set tScalars = ""       // 逗号分隔的标量图属性 | comma-separated scalar graph properties
        Set tColls = ""         // %List of 集合图属性名 | %List of collection graph property names
        For tI=1:1:tDef.Properties.Count() 
        {
            Set tPD = tDef.Properties.GetAt(tI)
            Set tName = tPD.Name
            Continue:$Extract(tName,1)="%"
            // 规范化类型/集合/基数取自编译期属性（声明可能是短名）；参数取自定义（含既有注入）
            // Normalized type/collection/cardinality come from the compiled property (declaration may be a short name); parameters come from the definition (including existing injections)
            Set tCP = ##class(%Dictionary.CompiledProperty).%OpenId(pClassName _ "||" _ tName)
            Set tType = $Select($IsObject(tCP):tCP.Type, 1:tPD.Type)
            Set tColl = $Select($IsObject(tCP):tCP.Collection, 1:tPD.Collection)
            Set tCard = $Select($IsObject(tCP):tCP.Cardinality, 1:tPD.Cardinality)
            Set tDir = tPD.Parameters.GetAt("Direction")
            Set tEff = ##class(Graph.Object.Index).effGraphProp(tAuto, tName, tType, tColl, tCard, tDir, tPD.Parameters.GetAt("Relation"), tPD.Parameters.GetAt("Inverse"), tPD.Parameters.GetAt("GraphUse"))
            Continue:tEff=""
            // Auto 自动纳入（原属性无 Direction）：把图参数显式写入属性定义
            // Auto auto-include (original property has no Direction): explicitly write graph parameters into the property definition
            // 仅补齐缺失的参数——用户手动设置的 Relation/Inverse 优先保留，不被覆盖
            // Only fill in missing parameters -- the user's manually set Relation/Inverse take priority and are not overwritten
            If tDir="" 
            {
                Do tPD.Parameters.SetAt($List(tEff,1), "Direction")
                Do:tPD.Parameters.GetAt("Relation")="" tPD.Parameters.SetAt($List(tEff,2), "Relation")
                Do:tPD.Parameters.GetAt("Inverse")="" tPD.Parameters.SetAt($List(tEff,3), "Inverse")
                Set tChanged = 1
            }
            // 分类到标量/集合，用于功能索引 On 子句
            // Classify into scalar/collection for the functional index On clause
            If (tColl="list")||(tColl="array") 
            {
                Set tColls = tColls _ $ListBuild(tName)
            } 
            Else 
            {
                Set tScalars = tScalars _ $Select(tScalars="":"", 1:",") _ tName
            }
        }

        // 计算期望的索引集合：tDesired(索引名) = On 表达式
        // Compute the desired index set: tDesired(indexName) = On expression
        //   标量  -> GraphIndex On (标量列表)
        //   scalar  -> GraphIndex On (scalar list)
        //   集合  -> GraphIndexE<Prop> On Prop(ELEMENTS)  （子值填充触发维护）
        //   collection  -> GraphIndexE<Prop> On Prop(ELEMENTS)  (sub-value population triggers maintenance)
        Kill tDesired
        If tScalars '= "" { Set tDesired("GraphIndex") = tScalars }
        For tI=1:1:$ListLength(tColls) 
        {
            Set tCp = $List(tColls, tI)
            Set tDesired("GraphIndexE" _ tCp) = tCp _ "(ELEMENTS)"
        }

        Set tChanged = 0
        // 移除已存在的 Graph 功能索引（名字以 GraphIndex 开头）；与期望完全一致者保留
        // Remove existing Graph functional indices (names starting with GraphIndex); keep those exactly matching the desired set
        For tI=tDef.Indices.Count():-1:1 
        {
            Set tIdx = tDef.Indices.GetAt(tI)
            Continue:$Extract(tIdx.Name,1,10)'="GraphIndex"
            Set tNm = tIdx.Name
            If $Data(tDesired(tNm)), (tIdx.Properties=tDesired(tNm)), (tIdx.TypeClass="Graph.Object.Index") 
            {
                Kill tDesired(tNm)   // 已存在且一致，无需改动 | already exists and matches, no change needed
            } 
            Else 
            {
                Do tDef.Indices.RemoveAt(tI)
                Set tChanged = 1
            }
        }
        // 添加仍缺失的期望索引
        // Add the desired indices that are still missing
        Set tNm = ""
        For 
        {
            Set tNm = $Order(tDesired(tNm))
            Quit:tNm=""
            Set tNewIdx = ##class(%Dictionary.IndexDefinition).%New()
            Set tNewIdx.Name = tNm
            Set tNewIdx.Properties = tDesired(tNm)
            Set tNewIdx.TypeClass = "Graph.Object.Index"
            Do tDef.Indices.Insert(tNewIdx)
            Set tChanged = 1
        }

        Quit:'tChanged                                       // 无变化则保持 tSC=$$$OK | if unchanged, keep tSC=$$$OK

        Set tSC = tDef.%Save()
        Quit:$$$ISERR(tSC)                                   // 保存失败，tSC 已含错误 | save failed, tSC already contains the error

        // 重新编译一次，使新索引生效（重入保护已就位）
        // Recompile once so the new index takes effect (reentrancy protection is in place)
        Set ^||GraphIdxProj(pClassName) = 1
        Set tSC = $System.OBJ.Compile(pClassName, "ck-d")
        Kill ^||GraphIdxProj(pClassName)
    }
    Catch ex 
    {
        Kill ^||GraphIdxProj(pClassName)                    // 异常时清理重入保护，避免残留 | on exception, clean up reentrancy protection to avoid leftovers
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

}
