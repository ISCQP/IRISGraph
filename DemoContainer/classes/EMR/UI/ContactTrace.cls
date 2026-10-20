Include %occInclude

/// 图 vs SQL · 接触追踪时序可达 · CSP 页面
/// Graph vs SQL · time-respecting contact tracing · CSP page
/// Author: QP
/// Version: 1.1
/// Last Modified Date: 2026/08/10
/// 
/// 访问 / Visit：/csp/healthshare/nehr/EMR.UI.ContactTrace.cls
///   ?action=build&n=<人数>&deg=<同地密度扇出>  构建合成时空在场数据 + 派生接触边（物化为图边） / build synthetic presences + derived contacts
///   ?action=benchstart&start=<指示病例>&k=<代数>  启动后台任务，返回 token / start a background job, returns token
///   ?action=benchpoll&token=<token>          轮询任务状态/结果 / poll job status/result
///   ?action=subgraph&start=&k=               返回时序传播树 / return the transmission tree
///   ?action=clear                             清理基准数据 / clear benchmark data
/// 
/// 用例：传染病接触追踪的「三间分析」（人际间 / 时间 / 空间）。以某个指示病例为起点，沿
/// **时间不倒流**的接触链（接触时刻 Ct 不减），问 k 代传播内可能波及谁。接触边由时空在场事实派生：
/// 同一地点、时间重叠的两个人之间成一条带接触时刻的边。这就是关系型最吃亏、图最擅长的**时序多跳可达**。
/// SQL 侧把接触存成 EMR_Test.CTContact(PersonA, PersonB, Ct, ...)，每加一代就多一次带 Ct 单调约束的自连接（度^k）。
/// 图侧把接触物化进 ^GraphData 邻接，用**时序分层 BFS**一次 O(V+E) 遍历。并排展示 SQL / Graph 命令、结果一致性、耗时。
Class EMR.UI.ContactTrace Extends %CSP.Page
{

Parameter CONTENTTYPE = "text/html";

Parameter CHARSET = "UTF-8";

ClassMethod OnPage() As %Status
{
    Set action = %request.Get("action")
    Set n = +$Get(%request.Data("n", 1), 2000)
    Set deg = +$Get(%request.Data("deg", 1), 8)
    Set start = +$Get(%request.Data("start", 1), 1)
    Set maxk = +$Get(%request.Data("maxk", 1), 6)
    // 保护上限 / guard rails
    Set:n<100 n = 100  Set:n>50000 n = 50000
    Set:deg<2 deg = 2  Set:deg>20 deg = 20
    Set:start<1 start = 1
    Set:maxk<1 maxk = 1  Set:maxk>7 maxk = 7

    // 启动后台对比任务，立即返回 token / kick off a background bench job, return token immediately
    If action = "benchstart" {
        Set %response.ContentType = "application/json"
        Set k1 = +$Get(%request.Data("k", 1), 1)
        Set:k1<1 k1 = 1  Set:k1>7 k1 = 7
        Set r = {}
        If '##class(EMR.Test.ContactTrace).HasData() {
            Set r.error = "nodata"
            Write r.%ToJSON()
            Quit $$$OK
        }
        Set token = $Increment(^CTBench.Seq) _ "-" _ $Job
        Kill ^CTBench.Job(token)
        Set ^CTBench.Job(token, "status") = "queued"
        Job ##class(EMR.Test.ContactTrace).BenchAsync(start, k1, token)
        Set r.token = token
        Write r.%ToJSON()
        Quit $$$OK
    }

    // 轮询后台任务状态 / poll a background job
    If action = "benchpoll" {
        Set %response.ContentType = "application/json"
        Set token = %request.Get("token")
        Set st = $Get(^CTBench.Job(token, "status"), "unknown")
        Set r = {}
        If st = "done" {
            Set r.status = "done"
            Set r.result = {}.%FromJSON($Get(^CTBench.Job(token, "json"), "{}"))
            Kill ^CTBench.Job(token)
        } ElseIf st = "error" {
            Set r.status = "error"
            Set r.err = $Get(^CTBench.Job(token, "err"), "error")
            Kill ^CTBench.Job(token)
        } Else {
            Set r.status = st
        }
        Write r.%ToJSON()
        Quit $$$OK
    }

    // 抽取指示病例 k 代内的时序传播树 / return the transmission tree within k generations
    If action = "subgraph" {
        Set %response.ContentType = "application/json"
        Set k2 = +$Get(%request.Data("k", 1), 1)
        Set:k2<1 k2 = 1  Set:k2>7 k2 = 7
        If '##class(EMR.Test.ContactTrace).HasData() { Write "{""error"":""nodata""}"  Quit $$$OK }
        Write ##class(EMR.Test.ContactTrace).ReachSubgraph(start, k2, 10000).%ToJSON()
        Quit $$$OK
    }

    If action = "clear" { Do ##class(EMR.Test.ContactTrace).Clear() }
    If action = "build" { Do ##class(EMR.Test.ContactTrace).Setup(n, deg, 0) }

    Write "<!DOCTYPE html>", !
    Write "<html lang='zh-CN'><head><meta charset='UTF-8'>", !
    Write "<meta name='viewport' content='width=device-width, initial-scale=1.0'>", !
    Write "<title>Graph vs SQL · 接触追踪</title>", !
    Do ##class(Graph.UI.Network).Head()
    Write "<style>", ..CSS(), ##class(Graph.UI.Network).CSS(), "</style>", !
    Write "</head><body>", !

    Set has = ##class(EMR.Test.ContactTrace).HasData()
    Set pc = $Select(has: ##class(EMR.Test.ContactTrace).PersonCount(), 1: 0)
    Set cc = $Select(has: ##class(EMR.Test.ContactTrace).ContactCount(), 1: 0)

    // 顶栏 / top bar
    Write "<header class='topbar'>"
    Write "<div class='brand'>&#129440; <span data-i18n='brand'></span></div>"
    Write "<div class='sub' id='ct-sub'></div>"
    Write "<button type='button' id='langtoggle' class='rebuild'>&#127760; <span data-i18n='langBtn'></span></button>"
    If has { Write "<a class='rebuild danger' href='?action=clear'>&#128465; <span data-i18n='clear'></span></a>" }
    Write "</header>", !

    Do ..RenderConfig(n, deg, start, maxk, has)

    If has {
        Write "<div id='runout'><section class='card tip' id='ct-tip'></section></div>", !
    } Else {
        Write "<div id='runout'></div>", !
        Do ..RenderIntro()
    }

    Write "<footer class='foot' data-i18n='footer'></footer>", !
    Write "<script>", ..JS(has, pc, cc), "</script>", !
    Write "</body></html>", !
    Quit $$$OK
}

/// 配置区：构建参数 + 运行参数 / config: build params + run params
ClassMethod RenderConfig(pN As %Integer, pDeg As %Integer, pStart As %Integer, pMaxK As %Integer, pHas As %Boolean)
{
    Write "<section class='card'>"
    Write "<h2>1&#65039;&#8419; <span data-i18n='build1'></span> <span class='hint' data-i18n='build1h'></span></h2>"
    Write "<form method='get' class='cfg'>"
    Write "<input type='hidden' name='action' value='build'>"
    Write "<label><span data-i18n='persons'></span><input type='number' name='n' value='", pN, "' min='100' max='50000' step='100'></label>"
    Write "<label><span data-i18n='fanout'></span><input type='number' name='deg' value='", pDeg, "' min='2' max='20'></label>"
    Write "<button class='btn build' type='submit'>&#128296; <span data-i18n='buildBtn'></span></button>"
    Write "</form>"

    Write "<h2 style='margin-top:18px'>2&#65039;&#8419; <span data-i18n='run2'></span> <span class='hint' data-i18n='run2h'></span></h2>"
    Write "<div class='cfg'>"
    Write "<label><span data-i18n='startLbl'></span><input type='number' id='runStart' value='", pStart, "' min='1'></label>"
    Write "<label><span data-i18n='maxgens'></span><input type='number' id='runMaxk' value='", pMaxK, "' min='1' max='7'></label>"
    Write "<button class='btn run' type='button' id='runBtn' onclick='runBench()'", $Select(pHas: "", 1: " disabled"), ">&#9654;&#65039; <span data-i18n='runBtn'></span></button>"
    Write "</div>"
    Write "</section>", !
}

/// 前端脚本：点击运行后逐代拉取 benchjson，实时刷新进度条与结果 / progressive runner
ClassMethod JS(pHas As %Boolean, pPc As %Integer, pCc As %Integer) As %String
{
    Set nl = $Char(10)
    Set s = ""
    // ---- language / i18n ----
    Set s = s _ "var LANG=localStorage.getItem('ctlang');" _ nl
    Set s = s _ "if(LANG!=='zh'&&LANG!=='en'){LANG=((navigator.language||'').toLowerCase().indexOf('zh')===0)?'zh':'en';}" _ nl
    Set s = s _ "function L(z,e){return LANG==='zh'?z:e;}" _ nl
    Set s = s _ "var CTHAS=" _ $Select(pHas: 1, 1: 0) _ ",CTPC=" _ +pPc _ ",CTCC=" _ +pCc _ ";" _ nl
    Set s = s _ "var I18N={" _ nl
    Set s = s _ "langBtn:{zh:'EN',en:'中文'}," _ nl
    Set s = s _ "brand:{zh:'Graph vs SQL · 接触追踪 · 时序传播链性能对比',en:'Graph vs SQL · contact tracing · time-respecting propagation'}," _ nl
    Set s = s _ "clear:{zh:'清理',en:'Clear'}," _ nl
    Set s = s _ "build1:{zh:'构建接触网络',en:'Build contact network'}," _ nl
    Set s = s _ "build1h:{zh:'（合成时空在场事实 → 同地+时间重叠派生接触，物化为图边）',en:'(synthetic presences → contacts from same place/time overlap, materialized as graph edges)'}," _ nl
    Set s = s _ "persons:{zh:'人数 Persons',en:'Persons'}," _ nl
    Set s = s _ "fanout:{zh:'同地密度扇出 Fanout',en:'Co-location fanout'}," _ nl
    Set s = s _ "buildBtn:{zh:'构建',en:'Build'}," _ nl
    Set s = s _ "run2:{zh:'运行对比',en:'Run comparison'}," _ nl
    Set s = s _ "run2h:{zh:'（逐代 k=1..maxK 各跑一次，实时显示进度）',en:'(one run per generation k=1..maxK, live progress)'}," _ nl
    Set s = s _ "startLbl:{zh:'起点/指示病例 P#',en:'Start / index case P#'}," _ nl
    Set s = s _ "maxgens:{zh:'最大代数 Max gens',en:'Max generations'}," _ nl
    Set s = s _ "runBtn:{zh:'运行对比',en:'Run comparison'}," _ nl
    Set s = s _ "footer:{zh:'用例：传染病接触追踪三间分析（人际间/时间/空间） · 沿接触时刻 Ct 不减的接触链，k 代传播内可能波及谁 · 图 Graph：^GraphData.OUT 邻接指针，时序分层 BFS（O(V+E)） · SQL：在 CTContact(PersonA, PersonB, Ct) 上逐代自连接 + Ct 单调约束（中间结果 ≈ 度^k）',en:'Use case: contact-tracing three-axis analysis (person / time / space) · along a non-decreasing-Ct contact chain, who is reachable within k generations · Graph: ^GraphData.OUT adjacency pointers, layered temporal BFS (O(V+E)) · SQL: per-generation self-joins on CTContact(PersonA, PersonB, Ct) with a monotonic Ct constraint (intermediate results ≈ degree^k)'}" _ nl
    Set s = s _ "};" _ nl
    Set s = s _ "function t(k){var e=I18N[k];return e?(e[LANG]||e.en):k;}" _ nl
    // ---- dynamic sub / tip / intro ----
    Set s = s _ "function ctSub(){var el=document.getElementById('ct-sub');if(!el)return;el.innerHTML=CTHAS?L('基准图已就绪 · '+CTPC+' 人 / '+CTCC+' 条接触边','Graph ready · '+CTPC+' persons / '+CTCC+' contact edges'):L('尚未构建基准图','No benchmark graph yet');}" _ nl
    Set s = s _ "function ctTip(){var el=document.getElementById('ct-tip');if(!el)return;el.innerHTML=L('基准图已就绪，点击 <b>运行对比</b> 开始，运行时会实时显示进度。','The graph is ready — click <b>Run comparison</b> to start; progress is shown live.');}" _ nl
    Set s = s _ "function ctIntro(){var el=document.getElementById('ct-intro');if(!el)return;el.innerHTML=L('<h2>&#128161; 这是什么</h2><p><b>传染病接触追踪</b>的核心是<b>三间分析</b>——<b>人际间（谁接触了谁）· 时间（何时接触，且时间不能倒流）· 空间（在哪里同处）</b>。本页把最原子的事实建成<b>时空在场</b>：某人在某地点、某时间段出现。当两个人<b>同一地点、时间重叠</b>时，派生一条带<b>接触时刻 Ct</b>的人-人接触边。从某个<b>指示病例</b>出发，沿<b>接触时刻不减</b>（时间不倒流）的接触链问「k 代传播内可能波及谁」——这正是需要<b>时序多跳递归</b>才能回答的问题。图侧把接触物化进 ^GraphData 邻接，用<b>时序分层 BFS</b> 一次 O(V+E) 遍历；SQL 侧把接触存成 CTContact(PersonA, PersonB, Ct)，每加一代都<b>再自连接一次</b>并加 Ct 单调约束。</p><p>&#11014;&#65039; 先在上方 <b>构建接触网络</b>，再 <b>运行对比</b>。</p>','<h2>&#128161; What is this</h2><p>Contact tracing is built on three axes — <b>who met whom</b> (person), <b>when</b> (time, which cannot run backwards), and <b>where</b> (space). The atomic fact is a spatiotemporal <b>presence</b>; a person-person contact edge with a contact time is derived when two presences overlap in time and place. From an index case, asking who is reachable within k generations along a <b>time-respecting</b> chain (non-decreasing contact time) is intrinsically recursive. The graph traverses the materialized adjacency once (O(V+E)); SQL self-joins the contact table once per generation with a monotonic-time constraint (degree^k).</p><p>&#11014;&#65039; Build the network above, then run the comparison.</p>');}" _ nl
    // ---- runner ----
    Set s = s _ "var benchRows=[];var maxMs=1;var runStartVal=1;" _ nl
    Set s = s _ "function jesc(x){return (x+'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}" _ nl
    Set s = s _ "function jpretty(x){var t=jesc(x).replace(/ UNION /g,'\nUNION\n').replace('SELECT COUNT','\nSELECT COUNT');return t.charAt(0)=='\n'?t.substr(1):t;}" _ nl
    Set s = s _ "function setProg(pct,msg){var f=document.getElementById('pfill');if(f)f.style.width=Math.round(pct)+'%';var m=document.getElementById('pmsg');if(m)m.innerHTML=msg+'  '+Math.round(pct)+'%';}" _ nl
    Set s = s _ "function sleep(ms){return new Promise(function(res){setTimeout(res,ms);});}" _ nl
    Set s = s _ "async function runJob(start,k,maxk){" _ nl
    Set s = s _ " var sresp=await fetch(`?action=benchstart&start=${start}&k=${k}`);var sj=await sresp.json();" _ nl
    Set s = s _ " if(sj.error) throw new Error(sj.error);" _ nl
    Set s = s _ " var token=sj.token;var t0=Date.now();" _ nl
    Set s = s _ " for(;;){" _ nl
    Set s = s _ "  await sleep(700);" _ nl
    Set s = s _ "  var presp=await fetch(`?action=benchpoll&token=${encodeURIComponent(token)}`);var p=await presp.json();" _ nl
    Set s = s _ "  if(p.status=='done') return p.result;" _ nl
    Set s = s _ "  if(p.status=='error') throw new Error(p.err||'error');" _ nl
    Set s = s _ "  if(p.status=='unknown') throw new Error('job lost');" _ nl
    Set s = s _ "  var sec=((Date.now()-t0)/1000).toFixed(1);" _ nl
    Set s = s _ "  setProg((k-1)/maxk*100,`<span class='spin'></span>k=${k}/${maxk} ${L('后台运行中','running')} ${sec}s... ${L('深层 SQL 可能较慢','deep SQL may be slow')}`);" _ nl
    Set s = s _ "  if(Date.now()-t0>600000) throw new Error('timeout>10min');" _ nl
    Set s = s _ " }" _ nl
    Set s = s _ "}" _ nl
    Set s = s _ "async function runBench(){" _ nl
    Set s = s _ " var start=parseInt(document.getElementById('runStart').value)||1;if(start<1)start=1;runStartVal=start;" _ nl
    Set s = s _ " var maxk=parseInt(document.getElementById('runMaxk').value)||1;if(maxk<1)maxk=1;if(maxk>7)maxk=7;" _ nl
    Set s = s _ " var btn=document.getElementById('runBtn');btn.disabled=true;" _ nl
    Set s = s _ " benchRows=[];maxMs=1;" _ nl
    Set s = s _ " document.getElementById('runout').innerHTML=`<section class='card' id='progcard'><h2>&#9203; ${L('运行进度','Progress')}</h2><div class='pbar'><span id='pfill'></span></div><div class='pmsg' id='pmsg'><span class='spin'></span>${L('准备中…','preparing…')}</div></section><div id='reswrap'></div>`;" _ nl
    Set s = s _ " for(var k=1;k<=maxk;k++){" _ nl
    Set s = s _ "  setProg((k-1)/maxk*100,`<span class='spin'></span>k=${k}/${maxk} ${L('运行中…','running…')} ${L('深层 SQL 可能较慢','deep SQL may be slow')}`);" _ nl
    Set s = s _ "  var r;" _ nl
    Set s = s _ "  try{r=await runJob(start,k,maxk);}" _ nl
    Set s = s _ "  catch(e){setProg((k-1)/maxk*100,`&#10007; ${L('出错','error')}: ${e}`);btn.disabled=false;return;}" _ nl
    Set s = s _ "  if(r.error){setProg((k-1)/maxk*100,`&#10007; ${L('请先构建基准图','build the graph first')}`);btn.disabled=false;return;}" _ nl
    Set s = s _ "  r.graphMs=parseFloat(r.graphMs);r.sqlMs=parseFloat(r.sqlMs);r.speedup=parseFloat(r.speedup);" _ nl
    Set s = s _ "  benchRows.push(r);maxMs=Math.max(maxMs,r.graphMs,r.sqlMs);render();" _ nl
    Set s = s _ "  setProg(k/maxk*100,`${L('已完成','done')} ${k}/${maxk}`);" _ nl
    Set s = s _ " }" _ nl
    Set s = s _ " var pc=document.getElementById('progcard');if(pc)pc.className+=' done';" _ nl
    Set s = s _ " setProg(100,`&#10003; ${L('全部完成','all done')}`);btn.disabled=false;" _ nl
    Set s = s _ " loadGraph(start,maxk);" _ nl
    Set s = s _ "}" _ nl
    Set s = s _ "function render(){" _ nl
    Set s = s _ " var last=benchRows[benchRows.length-1];" _ nl
    Set s = s _ " var h=`<section class='card'><h2>&#128202; ${L('对比结果','Results')}</h2><p class='usecase'>&#127919; ${L('用例：以指示病例 <b>P#'+runStartVal+'</b> 为起点，沿**时间不倒流**的接触链（接触时刻 Ct 不减）找出 k 代传播内可能波及的人 · 图侧时序分层 BFS 走物化邻接，SQL 侧在接触表上逐代自连接 + Ct 单调约束。','Use case: from index case <b>P#'+runStartVal+'</b>, follow time-respecting contact chains (non-decreasing Ct) to find who is reachable within k generations · the graph runs a layered temporal BFS over materialized adjacency, SQL self-joins the contact table per generation with a monotonic Ct constraint.')}</p><table class='res'><thead><tr><th>k</th><th>${L('波及','Reachable')}</th><th>Graph<br>ms</th><th>SQL<br>ms</th><th>${L('加速','Speedup')}</th><th>${L('耗时对比','Time')} Graph &#9632; / SQL &#9632;</th></tr></thead><tbody>`;" _ nl
    Set s = s _ " for(var i=0;i<benchRows.length;i++){var r=benchRows[i];" _ nl
    Set s = s _ "  var stat=r.match==1?`<span class='ok' title='${L('结果一致','match')}'>&#10003;</span>`:`<span class='bad' title='${L('不一致','mismatch')} g=${r.graphCount} s=${r.sqlCount}'>&#10007;</span>`;" _ nl
    Set s = s _ "  var gw=r.graphMs/maxMs*100;if(gw<1.5)gw=1.5;var sw=r.sqlMs/maxMs*100;if(sw<1.5)sw=1.5;" _ nl
    Set s = s _ "  var sp=r.speedup>=10?'sp-hi':(r.speedup>=2?'sp-mid':'sp-lo');" _ nl
    Set s = s _ "  h+=`<tr><td class='kc'>${r.k}</td><td>${r.reachable} ${stat}</td><td class='num'>${r.graphMs.toFixed(2)}</td><td class='num'>${r.sqlMs.toFixed(2)}</td><td class='num'><span class='sp ${sp}'>${r.speedup.toFixed(1)}x</span></td><td class='barcell'><div class='bar'><span class='bg' style='width:${gw}%'></span></div><div class='bar'><span class='bs' style='width:${sw}%'></span></div></td></tr>`;" _ nl
    Set s = s _ " }" _ nl
    Set s = s _ " h+=`</tbody></table>`;" _ nl
    Set s = s _ " if(last){h+=`<p class='takeaway'>${L('结论：SQL 每加一代就多一次带 Ct 单调约束的自连接、中间结果按 <b>度^k</b> 膨胀；图只按 <b>O(V+E)</b> 时序遍历一次。','Takeaway: each extra generation adds another self-join with a monotonic Ct constraint and inflates intermediate results by <b>degree^k</b> for SQL; the graph makes a single <b>O(V+E)</b> temporal pass.')} ${L('最深','deepest')} k=${last.k}: SQL ${last.sqlMs.toFixed(1)} ms vs Graph ${last.graphMs.toFixed(1)} ms (<b>${last.speedup.toFixed(1)}x</b>)</p>`;}" _ nl
    Set s = s _ " h+=`</section><section class='card'><h2>&#128269; ${L('执行的语句 / 命令','Executed statements &amp; commands')} <span class='hint'>(${L('仅显示最深','deepest only')} k=${last?last.k:0})</span></h2>`;" _ nl
    Set s = s _ " if(last){var q=last;" _ nl
    Set s = s _ "  h+=`<details open><summary>k = ${q.k} ${L('代','gens')} &#183; Graph ${q.graphMs.toFixed(2)} ms vs SQL ${q.sqlMs.toFixed(2)} ms &#183; ${q.speedup.toFixed(1)}x</summary><div class='exec'><div class='eng graph'><div class='eh'>&#129517; ${L('Graph 命令','Graph command')}</div><pre>${jesc(q.graphCmd)}</pre></div><div class='eng sql'><div class='eh'>&#128190; ${L('SQL 语句','SQL statement')}</div><pre>${jpretty(q.sql)}</pre></div></div></details>`;" _ nl
    Set s = s _ " }" _ nl
    Set s = s _ " h+=`</section>`;" _ nl
    Set s = s _ " document.getElementById('reswrap').innerHTML=h;" _ nl
    Set s = s _ "}" _ nl
    Set s = s _ "async function loadGraph(start,k){" _ nl
    Set s = s _ " var last=benchRows[benchRows.length-1];" _ nl
    Set s = s _ " var host=document.getElementById('reswrap');if(!host)return;" _ nl
    Set s = s _ " var card=document.createElement('section');card.className='card';card.id='graphcard';" _ nl
    Set s = s _ " card.innerHTML=`<h2>&#127760; ${L('时序传播圈图','Transmission Circos')} <span class='hint'>(P#${start} · ${L('最深','depth')} k=${k})</span></h2><div class='gload'><span class='spin'></span>${L('加载图数据中…','loading graph…')}</div>`;" _ nl
    Set s = s _ " host.appendChild(card);" _ nl
    Set s = s _ " try{" _ nl
    Set s = s _ "  var resp=await fetch(`?action=subgraph&start=${start}&k=${k}`);var d=await resp.json();" _ nl
    Set s = s _ "  if(d.error||!d.nodes||!window.vis){var g0=card.querySelector('.gload');if(g0)g0.innerHTML='&#10007; '+L('无图数据','no graph data');return;}" _ nl
    Set s = s _ "  var reach=last?last.reachable:(d.nodes.length-1);" _ nl
    Set s = s _ "  var cap=d.truncated?L('（图中仅示意前 '+d.nodes.length+' 个节点，实际波及 '+reach+'）',' (showing first '+d.nodes.length+' nodes; '+reach+' reachable)'):L('（共 '+(d.nodes.length-1)+' 个被波及者）',' ('+(d.nodes.length-1)+' reachable)');" _ nl
    // 第 0 代=指示病例（源头），用近黑独立色，代 1..N 才走暖→冷调色板 / gen 0 = index case: distinct near-black; gens 1..N use the palette
    Set s = s _ "  var pal=['#dc2626','#2563eb','#16a34a','#7c3aed','#ea580c','#0891b2','#db2777','#ca8a04'];" _ nl
    Set s = s _ "  function genColor(l){return l===0?'#0f172a':pal[(l-1)%pal.length];}" _ nl
    Set s = s _ "  var maxLvl=0;d.nodes.forEach(function(n){if(n.lvl>maxLvl)maxLvl=n.lvl;});" _ nl
    Set s = s _ "  var seen={};d.nodes.forEach(function(n){seen[n.lvl]=(seen[n.lvl]||0)+1;});" _ nl
    Set s = s _ "  var legend='';for(var lv=0;lv<=maxLvl;lv++){if(!seen[lv])continue;var nm=lv===0?L('指示病例（第0代）','index case (gen 0)'):L('第'+lv+'代','gen '+lv);legend+=`<span><i class='gnw-dot' style='background:${genColor(lv)}'></i>${nm} · ${seen[lv]}</span>`;}" _ nl
    // 节点带 level 与配色，按代分组排成 Circos 圈图弧段（弦=代际传播），交给标准渲染器 gnwRender 的 circos 布局
    Set s = s _ "  var vnodes=d.nodes.slice().sort(function(a,b){return a.lvl-b.lvl;}).map(function(n){var o={id:n.id,level:n.lvl,group:L('第'+n.lvl+'代','gen '+n.lvl),label:n.name,title:n.name+' · '+(n.lvl===0?L('指示病例（第0代）','index case (gen 0)'):L('第'+n.lvl+'代','gen '+n.lvl)),color:{background:genColor(n.lvl),border:genColor(n.lvl)},font:{color:'#fff'}};if(n.lvl===0){o.label='\u2605 '+n.name;o.size=32;o.borderWidth=5;o.color.border='#fbbf24';o.font={size:16,color:'#fff'};}return o;});" _ nl
    Set s = s _ "  var vedges=d.edges.map(function(e){return {from:e.s,to:e.t,label:e.r,title:e.r};});" _ nl
    Set s = s _ "  card.innerHTML=`<h2>&#127760; ${L('时序传播圈图','Transmission Circos')} <span class='hint'>(P#${start} · ${L('最深','depth')} k=${k}${cap})</span></h2><div class='gnw'><div class='gnw-bar'><button type='button' class='gz-in'>&#43;</button><button type='button' class='gz-out'>&#8722;</button><button type='button' class='gz-fit'>&#9635; ${L('适应','fit')}</button></div><div id='ctsub' class='gnw-net' style='height:480px'></div><div class='gnw-legend'>${legend}</div><div id='ctsub-info' class='gnw-info'><span class='gnw-info-tip'>&#128161; ${L('点击节点查看详情','Click a node')}</span></div></div>`;" _ nl
    Set s = s _ "  var net=gnwRender('ctsub',{nodes:vnodes,edges:vedges},{layout:'circos',groupBy:'group'});" _ nl
    Set s = s _ "  if(net){card.querySelector('.gz-in').onclick=function(){net.moveTo({scale:net.getScale()*1.25});};card.querySelector('.gz-out').onclick=function(){net.moveTo({scale:net.getScale()*0.8});};card.querySelector('.gz-fit').onclick=function(){net.fit({animation:true});};}" _ nl
    Set s = s _ " }catch(e){var g=card.querySelector('.gload');if(g)g.innerHTML='&#10007; '+L('加载失败','load failed')+' '+e;}" _ nl
    Set s = s _ "}" _ nl
    Set s = s _ "function applyLang(){document.documentElement.lang=LANG==='zh'?'zh-CN':'en';var els=document.querySelectorAll('[data-i18n]');for(var i=0;i<els.length;i++){els[i].textContent=t(els[i].getAttribute('data-i18n'));}ctSub();ctTip();ctIntro();if(benchRows.length){render();loadGraph(runStartVal,benchRows[benchRows.length-1].k);}}" _ nl
    Set s = s _ "function toggleLang(){LANG=LANG==='zh'?'en':'zh';localStorage.setItem('ctlang',LANG);applyLang();}" _ nl
    Set s = s _ "window.addEventListener('DOMContentLoaded',function(){var lb=document.getElementById('langtoggle');if(lb)lb.onclick=toggleLang;applyLang();});" _ nl
    Quit s
}

/// 未构建时的说明卡 / intro card when nothing is built yet
ClassMethod RenderIntro()
{
    Write "<section class='card intro' id='ct-intro'></section>", !
}

/// 页面样式 / page styles
ClassMethod CSS() As %String
{
    Quit "*{box-sizing:border-box}body{margin:0;font-family:system-ui,-apple-system,'Segoe UI',Roboto,'PingFang SC','Microsoft YaHei',sans-serif;background:#eef2f6;color:#0f172a}"
     _ ".topbar{background:linear-gradient(90deg,#b91c1c,#ea580c);color:#fff;padding:10px 20px;display:flex;align-items:center;gap:12px;box-shadow:0 2px 10px rgba(0,0,0,.15)}"
     _ ".brand{font-size:19px;font-weight:700}.sub{color:#fee2e2;font-size:13px;flex:1}"
     _ ".rebuild{color:#fff1f2;background:#9a3412;padding:7px 13px;border-radius:8px;text-decoration:none;font-size:13px}.rebuild:hover{background:#7c2d12}"
     _ ".rebuild.danger{background:#9f1239}.rebuild.danger:hover{background:#881337}"
     _ ".card{background:#fff;border-radius:12px;padding:14px 18px;margin:12px 16px;box-shadow:0 1px 6px rgba(0,0,0,.06)}"
     _ ".card h2{margin:0 0 8px;font-size:15px}.hint{color:#94a3b8;font-size:12px;font-weight:400}"
     _ ".usecase{margin:0 0 12px;padding:8px 12px;background:#fef2f2;border-left:3px solid #b91c1c;border-radius:8px;color:#991b1b;font-size:12.5px;line-height:1.6}"
     _ ".card.warn{background:#fff7ed;border:1px solid #fed7aa}.card.tip{background:#fef2f2;border:1px solid #fecaca;color:#991b1b}"
     _ ".intro p{color:#475569;font-size:13.5px;line-height:1.8;margin:8px 0}.intro .en{color:#64748b;font-size:12.5px}"
     _ ".cfg{display:flex;flex-wrap:wrap;gap:14px;align-items:flex-end}"
     _ ".cfg label{display:flex;flex-direction:column;font-size:12px;color:#475569;gap:5px}"
     _ ".cfg input{padding:9px 11px;border:1.5px solid #cbd5e1;border-radius:9px;font-size:14px;width:130px;outline:none}.cfg input:focus{border-color:#b91c1c}"
     _ ".btn{border:none;border-radius:10px;padding:11px 20px;font-size:14px;font-weight:700;color:#fff;cursor:pointer}"
     _ ".btn.build{background:#b91c1c}.btn.build:hover{background:#991b1b}.btn.run{background:#ea580c}.btn.run:hover{background:#c2410c}"
     _ ".btn:disabled{background:#cbd5e1;cursor:not-allowed}"
     _ "table.res{width:100%;border-collapse:collapse;font-size:13.5px}"
     _ "table.res th{background:#f1f5f9;color:#334155;font-weight:600;padding:6px 8px;text-align:center;border-bottom:2px solid #e2e8f0;font-size:12px}"
     _ "table.res td{padding:6px 8px;border-bottom:1px solid #eef2f6;text-align:center;vertical-align:middle}"
     _ "table.res td.kc{font-weight:700;color:#b91c1c}table.res td.num{font-variant-numeric:tabular-nums;font-family:ui-monospace,Menlo,monospace}"
     _ ".ok{color:#15803d;font-weight:600}.bad{color:#b91c1c;font-weight:600}"
     _ ".sp{display:inline-block;border-radius:8px;padding:2px 9px;font-weight:700;font-size:12.5px}"
     _ ".sp-lo{background:#e2e8f0;color:#475569}.sp-mid{background:#fef3c7;color:#92400e}.sp-hi{background:#fee2e2;color:#b91c1c}"
     _ ".barcell{min-width:150px}.bar{height:9px;background:#f1f5f9;border-radius:5px;margin:2px 0;overflow:hidden}"
     _ ".bar .bg{display:block;height:100%;background:linear-gradient(90deg,#22c55e,#16a34a);border-radius:6px}"
     _ ".bar .bs{display:block;height:100%;background:linear-gradient(90deg,#f97316,#dc2626);border-radius:6px}"
     _ ".takeaway{color:#475569;font-size:13px;line-height:1.75;margin:14px 0 0;padding-top:12px;border-top:1px dashed #e2e8f0}"
     _ "details{border:1px solid #e2e8f0;border-radius:10px;margin:10px 0;overflow:hidden}"
     _ "summary{cursor:pointer;padding:11px 14px;font-size:13px;font-weight:600;background:#f8fafc;color:#334155}summary:hover{background:#f1f5f9}"
     _ ".exec{display:grid;grid-template-columns:1fr 1fr;gap:0}@media(max-width:820px){.exec{grid-template-columns:1fr}}"
     _ ".eng{padding:12px 14px}.eng.graph{background:#f0fdf4;border-top:1px solid #e2e8f0}.eng.sql{background:#fff7ed;border-top:1px solid #e2e8f0;border-left:1px solid #e2e8f0}"
     _ ".eh{font-size:12px;font-weight:700;margin-bottom:6px;color:#334155}"
     _ ".eng pre{margin:0;white-space:pre-wrap;word-break:break-word;font-family:ui-monospace,Menlo,monospace;font-size:12px;line-height:1.6;color:#1f2937}"
     _ ".pbar{height:16px;background:#e2e8f0;border-radius:8px;overflow:hidden;margin:8px 0}"
     _ ".pbar span{display:block;height:100%;width:0;background:linear-gradient(90deg,#f97316,#ea580c);border-radius:8px;transition:width .3s ease}"
     _ "#progcard.done .pbar span{background:linear-gradient(90deg,#22c55e,#16a34a)}"
     _ ".pmsg{font-size:13px;color:#475569;margin-top:8px;display:flex;align-items:center}"
     _ ".spin{display:inline-block;width:13px;height:13px;border:2px solid #fecaca;border-top-color:#b91c1c;border-radius:50%;animation:sp .7s linear infinite;margin-right:7px;flex:none}"
     _ "@keyframes sp{to{transform:rotate(360deg)}}"
     _ ".foot{color:#64748b;font-size:12px;text-align:center;padding:16px 22px 30px}"
     _ ".gload{padding:20px;color:#64748b;font-size:13px;display:flex;align-items:center}"
}

}
