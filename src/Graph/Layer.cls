Include %occInclude

/// 图分层：层注册表、读写路由与一次性迁移。
/// Graph layering: layer registry, read/write routing and the one-time migration.
///
///   ^GraphData.OUT(layer, srcOID, tgtOID, rel) = ""
///   ^GraphData.IN (layer, tgtOID, srcOID, rel) = ""
///   ^GraphData.OWN(layer, ownerOID, srcOID, rel, tgtOID) = ""
///   ^Graph.Layer(layer) = $lb(tier, rank, mode, enabled, desc)       tier: core|industry|user|scenario; mode: ro|rw
///   ^Graph.Settings("Layers","DefaultView")  默认读取视图（逗号分隔，"*"=全部启用层）/ default read view
///   ^Graph.Settings("Layers","Write")        默认写入层 / default write layer
///   ^Graph.Settings("Layout")=2              分层布局标记 / layered-layout marker
///
/// 读取语义为并集：视图内各层的边合并，同一条边去重。 / Reads are the union of the layers in the view.
/// 写入层优先级：显式 pLayer > 类参数 GRAPHLAYER > 进程上下文 SetWriteLayer > 默认写入层。
/// Write layer precedence: explicit pLayer > class parameter GRAPHLAYER > process context > default write layer.
/// Author: QP
/// Version: 1.0
/// Last Modified Date: 2026/10/19
Class Graph.Layer Extends %RegisteredObject
{

Parameter DEFAULTVIEW = "Core,User";

Parameter DEFAULTWRITE = "User";

/// 首次使用时登记 Core(只读) 与 User(可写)。 / Register Core (ro) and User (rw) on first use.
ClassMethod Ensure()
{
    If '$Data(^Graph.Layer) {
        Set ^Graph.Layer("Core") = $ListBuild("core", 10, "ro", 1, "Generic core graph")
        Set ^Graph.Layer("User") = $ListBuild("user", 90, "rw", 1, "Application / user graph")
        Set ^Graph.LayerEpoch = $Increment(^Graph.LayerEpoch)
    }
}

/// 旧布局（首下标是节点）与新布局不能共存：有旧数据而未迁移时抛错，全新命名空间则直接打标记。
/// The legacy layout (first subscript = node) cannot coexist with the layered one: throw when legacy data is unmigrated, stamp fresh namespaces.
ClassMethod CheckLayout() [ Internal ]
{
    If $Get(^Graph.Settings("Layout")) = 2 Quit
    If $Data(^GraphData.OUT) || $Data(^GraphData.IN) || $Data(^GraphData.OWN) {
        Throw ##class(%Exception.General).%New("LEGACY_GRAPH_LAYOUT: run ##class(Graph.Layer).Migrate() first")
    }
    Set ^Graph.Settings("Layout") = 2
    Do ..Ensure()
}

/// 定义或更新一个层。 / Define or update a layer.
ClassMethod Define(pName As %String, pTier As %String = "user", pRank As %Integer = 50, pMode As %String = "rw", pDesc As %String = "") As %Status
{
    If '$Match(pName, "^[A-Za-z][A-Za-z0-9_.:-]*$") Quit $$$ERROR($$$GeneralError, "Invalid layer name: " _ pName)
    If '$ListFind($ListBuild("core", "industry", "user", "scenario"), pTier) Quit $$$ERROR($$$GeneralError, "Invalid tier: " _ pTier)
    If (pMode '= "ro") && (pMode '= "rw") Quit $$$ERROR($$$GeneralError, "Invalid mode: " _ pMode)
    Do ..CheckLayout()
    Set tOld = $Get(^Graph.Layer(pName)), tEnabled = $Select(tOld = "": 1, 1: $List(tOld, 4))
    Set ^Graph.Layer(pName) = $ListBuild(pTier, +pRank, pMode, tEnabled, pDesc)
    Set ^Graph.LayerEpoch = $Increment(^Graph.LayerEpoch)
    Quit $$$OK
}

/// 启用/停用一个层（停用后不参与读写）。 / Enable or disable a layer (a disabled layer is neither read nor written).
ClassMethod Enable(pName As %String, pOn As %Boolean = 1) As %Status
{
    If '$Data(^Graph.Layer(pName), tInfo) Quit $$$ERROR($$$GeneralError, "Layer not defined: " _ pName)
    Set $List(tInfo, 4) = $Select(pOn: 1, 1: 0), ^Graph.Layer(pName) = tInfo
    Set ^Graph.LayerEpoch = $Increment(^Graph.LayerEpoch)
    Quit $$$OK
}

/// 安装知识包层：登记 industry 层，并把它加入默认读取视图（排在 User 之前）；幂等。
/// Install a pack layer: register an industry layer and add it to the default read view (before User); idempotent.
ClassMethod InstallPack(pName As %String, pDesc As %String = "", pRank As %Integer = 50) As %Status
{
    If '$Data(^Graph.Layer(pName)) {
        Set tSC = ..Define(pName, "industry", pRank, "rw", pDesc)
        Quit:$$$ISERR(tSC) tSC
    }
    Set tView = $Get(^Graph.Settings("Layers", "DefaultView"), ..#DEFAULTVIEW)
    If tView = "*" Quit $$$OK
    Set tList = "", tHas = 0
    For tI = 1:1:$Length(tView, ",") {
        Set tName = $ZStrip($Piece(tView, ",", tI), "<>W")
        Continue:tName=""
        If tName = pName Set tHas = 1
        Set tList = tList _ $ListBuild(tName)
    }
    Quit:tHas $$$OK
    Set tNew = "", tDone = 0
    For tI = 1:1:$ListLength(tList) {
        Set tName = $List(tList, tI)
        If (tName = "User") && 'tDone { Set tNew = tNew _ $ListBuild(pName), tDone = 1 }
        Set tNew = tNew _ $ListBuild(tName)
    }
    If 'tDone Set tNew = tNew _ $ListBuild(pName)
    Set ^Graph.Settings("Layers", "DefaultView") = $ListToString(tNew, ",")
    Quit $$$OK
}

/// 删除一个层及其全部数据（三个全局的子树各 Kill 一次）。 / Drop a layer and all its data (one subtree Kill per global).
ClassMethod Drop(pName As %String) As %Status
{
    If pName = "" Quit $$$ERROR($$$GeneralError, "Layer name required")
    Kill ^GraphData.OUT(pName), ^GraphData.IN(pName), ^GraphData.OWN(pName), ^Graph.Layer(pName)
    Set ^Graph.LayerEpoch = $Increment(^Graph.LayerEpoch)
    Quit $$$OK
}

/// 列出已登记的层，按 rank 排序。 / List registered layers ordered by rank.
ClassMethod List() As %DynamicArray
{
    Set tOut = [], tName = ""
    For {
        Set tName = $Order(^Graph.Layer(tName), 1, tInfo)
        Quit:tName=""
        Set tRank($List(tInfo, 2), tName) = tInfo
    }
    Set tR = ""
    For {
        Set tR = $Order(tRank(tR))
        Quit:tR=""
        Set tName = ""
        For {
            Set tName = $Order(tRank(tR, tName), 1, tInfo)
            Quit:tName=""
            Do tOut.%Push({"name":(tName), "tier":($List(tInfo,1)), "rank":($List(tInfo,2)), "mode":($List(tInfo,3)), "enabled":($List(tInfo,4)), "desc":($List(tInfo,5))})
        }
    }
    Quit tOut
}

/// 实际存在数据的层（扫描 OUT/IN/OWN 的首下标）。 / Layers that actually hold data (first subscripts of OUT/IN/OWN).
ClassMethod Present() As %List
{
    Set tOut = ""
    For tRoot = "^GraphData.OUT", "^GraphData.IN", "^GraphData.OWN" {
        Set tName = ""
        For {
            Set tName = $Order(@tRoot@(tName))
            Quit:tName=""
            If '$ListFind(tOut, tName) Set tOut = tOut _ $ListBuild(tName)
        }
    }
    Quit tOut
}

/// 解析读取视图：显式 > 进程视图 > 默认视图；"*" 为全部启用层；停用的层被过滤。
/// Resolve the read view: explicit > process view > default view; "*" = every enabled layer; disabled layers are filtered out.
ClassMethod View(pLayers As %String = "") As %List
{
    If $Get(^Graph.Settings("Layout")) '= 2 Do ..CheckLayout()
    Set tSpec = pLayers
    If tSpec = "" Set tSpec = $Get(^||Graph.View)
    If tSpec = "" Set tSpec = $Get(^Graph.Settings("Layers", "DefaultView"), ..#DEFAULTVIEW)
    Set tOut = ""
    If tSpec = "*" {
        Set tName = ""
        For {
            Set tName = $Order(^Graph.Layer(tName), 1, tInfo)
            Quit:tName=""
            If $List(tInfo, 4) Set tRank($List(tInfo, 2), tName) = ""
        }
        Set tR = ""
        For {
            Set tR = $Order(tRank(tR))
            Quit:tR=""
            Set tName = ""
            For {
                Set tName = $Order(tRank(tR, tName))
                Quit:tName=""
                Set tOut = tOut _ $ListBuild(tName)
            }
        }
        Quit tOut
    }
    For i = 1:1:$Length(tSpec, ",") {
        Set tName = $ZStrip($Piece(tSpec, ",", i), "<>W")
        Continue:tName=""
        If $Data(^Graph.Layer(tName), tInfo)#2, '$List(tInfo, 4) Continue
        Continue:$ListFind(tOut, tName)
        Set tOut = tOut _ $ListBuild(tName)
    }
    Quit tOut
}

/// 某层的全局根，例如 ^GraphData.OUT("User")，供 @root@(...) 间接寻址。
/// The global root of a layer, e.g. ^GraphData.OUT("User"), for @root@(...) indirection.
ClassMethod Root(pDir As %String, pLayer As %String) As %String
{
    Quit $Case(pDir, "OUT": $Name(^GraphData.OUT(pLayer)), "IN": $Name(^GraphData.IN(pLayer)), "OWN": $Name(^GraphData.OWN(pLayer)), : "")
}

/// 进程级读取视图；空串恢复默认。 / Process-level read view; empty restores the default.
ClassMethod SetView(pLayers As %String = "")
{
    If pLayers = "" { Kill ^||Graph.View } Else { Set ^||Graph.View = pLayers }
}

/// 进程级写入层上下文（知识包加载器使用）；空串恢复默认。 / Process-level write-layer context (used by pack loaders); empty restores the default.
ClassMethod SetWriteLayer(pLayer As %String = "")
{
    If pLayer = "" { Kill ^||Graph.WriteLayer } Else { Set ^||Graph.WriteLayer = pLayer }
}

/// 持久化的默认读取视图。 / Persistent default read view.
ClassMethod SetDefaultView(pLayers As %String)
{
    Set ^Graph.Settings("Layers", "DefaultView") = pLayers
}

/// 持久化的默认写入层。 / Persistent default write layer.
ClassMethod SetDefaultWrite(pLayer As %String)
{
    Set ^Graph.Settings("Layers", "Write") = pLayer
    Set ^Graph.LayerEpoch = $Increment(^Graph.LayerEpoch)
}

/// 本进程临时解锁/锁回只读层（加载器写 Core 或 pack 时使用）。 / Temporarily unlock or relock a read-only layer for this process (pack loaders).
ClassMethod AllowWrite(pLayer As %String, pOn As %Boolean = 1)
{
    If pOn { Set ^||Graph.Unlock(pLayer) = 1 } Else { Kill ^||Graph.Unlock(pLayer) }
    Kill ^||Graph.WOK(pLayer)
}

/// 解析写入层。 / Resolve the write layer.
ClassMethod WriteLayer(pLayer As %String = "") As %String
{
    Quit:pLayer'="" pLayer
    Quit:$Get(^||Graph.WriteLayer)'="" ^||Graph.WriteLayer
    Quit $Get(^Graph.Settings("Layers", "Write"), ..#DEFAULTWRITE)
}

/// 由类参数 GRAPHLAYER 解析层，未设置则返回 ""（由调用方落到默认写入层）。
/// Resolve the layer from the class parameter GRAPHLAYER; "" when unset (the caller falls back to the default write layer).
ClassMethod ClassLayer(pClass As %String) As %String
{
    If '$Data(^||Graph.CL(pClass), tLayer) {
        Set tLayer = ""
        Try { Set tLayer = $Parameter(pClass, "GRAPHLAYER") } Catch {}
        Set ^||Graph.CL(pClass) = tLayer
    }
    Quit tLayer
}

/// 校验层可写（已登记、已启用、非只读或已解锁）；结果按注册表版本号缓存于进程私有全局。
/// Check that a layer is writable (registered, enabled, not read-only or unlocked); cached per registry epoch in a process-private global.
ClassMethod CheckWrite(pLayer As %String) As %Status
{
    Set tEpoch = $Get(^Graph.LayerEpoch)
    If $Get(^||Graph.WOK) '= tEpoch { Kill ^||Graph.WOK  Set ^||Graph.WOK = tEpoch }
    If $Data(^||Graph.WOK(pLayer)) Quit $$$OK
    Try { Do ..CheckLayout() } Catch ex { Return ex.AsStatus() }
    If '$Data(^Graph.Layer(pLayer), tInfo) Quit $$$ERROR($$$GeneralError, "Graph layer not defined: " _ pLayer)
    If '$List(tInfo, 4) Quit $$$ERROR($$$GeneralError, "Graph layer disabled: " _ pLayer)
    If ($List(tInfo, 3) = "ro") && '$Get(^||Graph.Unlock(pLayer)) Quit $$$ERROR($$$GeneralError, "Graph layer is read-only: " _ pLayer)
    Set ^||Graph.WOK(pLayer) = 1
    Quit $$$OK
}

/// 一次性迁移：把旧布局（无层）原地迁入 pLayer 层，迁移前后做条数与内容校验，成功后删除中间副本。
/// One-time migration: move the legacy (layerless) layout in place into layer pLayer, verify counts and content before/after, drop the scratch copy on success.
/// 须在无并发写入时执行。 / Run while no writers are active.
ClassMethod Migrate(pLayer As %String = "User") As %Status
{
    Set tSC = $$$OK, tLocked = 0
    Try {
        If $Get(^Graph.Settings("Layout")) = 2 Throw ##class(%Exception.General).%New("ALREADY_LAYERED")
        If '$Match(pLayer, "^[A-Za-z][A-Za-z0-9_.:-]*$") Throw ##class(%Exception.General).%New("INVALID_LAYER_NAME")
        Lock +^Graph.Settings("Layout"):5
        Set tLocked = 1
        If $Data(^Graph.MigTmp) Throw ##class(%Exception.General).%New("SCRATCH_EXISTS: ^Graph.MigTmp holds an earlier migration copy")
        For tD = "OUT", "IN", "OWN" Do ..scanDigest("^GraphData." _ tD, 0, "", .tN, .tC)  Set tBefore(tD) = $ListBuild(tN, tC)
        // 先落到持久的中间副本，再清空旧全局并写入分层位置
        // Stage in a persistent scratch copy first, then clear the old globals and write the layered location
        Merge ^Graph.MigTmp("OUT") = ^GraphData.OUT, ^Graph.MigTmp("IN") = ^GraphData.IN, ^Graph.MigTmp("OWN") = ^GraphData.OWN
        Kill ^GraphData.OUT, ^GraphData.IN, ^GraphData.OWN
        Merge ^GraphData.OUT(pLayer) = ^Graph.MigTmp("OUT"), ^GraphData.IN(pLayer) = ^Graph.MigTmp("IN"), ^GraphData.OWN(pLayer) = ^Graph.MigTmp("OWN")
        Set tOk = 1
        For tD = "OUT", "IN", "OWN" {
            Do ..scanDigest(..Root(tD, pLayer), 1, pLayer, .tN, .tC)
            If $ListBuild(tN, tC) '= tBefore(tD) Set tOk = 0
        }
        If 'tOk {
            Kill ^GraphData.OUT, ^GraphData.IN, ^GraphData.OWN
            Merge ^GraphData.OUT = ^Graph.MigTmp("OUT"), ^GraphData.IN = ^Graph.MigTmp("IN"), ^GraphData.OWN = ^Graph.MigTmp("OWN")
            Kill ^Graph.MigTmp
            Throw ##class(%Exception.General).%New("MIGRATION_VERIFY_FAILED: legacy layout restored")
        }
        Kill ^Graph.MigTmp
        Set ^Graph.Settings("Layout") = 2
        Do ..Ensure()
        If '$Data(^Graph.Layer(pLayer)) Set tSC = ..Define(pLayer)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    If tLocked Lock -^Graph.Settings("Layout")
    Quit tSC
}

/// 某层 OUT/IN/OWN 的条数与内容校验和：{"OUT":[n,crc],"IN":[n,crc],"OWN":[n,crc]}，供迁移与对账。
/// Per-layer entry counts and content checksums for OUT/IN/OWN, for migration and reconciliation.
ClassMethod Digest(pLayer As %String) As %DynamicObject
{
    Set tOut = {}
    For tD = "OUT", "IN", "OWN" {
        Do ..scanDigest(..Root(tD, pLayer), 1, pLayer, .tN, .tC)
        Do tOut.%Set(tD, [(tN), (tC)])
    }
    Quit tOut
}

/// 顺序扫描一个根下的全部数据节点，统计条数与（与根前缀无关的）CRC 求和。
/// Scan every data node under a root and sum entry counts and CRCs (independent of the root prefix).
ClassMethod scanDigest(pRoot As %String, pSkip As %Integer, pLayer As %String, Output pCount As %Integer, Output pCrc As %Integer) [ Internal ]
{
    Set pCount = 0, pCrc = 0
    Set tNext = $Query(@pRoot)
    While tNext '= "" {
        If pSkip && ($QSubscript(tNext, pSkip) '= pLayer) Quit
        Set tKey = ""
        For i = pSkip + 1:1:$QLength(tNext) { Set tKey = tKey _ $QSubscript(tNext, i) _ $Char(1) }
        Set pCount = pCount + 1, pCrc = (pCrc + $ZCRC(8, $ZConvert(tKey, "O", "UTF8"))) # 4294967296
        Set tNext = $Query(@tNext)
    }
}

}
