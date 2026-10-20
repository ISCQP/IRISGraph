/// 图 vs SQL 头对头基准（其二）—— 用**传染病接触追踪**演示图远胜 SQL。
/// Graph-vs-SQL head-to-head benchmark (part 2) — infectious-disease CONTACT TRACING as the use case.
/// 
/// 三间分析 / The 3-axis model（人际 / 时间 / 空间 · person / time / space）:
///   原子事实是**时空在场** CTPresence(人, 地, [tStart,tEnd])。人-人接触边 CTContact 是**派生**的——
///   两条在场记录「同地点 ∧ 时间窗重叠」时产生一条接触，接触时刻 Ct = 重叠起点，Tier = 空间接近度。
///   一条接触边 = 三个维度的交集：同两人(人际) ∧ 时间重叠(时间) ∧ 同地共处(空间)。
///   The atomic fact is spatiotemporal presence; a contact edge is the intersection of all three axes.
/// 
/// 用例 / The use case（真实的接触追踪问题 / a real tracing question）:
///   从一个指示病例 P# 出发（t=0 起具传染性），沿**时序递增**的接触链，k 代（k 跳）以内可能波及哪些人？
///   传播链天生是**多跳 + 时序**的：a→b→c 只有在 接触(a,b) 时刻 ≤ 接触(b,c) 时刻 时才是真实传播路径
///   （时间不能倒流）。这正是关系型最吃亏、图最擅长的可达性查询。
///   From an index case (infectious from t=0), which people are reachable within k transmission
///   generations along TIME-RESPECTING contact chains? a→b→c is a real path only if contact(a,b)
///   happens no later than contact(b,c) — time cannot run backwards.
/// 
///   同一个「k 跳时序可达」问题分别回答并计时：
///     · 图  Graph : 建库时把接触边（第三层下标 = 接触时刻 Ct）物化进 ^GraphData.OUT/IN。之后做
///                   **时序 BFS**（Bellman-Ford 式松弛，最早到达时间），每代只沿 Ct ≥ 上一跳到达时刻的边
///                   展开，O(k·E) 且实际只碰用得上的边。
///     · SQL       : 在接触边表 EMR_Test.CTContact 上做 k 次自连接（PersonB→PersonA），每跳加
///                   Ct 单调约束（cj.Ct ≥ c(j-1).Ct）。SQL 语句直白，但可达性递归 → 中间结果 度^k 膨胀。
///     · Graph     : materialize contact edges (3rd subscript = contact time Ct) into ^GraphData; then a
///                   time-respecting BFS (earliest-arrival relaxation) expands only along edges with
///                   Ct ≥ the infector's arrival time.
///     · SQL       : k self-joins over CTContact with a monotonic-time constraint per hop → degree^k.
/// 
/// 关键点 / The point: 时序可达（谁可能被传染、按什么先后）本质是**递归 + 时间约束**；SQL 只能靠
/// k 次带序自连接硬算（度^k），图按邻接一次遍历。深度越大差距越悬殊——而时间约束让 SQL 雪上加霜。
/// 
/// EMR 映射 / EMR mapping: CTPresence ← HS.SDA3.Encounter(putEvent: eventStartDate/eventEndDate +
/// institution)；指示病例 ← putLabResult / putPooledLabResult 阳性；免疫/易感 ← putImmunization。
/// 
/// 用法 / Usage (NEHR namespace):
///   Do ##class(EMR.Test.ContactTrace).Run()                     // 默认参数 / defaults
///   Do ##class(EMR.Test.ContactTrace).Run(2000, 8, 6, 1)        // 人数, 同地密度扇出, 最大代数, 指示病例
///   Do ##class(EMR.Test.ContactTrace).Clear()                   // 清理 / cleanup
/// Author: QP
/// Version: 1.0
/// Last Modified Date: 2026/08/11
Class EMR.Test.ContactTrace Extends %RegisteredObject
{

/// 图节点「类名」——仅用于构造图 OID 与定向清理 / node "class" tag for graph OIDs + scoped cleanup.
Parameter NODECLS = "CTBench.Person";

/// 每人合成的在场记录数 / presences synthesized per person.
Parameter PRESPER = 5;

/// 每条在场记录的时长（时间单位）/ duration of each presence (time units).
Parameter DUR = 8;

/// 时间轴长度（时间单位，如天/小时）/ time horizon (units, e.g. days/hours).
Parameter HORIZON = 120;

/// 规模化合成时空在场并派生接触边：把接触同时物化进图全局（供时序 BFS）与 CTContact 表（供 SQL 自连接）。
/// 两侧写同一批边，保证「图邻接 ≡ SQL 接触表」逐边一致。
/// Synthesize presences and derive contacts, materializing into BOTH the graph globals (for the
/// time-respecting BFS) and CTContact (for the SQL self-join). Both sides get the identical edge set.
/// 
/// pFanout 控制同地共处密度（地点数 Loc≈人数/扇出）：地点越少→同地同期的人越多→接触扇出越大→
/// 时序多跳可达膨胀越快。返回派生的接触边数（无向计一次）。
/// pFanout controls co-location density (Loc≈people/fanout); fewer locations = denser contact = faster
/// multi-hop blowup. Returns the derived contact count (each undirected contact counted once).
ClassMethod Setup(pN As %Integer = 2000, pFanout As %Integer = 8, pVerbose As %Boolean = 1) As %Integer
{
    Set cls = ..#NODECLS, presPer = ..#PRESPER, dur = ..#DUR, horizon = ..#HORIZON
    Do ..Clear()
    Set t0 = $ZHorolog
    Set fan = $Select(pFanout > 0: pFanout, 1: 8)
    Set Loc = pN \ fan  Set:Loc<2 Loc = 2

    Set insP = ##class(%SQL.Statement).%New()  Do insP.%Prepare("INSERT INTO EMR_Test.CTPresence (PersonId, LocId, TStart, TEnd) VALUES (?, ?, ?, ?)")
    Set insC = ##class(%SQL.Statement).%New()  Do insC.%Prepare("INSERT INTO EMR_Test.CTContact (PersonA, PersonB, Ct, LocId, Tier) VALUES (?, ?, ?, ?, ?)")

    Kill ^||ctevt   // 按地点/起始时间归集在场，供扫描线派生接触 / presences bucketed by loc/tStart for the sweep
    Set np = 0, nc = 0
    TSTART
    For pid = 1:1:pN {
        For r = 1:1:presPer {
            Set loc = $Random(Loc) + 1
            Set ts = $Random(horizon - dur) + 1
            Set te = ts + dur
            Do insP.%Execute(pid, loc, ts, te)  Set np = np + 1
            Set ^||ctevt(loc, ts, pid) = te
        }
    }
    // 每个地点做区间重叠扫描线：新在场与当前所有仍活跃（未结束）的在场都构成一条接触，接触时刻 = 新在场起点。
    // Per-location interval-overlap sweep: a new presence contacts every still-active presence; contact time = its start.
    Set loc = ""
    For {
        Set loc = $Order(^||ctevt(loc))  Quit:loc=""
        Kill act, ends   // act(person)=tEnd（活跃集）; ends(tEnd,person)=""（按结束时间排序以便清退）
        Set ts = ""
        For {
            Set ts = $Order(^||ctevt(loc, ts))  Quit:ts=""
            Set pr = ""
            For {
                Set pr = $Order(^||ctevt(loc, ts, pr))  Quit:pr=""
                Set te = ^||ctevt(loc, ts, pr)
                // 清退已结束（tEnd ≤ ts，与新在场不重叠）的活跃在场
                Set ee = ""
                For {
                    Set ee = $Order(ends(ee))  Quit:(ee="")||(ee>ts)
                    Set qq = ""
                    For { Set qq = $Order(ends(ee, qq))  Quit:qq=""  Kill act(qq) }
                    Kill ends(ee)
                }
                // 新在场 pr 与所有仍活跃者接触
                Set qq = ""
                For {
                    Set qq = $Order(act(qq))  Quit:qq=""
                    Continue:qq=pr
                    Set tier = (loc # 3) + 1
                    Do ..addContact(pr, qq, ts, loc, tier, insC, cls)  Set nc = nc + 1
                }
                Set act(pr) = te, ends(te, pr) = ""
            }
        }
    }
    TCOMMIT
    Kill ^||ctevt

    Do $SYSTEM.SQL.TuneTable("EMR_Test.CTContact", 1, 0)
    Do $SYSTEM.SQL.TuneTable("EMR_Test.CTPresence", 1, 0)

    Set ^CTBench.Meta("persons") = pN, ^CTBench.Meta("contacts") = nc
    Set ^CTBench.Meta("locs") = Loc, ^CTBench.Meta("presences") = np, ^CTBench.Meta("horizon") = horizon
    Write:pVerbose "构建完成 built: ", pN, " 人/persons, ", np, " 在场/presences, ", Loc, " 地点/locations, ",
        nc, " 接触边/contacts  用时/time=", $FNumber($ZHorolog - t0, "", 2), "s", !
    Quit nc
}

/// 写一条无向接触（两个方向的有向边）：进 CTContact 表（SQL）与图全局 OUT/IN（BFS）。
/// 第三层下标是**接触时刻 Ct**，边值存 $lb(地点, 分层) 供画图时标注。返回 1。
/// Write one undirected contact (both directed edges) into CTContact and the graph globals. The 3rd
/// subscript is the contact time Ct; the edge value holds $lb(loc,tier) for later labeling. Returns 1.
ClassMethod addContact(pA As %Integer, pB As %Integer, pT As %Integer, pLoc As %Integer, pTier As %Integer, pIns As %SQL.Statement, pCls As %String) As %Integer [ Private ]
{
    Do pIns.%Execute(+pA, +pB, +pT, +pLoc, +pTier)
    Do pIns.%Execute(+pB, +pA, +pT, +pLoc, +pTier)
    Set ^GraphData.OUT("User", $ListBuild(+pA, pCls), $ListBuild(+pB, pCls), +pT) = $ListBuild(+pLoc, +pTier)
    Set ^GraphData.IN("User", $ListBuild(+pB, pCls), $ListBuild(+pA, pCls), +pT) = ""
    Set ^GraphData.OUT("User", $ListBuild(+pB, pCls), $ListBuild(+pA, pCls), +pT) = $ListBuild(+pLoc, +pTier)
    Set ^GraphData.IN("User", $ListBuild(+pA, pCls), $ListBuild(+pB, pCls), +pT) = ""
    Quit 1
}

/// 清理：只删本基准写入的 CTBench.Person 键，再清空两张表与元数据。绝不触碰生产 EMR 图。
/// Cleanup: remove only this benchmark's CTBench.Person keys, empty both tables + metadata.
ClassMethod Clear()
{
    Set cls = ..#NODECLS, k = ""
    For { Set k = $Order(^GraphData.OUT("User", k))  Quit:k=""  If $ListValid(k), $ListGet(k, 2) = cls { Kill ^GraphData.OUT("User", k) } }
    Set k = ""
    For { Set k = $Order(^GraphData.IN("User", k))   Quit:k=""  If $ListValid(k), $ListGet(k, 2) = cls { Kill ^GraphData.IN("User", k) } }
    Do ##class(EMR.Test.CTContact).%KillExtent()
    Do ##class(EMR.Test.CTPresence).%KillExtent()
    Kill ^CTBench.Meta
}

/// 基准数据是否已装载 / whether the benchmark data is loaded.
ClassMethod HasData() As %Boolean
{
    Quit ..PersonCount() > 0
}

/// 人数（起点取值范围 1..N）/ person count (valid start ids 1..N).
ClassMethod PersonCount() As %Integer
{
    Quit +$Get(^CTBench.Meta("persons"))
}

/// 接触边数（无向）/ undirected contact edge count.
ClassMethod ContactCount() As %Integer
{
    Quit +$Get(^CTBench.Meta("contacts"))
}

/// 图侧：**时序 BFS**（最早到达松弛）到第 k 代，返回 k 跳内时序可达的不同人数（不含起点）。
/// Graph side: time-respecting BFS (earliest-arrival relaxation) to generation k; returns the count of
/// distinct people reachable within k hops along non-decreasing contact times (excl. start).
/// 指示病例 t=0 起具传染性；每代只沿「接触时刻 ≥ 感染者到达时刻」的边展开（时间不倒流）。
/// Index case infectious from t=0; each generation follows only edges whose contact time ≥ the
/// infector's arrival time (time never runs backwards).
ClassMethod GraphReach(pStartId As %Integer, pK As %Integer) As %Integer
{
    Set cls = ..#NODECLS, s = +pStartId
    Kill best, cur
    Set best(s) = 0, cur(s) = 0
    // 双缓冲逐代松弛：本代只从上一代冻结的 cur 读，写入 nxt；避免同代内两条边被串联（否则会越界 k 跳而多计）。
    // Double-buffered layer relaxation: expand only from the previous layer's frozen cur, write into nxt,
    // so two edges can't chain within one round (which would overshoot the k-hop bound and over-count).
    For hop = 1:1:pK {
        Kill nxt
        Set p = ""
        For {
            Set p = $Order(cur(p))  Quit:p=""
            Set ap = cur(p), aoid = $ListBuild(+p, cls), boid = ""
            For {
                Set boid = $Order(^GraphData.OUT("User", aoid, boid))  Quit:boid=""
                Continue:'$ListValid(boid)
                Set b = $ListGet(boid, 1)
                Set ct = $Order(^GraphData.OUT("User", aoid, boid, ap - 1))
                Continue:ct=""
                Set imp = 0
                If '$Data(best(b)) { Set best(b) = ct, imp = 1 }
                ElseIf ct < best(b) { Set best(b) = ct, imp = 1 }
                If imp { If '$Data(nxt(b)) { Set nxt(b) = ct } ElseIf ct < nxt(b) { Set nxt(b) = ct } }
            }
        }
        Quit:'$Data(nxt)
        Kill cur  Merge cur = nxt
    }
    Set cnt = 0, x = ""
    For { Set x = $Order(best(x))  Quit:x=""  Set:x'=s cnt = cnt + 1 }
    Quit cnt
}

/// 图侧的「Graph SQL」版本：算法与 GraphReach 完全相同（双缓冲时序 BFS），只是把邻居枚举从
/// 直接 $Order(^GraphData.OUT) 换成经 Graph.SQL 的 SingleHop 表值函数（第三层下标 Ct 以 Relation 列返回）。
/// 用来量化「同一图遍历，走 SQL/TVF 封装层 vs 直接读全局」的开销。结果应与 GraphReach 完全一致。
/// The "Graph SQL" variant: identical algorithm to GraphReach (double-buffered time-respecting BFS),
/// but neighbor enumeration goes through the Graph.SQL SingleHop TVF (the 3rd subscript Ct comes back as
/// the Relation column) instead of a raw $Order(^GraphData.OUT). Measures the SQL/TVF wrapper overhead.
ClassMethod GraphReachSQL(pStartId As %Integer, pK As %Integer) As %Integer
{
    Set cls = ..#NODECLS, s = +pStartId
    Kill best, cur
    Set best(s) = 0, cur(s) = 0
    Set stmt = ##class(%SQL.Statement).%New()
    Do stmt.%Prepare("SELECT TargetId, Relation FROM Graph.SingleHop('" _ cls _ "', ?, '', 0)")
    For hop = 1:1:pK {
        Kill nxt
        Set p = ""
        For {
            Set p = $Order(cur(p))  Quit:p=""
            Set ap = cur(p)
            Set rs = stmt.%Execute(+p)
            While rs.%Next() {
                Set b = rs.%GetData(1), ct = rs.%GetData(2)
                Continue:ct<ap
                Set imp = 0
                If '$Data(best(b)) { Set best(b) = ct, imp = 1 }
                ElseIf ct < best(b) { Set best(b) = ct, imp = 1 }
                If imp { If '$Data(nxt(b)) { Set nxt(b) = ct } ElseIf ct < nxt(b) { Set nxt(b) = ct } }
            }
        }
        Quit:'$Data(nxt)
        Kill cur  Merge cur = nxt
    }
    Set cnt = 0, x = ""
    For { Set x = $Order(best(x))  Quit:x=""  Set:x'=s cnt = cnt + 1 }
    Quit cnt
}

/// 图侧执行的命令原文（供页面展示）/ the graph command executed (for display).
ClassMethod GraphCmd(pStartId As %Integer, pK As %Integer) As %String
{
    Quit "// 时序 BFS over ^GraphData.OUT（第三层下标=接触时刻 Ct），从指示病例 P" _ (+pStartId) _
        " 出发展开 " _ (+pK) _ " 代，每跳只沿 Ct≥感染者到达时刻的边 → 沿邻接一次遍历" _ $Char(10) _
        "// time-respecting BFS from index case P" _ (+pStartId) _ ", " _ (+pK) _ " generations, edges with Ct≥arrival only"
}

/// 构造纯 SQL 的 k 跳时序可达语句（供页面展示与执行共用）。
/// Build the pure-SQL k-hop time-respecting reachability statement (shared by display and execution).
/// 
/// 接触边存成表 CTContact(PersonA, PersonB, Ct, ...)。第 j 跳把 CTContact 沿 PersonB→PersonA 自连接 j 次，
/// 每跳加 Ct 单调约束（cj.Ct ≥ c(j-1).Ct）；起点 c1.PersonA = s 且 c1.Ct ≥ 0（t=0 起传染）。
/// k 跳取 1..k 各腿 UNION 后数不同的可达人。每加一跳多一次带序自连接 → 度^k 膨胀。
/// Hop j self-joins CTContact j times along PersonB→PersonA with a monotonic Ct constraint per hop.
ClassMethod SqlText(pStartId As %Integer, pK As %Integer) As %String
{
    Set s = +pStartId, e = "EMR_Test.CTContact"
    Set union = ""
    For j = 1:1:pK {
        Set from = e _ " c1"
        For h = 2:1:j { Set from = from _ " JOIN " _ e _ " c" _ h _ " ON c" _ h _ ".PersonA = c" _ (h - 1) _ ".PersonB AND c" _ h _ ".Ct >= c" _ (h - 1) _ ".Ct" }
        Set leg = "SELECT c" _ j _ ".PersonB AS P FROM " _ from _ " WHERE c1.PersonA = " _ s _ " AND c1.Ct >= 0"
        Set union = union _ $Select(j = 1: "", 1: " UNION ") _ leg
    }
    Quit "SELECT COUNT(DISTINCT P) FROM (" _ union _ ") d WHERE P <> " _ s
}

/// SQL 侧：纯 SQL 的 k 跳时序可达。对接触表 CTContact 做 k 次带序自连接（不预物化任何可达关系）。
/// SQL side: pure-SQL k-hop time-respecting reachability via k monotonic self-joins over CTContact.
ClassMethod SqlReach(pStartId As %Integer, pK As %Integer) As %Integer
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, ..SqlText(pStartId, pK))
    Quit $Select(rs.%Next(): rs.%GetData(1), 1: -1)
}

/// 单个深度 k 的一次对比测量（供 CSP 页面逐行调用）。热身一次后各计时一次，校验两侧一致。
/// One comparison measurement at depth k. Warms once, times each once, verifies parity.
/// Returns { k, reachable, graphMs, sqlMs, speedup, match, graphCount, sqlCount, sql, graphCmd }.
ClassMethod Bench(pStartId As %Integer, pK As %Integer) As %DynamicObject
{
    Set o = {}
    Set o.k = pK
    Set gN = ..GraphReach(pStartId, pK)
    Set sN = ..SqlReach(pStartId, pK)
    Set o.reachable = gN
    Set o.match = $Select(gN = sN: 1, 1: 0)
    Set o.graphCount = gN, o.sqlCount = sN
    Do ..GraphReach(pStartId, pK)
    Set g0 = $ZHorolog  Do ..GraphReach(pStartId, pK)  Set gt = $ZHorolog - g0
    Do ..SqlReach(pStartId, pK)
    Set s0 = $ZHorolog  Do ..SqlReach(pStartId, pK)  Set st = $ZHorolog - s0
    Set o.graphMs = $FNumber(gt * 1000, "", 2)
    Set o.sqlMs = $FNumber(st * 1000, "", 2)
    Set o.speedup = $Select(gt > 0: $FNumber(st / gt, "", 1), 1: 0)
    Set o.sql = ..SqlText(pStartId, pK)
    Set o.graphCmd = ..GraphCmd(pStartId, pK)
    Quit o
}

/// 抽取指示病例 k 代内的**时序传播树**（按代分层），供页面画图。节点数封顶 pMaxNodes。
/// 节点带代数 lvl 与显示名；每条树边标注它依据的接触（地点 + 接触时刻）。有向：感染者→被感染者。
/// Extract the time-respecting transmission TREE within k generations for drawing. Nodes carry a
/// generation lvl + name; each tree edge is labeled with the contact (location + time) it rests on.
/// Returns { start, k, truncated, nodes:[{id,lvl,name}], edges:[{s,t,r}] }.
ClassMethod ReachSubgraph(pStartId As %Integer, pK As %Integer, pMaxNodes As %Integer = 10000) As %DynamicObject
{
    Set cls = ..#NODECLS, s = +pStartId
    Kill arr, lvl, pred, cur
    Set arr(s) = 0, lvl(s) = 0, cur(s) = "", nodeCount = 1, capped = 0
    // 干净的**最短代数** BFS 传播树：每个节点只在其最小跳数（=传播代数）被确定一次，取该代内最早到达的接触为父。
    // 不做后代重松弛，故每条树边都是 第(h-1)代 → 第h代，绝不会出现同代→同代或回指的边。
    // Clean min-HOP generation BFS: each node is fixed once at its minimum hop (= transmission generation),
    // with the earliest arrival among that generation's parents; never re-relaxed. So every tree edge goes
    // gen(h-1) -> gen(h) — no same-generation and no backward edges.
    For hop = 1:1:pK {
        Kill lay, layp
        Set p = ""
        For {
            Set p = $Order(cur(p))  Quit:p=""
            Set ap = arr(p), aoid = $ListBuild(+p, cls), boid = ""
            For {
                Set boid = $Order(^GraphData.OUT("User", aoid, boid))  Quit:boid=""
                Continue:'$ListValid(boid)
                Set b = $ListGet(boid, 1)
                Continue:$Data(lvl(b))
                Set ct = $Order(^GraphData.OUT("User", aoid, boid, ap - 1))
                Continue:ct=""
                If '$Data(lay(b)) || (ct < lay(b)) {
                    Set lay(b) = ct, layp(b) = $ListBuild(+p, ct, $Get(^GraphData.OUT("User", aoid, boid, ct)))
                }
            }
        }
        Kill cur
        Set b = "", any = 0
        For {
            Set b = $Order(lay(b))  Quit:b=""
            If nodeCount '< pMaxNodes { Set capped = 1  Quit }
            Set lvl(b) = hop, arr(b) = lay(b), pred(b) = layp(b), cur(b) = "", nodeCount = nodeCount + 1, any = 1
        }
        Quit:'any
    }
    Set nodesArr = [], edgesArr = [], id = ""
    For { Set id = $Order(lvl(id))  Quit:id=""  Do nodesArr.%Push({"id":(+id), "lvl":(+lvl(id)), "name":("P" _ (+id))}) }
    Set id = ""
    For {
        Set id = $Order(pred(id))  Quit:id=""
        Set pe = pred(id), p = $ListGet(pe, 1), ct = $ListGet(pe, 2), val = $ListGet(pe, 3)
        Set locTxt = $Select($ListValid(val): "地点 L" _ $ListGet(val, 1), 1: "")
        // 边标注传播的**代际跃迁** 第(h-1)→h 代（h=被感染者代数），避免被误读成同代传染。
        Set gT = +lvl(id), gS = gT - 1
        Do edgesArr.%Push({"s":(+p), "t":(+id), "r":(locTxt _ " · 第" _ gS _ "→" _ gT _ "代 · t=" _ (+ct))})
    }
    Set o = {}
    Set o.start = +pStartId, o.k = +pK
    Set o.truncated = capped
    Set o.nodes = nodesArr, o.edges = edgesArr
    Quit o
}

/// 后台运行一个深度的对比，结果写入 ^CTBench.Job(pToken)，供 CSP 轮询以避免网关响应超时。
/// Background single-depth bench; result parked in ^CTBench.Job(token) so the page can poll it.
ClassMethod BenchAsync(pStartId As %Integer, pK As %Integer, pToken As %String)
{
    Try {
        Set ^CTBench.Job(pToken, "status") = "running"
        Set o = ..Bench(pStartId, pK)
        Set ^CTBench.Job(pToken, "json") = o.%ToJSON()
        Set ^CTBench.Job(pToken, "status") = "done"
    } Catch ex {
        Set ^CTBench.Job(pToken, "err") = ex.DisplayString()
        Set ^CTBench.Job(pToken, "status") = "error"
    }
    Quit
}

/// 跑基准并打印对比表：对每代 k，先校验两侧结果一致，再各计时。
/// Run the benchmark and print the comparison table.
ClassMethod Run(pN As %Integer = 2000, pFanout As %Integer = 8, pMaxK As %Integer = 6, pStartId As %Integer = 1)
{
    Do ..Setup(pN, pFanout)
    Write !, "=== Graph vs SQL：接触追踪时序可达（指示病例 start P", pStartId, "，人数 N=", pN, "，同地密度扇出 fanout≈", pFanout, "）===", !
    Write "模型 model：时空在场 → 同地+时间重叠派生接触；沿 Ct 不减的接触链，k 代内可能波及谁", !
    Write "k | reachable | Graph(BFS) s | SQL(k-join) s | 加速比 speedup", !
    Write "--+-----------+--------------+---------------+--------------", !
    For k = 1:1:pMaxK {
        Set gN = ..GraphReach(pStartId, k)
        Set sN = ..SqlReach(pStartId, k)
        Set ok = $Select(gN = sN: "", 1: "  <== MISMATCH g=" _ gN _ " s=" _ sN)
        Do ..GraphReach(pStartId, k)
        Set g0 = $ZHorolog  Do ..GraphReach(pStartId, k)  Set gt = $ZHorolog - g0
        Do ..SqlReach(pStartId, k)
        Set s0 = $ZHorolog  Do ..SqlReach(pStartId, k)  Set st = $ZHorolog - s0
        Set sp = $Select(gt > 0: $FNumber(st / gt, "", 1) _ "x", 1: "n/a")
        Write $Justify(k, 1), " | ", $Justify(gN, 9), " | ", $Justify($FNumber(gt, "", 4), 12), " | ",
            $Justify($FNumber(st, "", 4), 13), " | ", sp, ok, !
    }
    Write !, "结论 takeaway：时序可达是递归+时间约束的问题；SQL 每加一跳多一次带序自连接、度^k 膨胀，", !
    Write "             图沿邻接一次遍历。k 越大，SQL 越慢，图基本持平。", !
}

/// 三方对比：直接全局图遍历 GraphReach vs 走 Graph.SQL/TVF 的 GraphReachSQL vs 关系自连接 SqlReach。
/// 量化「图操作改走 Graph SQL 会慢多少」。每代先校验三者可达数一致，再各热身一次后各计时一次。
/// Three-way comparison to quantify how much slower the graph traversal is when routed through Graph SQL.
ClassMethod RunSQL(pN As %Integer = 2000, pFanout As %Integer = 8, pMaxK As %Integer = 6, pStartId As %Integer = 1)
{
    Do ..Setup(pN, pFanout)
    Write !, "=== 图操作：直接全局 vs Graph SQL（TVF） vs 关系 SQL（start P", pStartId, "，N=", pN, "，fanout≈", pFanout, "）===", !
    Write "k | reach | 直接图 raw ms | GraphSQL ms | 关系SQL ms | GraphSQL/raw | 关系SQL/raw | 校验", !
    Write "--+-------+--------------+-------------+-----------+--------------+------------+-----", !
    For k = 1:1:pMaxK {
        Set gN = ..GraphReach(pStartId, k)
        Set qN = ..GraphReachSQL(pStartId, k)
        Set sN = ..SqlReach(pStartId, k)
        Set ok = $Select((gN = qN) && (gN = sN): "OK", 1: "MISMATCH g=" _ gN _ " gsql=" _ qN _ " s=" _ sN)
        Do ..GraphReach(pStartId, k)
        Set g0 = $ZHorolog  Do ..GraphReach(pStartId, k)  Set gt = ($ZHorolog - g0) * 1000
        Do ..GraphReachSQL(pStartId, k)
        Set q0 = $ZHorolog  Do ..GraphReachSQL(pStartId, k)  Set qt = ($ZHorolog - q0) * 1000
        Do ..SqlReach(pStartId, k)
        Set s0 = $ZHorolog  Do ..SqlReach(pStartId, k)  Set st = ($ZHorolog - s0) * 1000
        Set rq = $Select(gt > 0: $FNumber(qt / gt, "", 1) _ "x", 1: "n/a")
        Set rs = $Select(gt > 0: $FNumber(st / gt, "", 1) _ "x", 1: "n/a")
        Write $Justify(k, 1), " | ", $Justify(gN, 5), " | ", $Justify($FNumber(gt, "", 2), 12), " | ",
            $Justify($FNumber(qt, "", 2), 11), " | ", $Justify($FNumber(st, "", 2), 9), " | ",
            $Justify(rq, 12), " | ", $Justify(rs, 10), " | ", ok, !
    }
    Write !, "说明：GraphSQL 与直接图算法完全相同，只是邻居枚举改走 Graph.SQL 的 SingleHop 表值函数。", !
    Write "     GraphSQL/raw = 走 SQL/TVF 封装层相对直接读全局的倍数（>1 即变慢）。", !
}

}
