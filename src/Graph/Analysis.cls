Include %occInclude

Class Graph.Analysis Extends %RegisteredObject
{

/// 中文：自动分析当前命名空间图；先汇总 OUT/IN/OWN 已分配 MB，再决定是否抽样。
/// pMinMB 默认 64；尺寸 <= 门槛时返回 small-graph、空建议，不枚举节点或邻接。
/// pSampleSize 默认 2048；大图全节点框等概率无放回抽样，完整扫描样本节点的 OUT/IN。
/// pMaxNodes/pMaxScans 默认 10000000/10000000，分别限制节点框枚举和样本邻接扫描。
/// 总体为 OUT/IN 顶层键的并集；没有存储记录的孤立节点不在总体内。
/// 报告区分尺寸、精确总体节点数、样本观测、无偏估计和保守的单项 95% 置信区间。
/// 样本最大值/分位数/CV 不代表总体精确值；抽样可能遗漏稀有高阶节点。
/// 仅提供可选试验，不改变默认值；缓存 -1 无上限模式保留。超预算返回错误，不给部分建议。
/// pReport 输出说明：失败只有 complete=false/error；成功包含 namespace、scope 和 heuristicVersion。
/// 入参：pMinMB 是跳过小图的存储阈值，pSampleSize 是抽样量，pMaxNodes/pMaxScans 是工作预算；pReport 输出分析结果。
/// size：三个 Global 的 allocatedMB 及总量；gate：thresholdMB 和严格大于的门槛规则。
/// decision=small-graph：samplingPerformed=false、enumeratedNodes/scannedNeighborEntries=0、空建议。
/// decision=optional-trials：sample 给出总体节点数、实际样本数、入样概率和 census 标记。
/// observed：样本节点数、完整方向度数 mean/p50/p95/max/CV、出边节点对数、自环数。
/// estimates：均值与全图连接对总量的 estimate/lower/upper/confidence；不是样本最大值的区间。
/// recommendations：option、candidate、factoryDefault、currentDefault、suggestedValue、trialValues、reason、condition、evidence。
/// candidate=true 仅表示可试验；suggestedValue 为显式接受时的值，trialValues 为其他可比较值。
/// currentDefault 是分析时已配置的默认值；factoryDefault 是未配置时的内建值。
/// budgets 为节点/邻接计数限制；warnings 必须与估计和建议一起解读。不会返回节点身份列表。
/// 接受建议须另行调用 AcceptSuggestion(report,.applied)；Analyze 本身不写入设置。
/// 无快照；必须在图稳定且 OUT/IN 一致时运行。存储块统计可能产生 I/O，并非常数时间。
/// English: Measure namespace graph storage first; only analyze graphs strictly above pMinMB (64).
/// Small graphs return decision=small-graph and no recommendations, without enumerating nodes/edges.
/// Above the gate, use a uniform reservoir without replacement over the complete OUT/IN node union.
/// Scan full adjacency of sampled nodes, not sample-internal edges. Sample size defaults to 2048.
/// Node-frame/neighbor budgets default to 10000000 each; overflow fails without partial recommendations.
/// Estimates assume a stable, consistent graph. Unstored isolates are outside the sampling frame.
/// Mean/total intervals are conservative marginal 95% Hoeffding bounds, not relative-error guarantees.
/// Max/quantiles/CV are sample observations; rare hubs may be missed. No settings are applied.
/// pReport: failures contain only complete=false/error; success includes namespace/scope/heuristicVersion.
/// size/gate describe allocated MB and the threshold; small-graph has zero scan work and no suggestions.
/// sample contains populationNodes/sampledNodes/inclusionProbability/census; observed contains sample statistics.
/// estimates contain estimate/lower/upper/confidence for mean degree and population pair totals only.
/// recommendations contain option/candidate/factoryDefault/currentDefault/suggestedValue/trialValues/reason/condition/evidence.
/// suggestedValue is the value used by explicit acceptance, not an automatic change or a proven optimum.
/// currentDefault is the configured value at analysis time; factoryDefault is the built-in fallback.
/// budgets limit counted work; warnings qualify all results. Sample identifiers are not returned.
/// Call AcceptSuggestion(report,.applied) separately to persist candidate settings; Analyze remains read-only.
/// Example / 示例：Set sc = ##class(Graph.Analysis).Analyze(.report)
/// Custom gate / 自定义门槛：Set sc = ##class(Graph.Analysis).Analyze(.report,128,4096)
/// Full budget example / 完整预算示例：Set sc=##class(Graph.Analysis).Analyze(.report,128,4096,100000,1000000)
/// If $SYSTEM.Status.IsOK(sc) Write report.%ToJSON(),!
ClassMethod Analyze(Output pReport As %DynamicObject, pMinMB As %Numeric = 64, pSampleSize As %Integer = 2048, pMaxNodes As %Integer = 10000000, pMaxScans As %Integer = 10000000, pLayers As %String = "") As %Status
{
    Set pReport = {"complete":false}, status = $$$OK
    Try {
        If (pMinMB<0)||(pMinMB'=+pMinMB)||(pSampleSize<2)||(pSampleSize'=(pSampleSize\1))||(pMaxNodes<1)||(pMaxNodes>2147483647)||(pMaxNodes'=(pMaxNodes\1))||(pMaxScans<1)||(pMaxScans'=(pMaxScans\1)) Throw ##class(%Exception.General).%New("INVALID_ANALYSIS_OPTIONS")
        $$$ThrowOnError(..Size(.size))
        Set gate = {"thresholdMB":(pMinMB),"comparison":"allocatedMB > thresholdMB","policy":"Skip optional optimization for small graphs; threshold is a configurable heuristic."}
        Set warnings = ["No settings are applied; candidates require representative workload benchmarks.","No snapshot: graph must remain stable and OUT/IN must be consistent throughout measurement and sampling.","Population excludes isolated nodes with no OUT/IN record. Relation multiplicity is not part of degree.","Sample maxima, quantiles and CV are descriptive, not exact population values; rare hubs can be missed.","Hoeffding intervals are marginal 95% bounds and may be very wide; they do not guarantee useful relative precision.","Allocated storage is not live payload bytes, node count, cache use or process peak memory. Size measurement reads storage blocks.","Count budgets do not bound elapsed time or total memory. A failed/budget-truncated sample produces no recommendations."]
        If size.allocatedMB<=pMinMB {
            Set pReport = {"complete":true,"namespace":($Namespace),"scope":"namespace-graph","heuristicVersion":2,"size":(size),"gate":(gate),"decision":"small-graph","samplingPerformed":false,"enumeratedNodes":0,"scannedNeighborEntries":0,"recommendations":[],"warnings":(warnings)}
            Return $$$OK
        }
        Set population = 0, unitCount = ##class(Graph.Tools).units(0,1,pLayers,.unit)
        Kill ^||GraphAnalysisSeen
        For unitIndex = 1:1:unitCount {
            Set root = $List(unit(unitIndex),2), node = ""
            For {
                Set node = $Order(@root@(node))
                Quit:node=""
                // 同一节点可出现在多个方向/层，只计一次 | a node may appear in several directions/layers; count it once
                Continue:$Data(^||GraphAnalysisSeen(node))
                Set ^||GraphAnalysisSeen(node) = ""
                Set population = population+1
                If population>pMaxNodes Throw ##class(%Exception.General).%New("ANALYSIS_NODE_BUDGET_EXCEEDED")
                Set slot = population
                If population>pSampleSize Set slot = $Random(population)+1
                If slot<=pSampleSize Set reservoir(slot) = node
            }
        }
        Kill ^||GraphAnalysisSeen
        Set sampleCount = $Select(population<pSampleSize:population,1:pSampleSize)
        For slot = 1:1:sampleCount Set selected(reservoir(slot)) = ""
        Kill reservoir
        $$$ThrowOnError(..Measure(.selected,.observed,pMaxNodes,pMaxScans,1,population,pLayers))
        Set mean = observed.directionalDegree.mean, pairMean = 0, inclusion = 0
        If sampleCount Set pairMean = observed.directedPairs/sampleCount, inclusion = sampleCount/population
        Set census = sampleCount=population
        For index = 0:1:observed.recommendations.%Size()-1 {
            Set recommendation = observed.recommendations.%Get(index)
            Set recommendation.evidence = $Select(census:"node census",1:"sample observations, not a population-wide exclusion or significance test")
            If 'census Set recommendation.reason = $Select(recommendation.candidate:"Observed sample signal suggests an optional workload trial.",1:"No candidate signal in this sample; unsampled nodes may differ.")
        }
        Set degreeInterval = ..MeanInterval(mean,(2*population),sampleCount,census)
        Set pairInterval = ..MeanInterval(pairMean,population,sampleCount,census)
        Set pairs = {"estimate":(population*pairMean),"lower":(population*pairInterval.lower),"upper":(population*pairInterval.upper),"confidence":0.95}
        If census Set pairs = {"estimate":(observed.directedPairs),"lower":(observed.directedPairs),"upper":(observed.directedPairs),"confidence":0.95}
        Set sample = {"method":"uniform-reservoir-without-replacement","population":"unique OUT/IN top-level keys","populationNodes":(population),"requestedNodes":(pSampleSize),"sampledNodes":(sampleCount),"inclusionProbability":(inclusion),"census":(census)}
        Set estimates = {"directionalDegreeMean":(degreeInterval),"directedPairs":(pairs),"method":($Select(census:"census",1:"unbiased sample mean and N times sample outgoing-degree mean; conservative Hoeffding intervals"))}
        Set pReport = {"complete":true,"namespace":($Namespace),"scope":"namespace-graph","heuristicVersion":2,"size":(size),"gate":(gate),"decision":"optional-trials","samplingPerformed":true,"enumeratedNodes":(population),"sample":(sample),"observed":{"nodeCount":(observed.nodeCount),"directionalDegree":(observed.directionalDegree),"outgoingPairs":(observed.directedPairs),"selfLoopPairs":(observed.selfLoopPairs)},"estimates":(estimates),"scannedNeighborEntries":(observed.scannedNeighborEntries),"budgets":{"maxNodes":(pMaxNodes),"maxScans":(pMaxScans)},"recommendations":(observed.recommendations),"warnings":(warnings)}
    } Catch exception {
        Set status = exception.AsStatus(), pReport = {"complete":false,"error":($SYSTEM.Status.GetErrorText(status))}
    }
    Return status
}

/// 中文：显式接受 Analyze 的候选建议，持久化当前命名空间的 GraphEx 默认参数。
/// pReport 必须为本命名空间成功的自动分析报告；小图为空操作；不接受 AnalyzeNodes 报告。
/// pChoices 可选动态对象，如 {"pCacheLimit":-1}；只能为 candidate=true 的选项选择 trialValues 内的值。
/// 未指定选择时使用 suggestedValue；非候选项保持原值；-1 无上限缓存必须显式选择。
/// 所有选项先校验，再加锁合并并单次写入 ^Graph.Settings("Traversal")；错误不写入任何设置。
/// pApplied：complete、namespace、applied（是否改变配置）、changes、before/after；失败只有 complete/error。
/// 入参：pReport 是 Analyze 生成的同命名空间报告，pChoices 可选指定候选项试验值；pApplied 返回应用前后配置和变更。
/// 后续 GraphEx BFSParallel/ShortestPath 的省略参数读取设置，显式参数优先；原有 Graph 不受影响。
/// English: Explicitly accept candidate suggestions into persistent namespace-local GraphEx defaults.
/// Only successful automatic reports from this namespace are accepted; small-graph reports are no-ops.
/// Optional pChoices maps candidate option names to trialValues; otherwise suggestedValue is used.
/// Non-candidates remain unchanged. Unbounded cache -1 requires an explicit choice and memory validation.
/// Validate all values, lock/merge, then write one settings record; invalid input never partially applies.
/// pApplied contains complete/namespace/applied/changes/before/after, or only complete=false/error on failure.
/// Future omitted GraphEx parameters use these defaults; explicit arguments and the original Graph are unchanged.
/// Reports are proposals, not signed approvals: restrict configuration writes to trusted operators.
/// Example / 示例：Set sc = ##class(Graph.Analysis).AcceptSuggestion(report,.applied)
/// Explicit trial / 显式试验：Set choices={"pCacheLimit":-1} Set sc=##class(Graph.Analysis).AcceptSuggestion(report,.applied,choices)
/// English parameters: pReport is an Analyze report from this namespace; optional pChoices selects trial values; pApplied returns changes and before/after settings.
ClassMethod AcceptSuggestion(pReport As %DynamicObject, Output pApplied As %DynamicObject, pChoices As %DynamicObject = "") As %Status
{
    Set status = $$$OK, pApplied = {"complete":false}, locked = 0
    Try {
        If '$IsObject(pReport) Throw ##class(%Exception.General).%New("INVALID_ANALYSIS_REPORT")
        If 'pReport.%IsA("%DynamicObject") Throw ##class(%Exception.General).%New("INVALID_ANALYSIS_REPORT")
        If (pReport.complete'=1)||(pReport.scope'="namespace-graph")||(pReport.namespace'=$Namespace)||(pReport.heuristicVersion'=2) Throw ##class(%Exception.General).%New("INCOMPATIBLE_ANALYSIS_REPORT")
        If pChoices="" Set pChoices = {}
        If '$IsObject(pChoices) Throw ##class(%Exception.General).%New("INVALID_CHOICES")
        If 'pChoices.%IsA("%DynamicObject") Throw ##class(%Exception.General).%New("INVALID_CHOICES")
        Set recommendations = pReport.recommendations
        If '$IsObject(recommendations) Throw ##class(%Exception.General).%New("INVALID_RECOMMENDATIONS")
        If 'recommendations.%IsA("%DynamicArray") Throw ##class(%Exception.General).%New("INVALID_RECOMMENDATIONS")
        Set small = pReport.decision="small-graph"
        If (small&&(recommendations.%Size()'=0))||('small&&((pReport.decision'="optional-trials")||(recommendations.%Size()'=5))) Throw ##class(%Exception.General).%New("INVALID_RECOMMENDATIONS")
        For index = 0:1:recommendations.%Size()-1 {
            Set item = recommendations.%Get(index)
            If '$IsObject(item) Throw ##class(%Exception.General).%New("INVALID_RECOMMENDATION")
            Set name = item.option, position = ..OptionIndex(name)
            If ('position)||$Data(seen(name)) Throw ##class(%Exception.General).%New("UNKNOWN_OR_DUPLICATE_OPTION")
            Set seen(name) = ""
            If (item.candidate'=0)&&(item.candidate'=1) Throw ##class(%Exception.General).%New("INVALID_CANDIDATE")
            If 'item.candidate Continue
            Set value = item.suggestedValue, explicit = pChoices.%IsDefined(name)
            If explicit Set value = pChoices.%Get(name)
            If explicit {
                If pChoices.%GetTypeOf(name)'="number" Throw ##class(%Exception.General).%New("OPTION_MUST_BE_NUMERIC")
            } Else {
                If item.%GetTypeOf("suggestedValue")'="number" Throw ##class(%Exception.General).%New("OPTION_MUST_BE_NUMERIC")
            }
            If (value'=(value\1))||(value>2147483647) Throw ##class(%Exception.General).%New("INVALID_OPTION_VALUE")
            If (position=1)||(position=3)||(position=5) {
                If (value'=0)&&(value'=1) Throw ##class(%Exception.General).%New("INVALID_BOOLEAN_OPTION")
            }
            If (position=2)&&(value<0) Throw ##class(%Exception.General).%New("INVALID_SPLIT_SIZE")
            If (position=4)&&(value<(-1)) Throw ##class(%Exception.General).%New("INVALID_CACHE_LIMIT")
            If (position=4)&&(value=-1)&&('explicit) Throw ##class(%Exception.General).%New("UNBOUNDED_CACHE_REQUIRES_EXPLICIT_CHOICE")
            Set trials = item.trialValues, allowed = 0
            If '$IsObject(trials) Throw ##class(%Exception.General).%New("INVALID_TRIAL_VALUES")
            If 'trials.%IsA("%DynamicArray") Throw ##class(%Exception.General).%New("INVALID_TRIAL_VALUES")
            For trialIndex = 0:1:trials.%Size()-1 {
                If trials.%GetTypeOf(trialIndex)="number",trials.%Get(trialIndex)=value Set allowed = 1
            }
            If 'allowed Throw ##class(%Exception.General).%New("VALUE_NOT_IN_TRIALS")
            Set updates(position) = value, candidates(name) = ""
        }
        Set iterator = pChoices.%GetIterator()
        While iterator.%GetNext(.name,.value) {
            If '$Data(candidates(name)) Throw ##class(%Exception.General).%New("CHOICE_IS_NOT_A_CANDIDATE")
        }
        Lock +^Graph.Settings("Traversal"):5
        If '$Test Throw ##class(%Exception.General).%New("SETTINGS_LOCK_TIMEOUT")
        Set locked = 1, defaults = $ListBuild(0,0,0,4096,1), previous = $Get(^Graph.Settings("Traversal"),defaults), updated = previous, changes = []
        Set names = $ListBuild("pBalance","pSplitSize","pDegreeAware","pCacheLimit","pDirOpt")
        For position = 1:1:5 {
            If '$Data(updates(position)) Continue
            If $List(previous,position)=updates(position) Continue
            Set $List(updated,position) = updates(position)
            Do changes.%Push({"option":($List(names,position)),"before":($List(previous,position)),"after":(updates(position))})
        }
        Set pApplied = {"complete":true,"namespace":($Namespace),"applied":((changes.%Size()>0)),"changes":(changes),"before":(..SettingsObject(previous)),"after":(..SettingsObject(updated))}
        If changes.%Size() Set ^Graph.Settings("Traversal") = updated
    } Catch exception {
        Set status = exception.AsStatus(), pApplied = {"complete":false,"error":($SYSTEM.Status.GetErrorText(status))}
    }
    If locked Lock -^Graph.Settings("Traversal")
    Return status
}

/// 中文：将遍历策略选项名映射为持久化设置列表中的位置。
/// 未知选项返回 0，供调用方拒绝无效名称。
/// 入参：pName 是 pBalance、pSplitSize、pDegreeAware、pCacheLimit 或 pDirOpt；返回对应列表位置。
/// 示例：Set position=##class(Graph.Analysis).OptionIndex("pCacheLimit")
///
/// English: Map a traversal-policy option name to its position in the persisted settings list.
/// Returns 0 for an unknown option so callers can reject invalid names.
/// Parameter: pName is a supported traversal option; returns its settings-list position or 0 if unknown.
/// Example: Set position=##class(Graph.Analysis).OptionIndex("pCacheLimit")
ClassMethod OptionIndex(pName As %String) As %Integer [ Private ]
{
    Return $Select(pName="pBalance":1,pName="pSplitSize":2,pName="pDegreeAware":3,pName="pCacheLimit":4,pName="pDirOpt":5,1:0)
}

/// 中文：把按位置存储的遍历设置列表转换为带字段名的动态对象。
/// 入参：pSettings 是按策略顺序排列的列表；返回具名设置对象。
/// 示例：Set object=##class(Graph.Analysis).SettingsObject(settings)
///
/// English: Convert the positional traversal-settings list into a named dynamic object.
/// Parameter: pSettings is the ordered policy list; returns an object with named settings.
/// Example: Set object=##class(Graph.Analysis).SettingsObject(settings)
ClassMethod SettingsObject(pSettings As %String) As %DynamicObject [ Private ]
{
    Return {"pBalance":($List(pSettings,1)),"pSplitSize":($List(pSettings,2)),"pDegreeAware":($List(pSettings,3)),"pCacheLimit":($List(pSettings,4)),"pDirOpt":($List(pSettings,5))}
}

/// 中文：计算均值的保守区间；完整普查时区间半径为零，否则使用 Hoeffding 界。
/// 结果限定在变量取值范围内，并标注 95% 置信水平。
/// 入参：pMean 是估计均值，pRange 是变量上界，pCount 是样本数，pCensus 表示是否全量普查。
/// 示例：Set interval=##class(Graph.Analysis).MeanInterval(2,100,20,0)
///
/// English: Compute a conservative interval for a mean, using a Hoeffding bound unless the data is a census.
/// Bounds are clamped to the variable range and report 95% confidence.
/// Parameters: pMean is the estimate, pRange the variable upper bound, pCount the sample size and pCensus indicates a full census.
/// Example: Set interval=##class(Graph.Analysis).MeanInterval(2,100,20,0)
ClassMethod MeanInterval(pMean As %Numeric, pRange As %Numeric, pCount As %Integer, pCensus As %Boolean) As %DynamicObject [ Private ]
{
    Set radius = 0
    If 'pCensus,pCount Set radius = pRange*(($ZLn(40)/(2*pCount))**0.5)
    Set lower = pMean-radius, upper = pMean+radius
    If lower<0 Set lower = 0
    If upper>pRange Set upper = pRange
    Return {"estimate":(pMean),"lower":(lower),"upper":(upper),"confidence":0.95}
}

/// 中文：汇总当前命名空间 OUT/IN/OWN 的已分配 MB，考虑 Global 映射；不扫描节点邻接。
/// 入参：pSize 输出各全局映射区间及已分配空间汇总。
/// 示例：Set sc=##class(Graph.Analysis).Size(.size)
/// English: Sum allocated MB for namespace-visible OUT/IN/OWN mappings, not database file size.
/// Exact block measurement can incur I/O; unavailable/remote databases fail rather than being omitted.
/// Parameter: pSize receives allocated storage and mapping details. Example: Set sc=##class(Graph.Analysis).Size(.size)
ClassMethod Size(Output pSize As %DynamicObject) As %Status
{
    Set pSize = {}, status = $$$OK, result = ""
    Try {
        Set globals = [], total = 0
        For name = "GraphData.OUT","GraphData.IN","GraphData.OWN" {
            Set result = ##class(%ResultSet).%New("%SYS.GlobalQuery:NameSpaceSize")
            $$$ThrowOnError(result.Execute(name,0,0))
            Set allocated = 0, mappings = 0
            For {
                Set found = result.Next(.status)
                $$$ThrowOnError(status)
                Quit:'found
                Set allocated = allocated+result.Get("Allocated"), mappings = mappings+1
            }
            Do result.Close()
            Set total = total+allocated
            Do globals.%Push({"name":(name),"allocatedMB":(allocated),"mappingRanges":(mappings)})
        }
        Set pSize = {"allocatedMB":(total),"unit":"IRIS MB","method":"%SYS.GlobalQuery:NameSpaceSize FastFlag=0 SilentSkip=0","globals":(globals)}
    } Catch exception {
        If $IsObject(result) Do result.Close()
        Set status = exception.AsStatus(), pSize = {}
    }
    Return status
}

/// 中文：只读分析指定节点集合的诱导子图，并返回可选优化的候选试验建议。
/// pNodes：按引用传入 nodes(原始节点键) 集合，值被忽略，输入不会被修改。
/// 必须保留节点键的二进制表示及 ID 类型；数字 ID 与字符串 ID 不可互换。
/// 顶层变量不能有标量值；未定义的数组表示空集合，不表示整个命名空间。
/// pReport：输出动态对象，包含 complete、节点数、连接对数、自环、孤立节点、
/// 边界邻接数、方向度数的均值/p50/p95/最大值/变异系数、recommendations 和 warnings。
/// OUT 和 IN 分别计数，自环贡献两次度数，同一有向节点对的多种关系只计一次。
/// 集合外邻接仅计入边界统计，不扩展分析范围；缺失节点与孤立节点无法区分。
/// pMaxNodes/pMaxScans：正整数预算，默认 100000 个节点、1000000 个邻接条目。
/// 超限或参数错误返回错误 %Status；报告仅含 complete=false 和 error，不保留部分建议。
/// 入参：pNodes 是节点键集合，pMaxNodes/pMaxScans 分别限制节点数和邻接扫描条目；pReport 输出统计及候选建议。
/// 返回成功时，建议包含 option、candidate、currentDefault、trialValues、reason、condition。
/// 覆盖均衡、拆分、度数感知、缓存和方向优化；candidate 表示值得试验，不是应立即启用。
/// 不自动修改参数，缓存 -1 仍是可选无上限模式，需验证内存风险。
/// 无快照隔离，请在图和输入集合稳定时运行；预算不限制耗时或总内存。
/// 现有遍历接口不会自动限制在此集合内；存在边界邻接时，应核对真实查询范围。
/// English: Read-only analysis of an explicit node-set induced subgraph with optimization trials.
/// pNodes: By-reference nodes(opaqueNodeKey) membership; values are ignored and input is unchanged.
/// Preserve binary keys and ID types: numeric and string IDs are not interchangeable.
/// No top-level scalar is allowed. An undefined array means an empty set, not the whole namespace.
/// pReport: Dynamic object with complete, node/pair/self-loop/isolate counts, boundary entries,
/// directional-degree mean/p50/p95/max/coefficient of variation, recommendations and warnings.
/// OUT and IN count separately; self-loops contribute twice to degree; parallel relations count once.
/// External neighbors count as boundary entries without scope expansion. Missing keys look isolated.
/// pMaxNodes/pMaxScans: Positive integer budgets, defaulting to 100000 nodes/1000000 neighbor entries.
/// Invalid input or budget overflow returns an error %Status and only complete=false/error in the report.
/// Success includes option/candidate/currentDefault/trialValues/reason/condition for each recommendation.
/// Trials cover balancing, splitting, degree-aware search, caching and direction optimization.
/// Candidates require workload validation, not automatic activation; cache -1 remains an unbounded option.
/// No settings are applied and no snapshot is taken. Use stable graph data and input membership.
/// Budgets do not bound elapsed time or total memory. Traversal APIs are not constrained to this set.
/// Example / 示例：替换为真实节点键 / Replace with actual graph keys:
///   Kill nodes
///   Set nodes($ListBuild("patient-id","EMR.Patient")) = ""
///   Set nodes($ListBuild("drug-id","EMR.Drug")) = ""
///   Set sc = ##class(Graph.Analysis).AnalyzeNodes(.nodes,.report,100000,1000000)
///   If $SYSTEM.Status.IsError(sc) Do $SYSTEM.Status.DisplayError(sc)
///   If $SYSTEM.Status.IsOK(sc) Write report.%ToJSON(),!
/// English parameters: pNodes is the selected node-key set; pMaxNodes and pMaxScans bound work; pReport receives statistics and optional trials.
ClassMethod AnalyzeNodes(ByRef pNodes, Output pReport As %DynamicObject, pMaxNodes As %Integer = 100000, pMaxScans As %Integer = 1000000, pLayers As %String = "") As %Status
{
    Return ..Measure(.pNodes,.pReport,pMaxNodes,pMaxScans,0,0,pLayers)
}

/// 中文：分析阶段内部实现，对显式节点集合或命名空间全量节点执行受预算限制的度数统计。
/// pFullAdjacency 区分诱导子图与全邻接采样；成功输出统计和候选建议，失败不保留部分报告。
/// 入参：pNodes/pPopulation 表示分析范围，pMaxNodes/pMaxScans 是工作预算，pFullAdjacency 选择完整邻接扫描，pReport 接收结果。
/// 示例：Do ..Measure(.nodes,.report,100000,1000000,0,0)
///
/// English: Internal budgeted degree-analysis engine for an explicit node set or namespace-wide sample.
/// pFullAdjacency selects induced-subgraph versus full-adjacency sampling; failures discard partial reports.
/// Parameters: pNodes/pPopulation define scope, pMaxNodes/pMaxScans bound work, pFullAdjacency selects scan mode and pReport receives results.
/// Example: Do ..Measure(.nodes,.report,100000,1000000,0,0)
ClassMethod Measure(ByRef pNodes, Output pReport As %DynamicObject, pMaxNodes As %Integer, pMaxScans As %Integer, pFullAdjacency As %Boolean = 0, pPopulation As %Integer = 0, pLayers As %String = "") As %Status [ Private ]
{
    Set pReport = {"complete":false}, status = $$$OK
    Try {
        If (pMaxNodes<1)||(pMaxNodes'=(pMaxNodes\1))||(pMaxScans<1)||(pMaxScans'=(pMaxScans\1)) Throw ##class(%Exception.General).%New("INVALID_ANALYSIS_BUDGET")
        If ($Data(pNodes)#2) Throw ##class(%Exception.General).%New("NODE_SET_MUST_BE_SUBSCRIPTED")
        Set unitCount = ##class(Graph.Tools).units(0,1,pLayers,.unit)
        Set node = "", nodeCount = 0
        For {
            Set node = $Order(pNodes(node))
            Quit:node=""
            Set nodeCount = nodeCount+1
            If nodeCount>pMaxNodes Throw ##class(%Exception.General).%New("ANALYSIS_NODE_BUDGET_EXCEEDED")
        }
        Set scans = 0, pairs = 0, boundary = 0, selfLoops = 0, isolated = 0, totalDegree = 0, squares = 0, maximum = 0, node = ""
        For {
            Set node = $Order(pNodes(node))
            Quit:node=""
            Set degree = 0
            Kill seenNeighbor
            For unitIndex = 1:1:unitCount {
                Set direction = $List(unit(unitIndex),1), root = $List(unit(unitIndex),2), neighbor = ""
                For {
                    Set neighbor = $Order(@root@(node,neighbor))
                    Quit:neighbor=""
                    // 同一邻居在多层出现只计一次 | a neighbor present in several layers counts once
                    Continue:$Data(seenNeighbor(direction,neighbor))
                    Set seenNeighbor(direction,neighbor) = ""
                    Set scans = scans+1
                    If scans>pMaxScans Throw ##class(%Exception.General).%New("ANALYSIS_SCAN_BUDGET_EXCEEDED")
                    If 'pFullAdjacency,'$Data(pNodes(neighbor)) { Set boundary = boundary+1 Continue }
                    Set degree = degree+1
                    If 'direction {
                        Set pairs = pairs+1
                        If neighbor=node Set selfLoops = selfLoops+1
                    }
                }
            }
            If degree=0 Set isolated = isolated+1
            Set totalDegree = totalDegree+degree, squares = squares+(degree*degree)
            If degree>maximum Set maximum = degree
            Set histogram(degree) = $Get(histogram(degree))+1
        }
        Set mean = 0, variance = 0, coefficient = 0, p50 = 0, p95 = 0
        If nodeCount {
            Set mean = totalDegree/nodeCount, variance = (squares/nodeCount)-(mean*mean)
            If variance<0 Set variance = 0
            If mean Set coefficient = (variance**0.5)/mean
            Set rank = 0, degree = "", medianFound = 0, tailFound = 0
            For {
                Set degree = $Order(histogram(degree))
                Quit:degree=""
                Set rank = rank+histogram(degree)
                If 'medianFound && (rank>=((nodeCount+1)\2)) Set p50 = degree, medianFound = 1
                If 'tailFound && (rank>=((nodeCount*95+99)\100)) Set p95 = degree, tailFound = 1
            }
        }
        Set skewed = (coefficient>=1)&&(maximum>=(8*mean))&&(maximum>0)
        Set ruleNodes = $Select(pFullAdjacency:pPopulation,1:nodeCount)
        Set balanceCandidate = (ruleNodes>=64)&&skewed, splitCandidate = maximum>=1024
        Set degreeCandidate = skewed&&(maximum>=64), cacheCandidate = (ruleNodes>4096)&&(mean>=4)
        Set recommendations = []
        Do recommendations.%Push({"option":"pBalance","candidate":(balanceCandidate),"currentDefault":0,"trialValues":[0,1],"reason":($Select(balanceCandidate:"High degree dispersion suggests testing weighted assignment.",1:"No strong dataset-level imbalance signal; retain default.")),"condition":"Requires a queued top-down frontier with at least 64 nodes; validate actual frontier skew."})
        Set splitValues = [0]
        If splitCandidate Do splitValues.%Push(512)
        If maximum>2048 Do splitValues.%Push(2048)
        Do recommendations.%Push({"option":"pSplitSize","candidate":(splitCandidate),"currentDefault":0,"trialValues":(splitValues),"reason":($Select(splitCandidate:"High-degree nodes may benefit from range splitting.",1:"No node reaches the exploratory splitting threshold.")),"condition":"Multiple workers and top-down expansion required; preparation and JSON collection can outweigh gains."})
        Do recommendations.%Push({"option":"pDegreeAware","candidate":(degreeCandidate),"currentDefault":0,"trialValues":[0,1],"reason":($Select(degreeCandidate:"Skewed degrees suggest testing degree-aware shortest-path expansion.",1:"Degree skew does not justify changing the default.")),"condition":"Benchmark both query directions and short paths; estimation may cost more than it saves."})
        Do recommendations.%Push({"option":"pCacheLimit","candidate":(cacheCandidate),"currentDefault":4096,"trialValues":[0,4096,-1],"reason":($Select(cacheCandidate:"Dataset size and mean degree justify testing cache capacity.",1:"Retain bounded default without repeated-visit evidence.")),"condition":"Static degrees do not measure cache reuse; -1 is optional unbounded caching and requires memory measurement."})
        Do recommendations.%Push({"option":"pDirOpt","candidate":((pairs>0)&&(ruleNodes>=1000)),"currentDefault":1,"trialValues":[0,1],"reason":"Direction switching depends on reached frontiers and the namespace-wide node universe, not just dataset density.","condition":"Compare representative BFS depths; dataset statistics alone cannot choose a direction policy."})
        Set settings = $Get(^Graph.Settings("Traversal"))
        For index = 0:1:recommendations.%Size()-1 {
            Set item = recommendations.%Get(index), item.factoryDefault = item.currentDefault
            Set item.currentDefault = $ListGet(settings,..OptionIndex(item.option),item.factoryDefault)
            Set item.suggestedValue = item.currentDefault
            If item.candidate Set item.suggestedValue = $Select(item.option="pBalance":1,item.option="pSplitSize":512,item.option="pDegreeAware":1,item.option="pCacheLimit":4096,1:1)
        }
        Set warnings = ["Heuristics are trial recommendations, not measured speedups; no settings are applied.","Read-only scan has no snapshot isolation; analyze stable data and a stable input set.","Membership is explicit: missing and isolated nodes are indistinguishable without a node registry.","Traversal APIs do not restrict execution to this node set; boundary edges can change actual workloads.","Only neighbor entries are counted; relation multiplicity, cache hits and process peak memory are not measured.","Budgets bound node and neighbor-entry counts, not elapsed time or total memory."]
        Set pReport = {"complete":true,"scope":"induced-node-set","heuristicVersion":1,"nodeCount":(nodeCount),"directedPairs":(pairs),"selfLoopPairs":(selfLoops),"isolatedNodes":(isolated),"boundaryNeighborEntries":(boundary),"scannedNeighborEntries":(scans),"directionalDegree":{"mean":(mean),"p50":(p50),"p95":(p95),"max":(maximum),"coefficientOfVariation":(coefficient)},"budgets":{"maxNodes":(pMaxNodes),"maxScans":(pMaxScans)},"recommendations":(recommendations),"warnings":(warnings)}
    } Catch exception {
        Set status = exception.AsStatus(), pReport = {"complete":false,"error":($SYSTEM.Status.GetErrorText(status))}
    }
    Return status
}

}