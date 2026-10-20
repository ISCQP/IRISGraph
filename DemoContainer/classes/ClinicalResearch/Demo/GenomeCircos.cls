Include %occInclude

/// 病人级基因组精准医疗 · 三视图 Circos 圈图 · CSP 页面
/// Patient genome precision-medicine · three Circos views · CSP page
/// Author: QP
/// Version: 1.0
/// Last Modified Date: 2026/08/10
/// 
/// 访问 / Visit：/csp/healthshare/nehr/ClinicalResearch.Demo.GenomeCircos.cls
///   ?action=data     返回整张策展基因组图 JSON（无数据自动构建）/ curated genome graph JSON (auto-build if empty)
///   ?action=build    重建策展数据 / rebuild curated data
///   ?action=clear    清理数据 / clear data
/// 
/// 用例：把「基因组坐标 / 知识推理 / 用药安全」三个 Circos 用例整合进一位样例病人（P001）的
/// 完整基因组知识图谱（ClinicalResearch.Demo.GenomeCase，物化进 ^GraphData）。同一份 fetch 的数据，前端按不同
/// groupBy/过滤切换出三个 Circos 圈图视图：
///   A 基因组坐标：按染色体分弧段，基因/变异定位；跨染色体基因融合（BCR-ABL1 / EML4-ALK）为高亮弦。
///   B 知识推理：按节点类型分弧段（病人→变异→基因→通路/疾病→表型→药物），全部关系为弦，展示多跳推理。
///   C 用药安全：按基因分弧段，基因→药物 PK/PD 边按关系类别（代谢/靶点/转运/HLA风险/禁忌/耐药）着色。
Class ClinicalResearch.Demo.GenomeCircos Extends %CSP.Page
{

Parameter CONTENTTYPE = "text/html";

Parameter CHARSET = "UTF-8";

ClassMethod OnPage() As %Status
{
    Try {
        Set tAction = %request.Get("action")

        // 数据接口：返回整张策展图 JSON（无数据则自动构建）/ data API
        If tAction = "data" {
            Set %response.ContentType = "application/json"
            If '##class(ClinicalResearch.Demo.GenomeCase).HasData() { Do ##class(ClinicalResearch.Demo.GenomeCase).Setup(0) }
            Write ##class(ClinicalResearch.Demo.GenomeCase).FullJSON()
            Return $$$OK
        }
        If tAction = "clear" { Do ##class(ClinicalResearch.Demo.GenomeCase).Clear() }
        If tAction = "build" { Do ##class(ClinicalResearch.Demo.GenomeCase).Setup(0) }

        Write "<!DOCTYPE html>", !
        Write "<html lang='zh-CN'><head><meta charset='UTF-8'>", !
        Write "<meta name='viewport' content='width=device-width, initial-scale=1.0'>", !
        Write "<title>基因组精准医疗 · Circos 三视图</title>", !
        Do ##class(Graph.UI.Network).Head()
        Write "<style>", ..CSS(), ##class(Graph.UI.Network).CSS(), "</style>", !
        Write "</head><body>", !

        Set tHas = ##class(ClinicalResearch.Demo.GenomeCase).HasData()
        Set tNN = $Select(tHas: ##class(ClinicalResearch.Demo.GenomeCase).NodeCount(), 1: 0)
        Set tNE = $Select(tHas: ##class(ClinicalResearch.Demo.GenomeCase).EdgeCount(), 1: 0)

        Write "<header class='topbar'>"
        Write "<div class='brand'>&#129516; <span data-i18n='brand'></span></div>"
        Write "<div class='sub' id='gc-sub'></div>"
        Write "<button type='button' id='langtoggle' class='rebuild'>&#127760; <span data-i18n='langBtn'></span></button>"
        Write "<a class='rebuild' href='?action=build'>&#128260; <span data-i18n='rebuild'></span></a>"
        Write "<a class='rebuild danger' href='?action=clear'>&#128465; <span data-i18n='clear'></span></a>"
        Write "</header>", !

        Write "<section class='card intro'>"
        Write "<p id='gc-introA'></p>"
        Write "<p class='muted' data-i18n='introB'></p>"
        Write "</section>", !

        // 三视图切换 / three-view tabs
        Write "<div class='gc-tabs'>"
        Write "<button type='button' class='gc-tab active' data-v='A'>&#129516; <span data-i18n='tabA'></span></button>"
        Write "<button type='button' class='gc-tab' data-v='B'>&#128279; <span data-i18n='tabB'></span></button>"
        Write "<button type='button' class='gc-tab' data-v='C'>&#128138; <span data-i18n='tabC'></span></button>"
        Write "</div>", !

        // 跨视图联动条 / cross-view linkage bar
        Write "<div class='gc-xbar'>"
        Write "<button type='button' class='gc-x' id='gc-focus'>&#129516; <span data-i18n='focus'></span></button>"
        Write "<button type='button' class='gc-x ghost' id='gc-clear'>&#10005; <span data-i18n='clearhi'></span></button>"
        Write "<span class='gc-xinfo' id='gc-xinfo'></span>"
        Write "</div>", !

        Do ..RenderPanel("A")
        Do ..RenderPanel("B")
        Do ..RenderPanel("C")

        Do ..RenderScript(tHas, tNN, tNE)

        Write "</body></html>", !
        Return $$$OK
    }
    Catch tEx {
        Write "<pre>page error: ", tEx.DisplayString(), "</pre>"
        Return $$$OK
    }
}

/// 单个视图面板 / one view panel
ClassMethod RenderPanel(pView As %String)
{
    Set tId = "gc" _ pView
    Set tShow = $Select(pView = "A": "", 1: " style='display:none'")
    Write "<section class='card gc-panel'", tShow, " data-v='", pView, "'>", !
    Write "<h2 data-i18n='panel", pView, "'></h2>"
    Write "<p class='muted small' data-i18n='panel", pView, "d'></p>"
    Write "<div class='gnw'>"
    Write "<div class='gnw-bar'><button type='button' class='gz-in'>&#43;</button><button type='button' class='gz-out'>&#8722;</button><button type='button' class='gz-fit'>&#9635; <span data-i18n='fit'></span></button></div>"
    Write "<div id='", tId, "' class='gnw-net' style='height:580px'><div class='gload'><span class='spin'></span><span data-i18n='loading'></span></div></div>"
    Write "<div class='gnw-legend'></div>"
    Write "<div id='", tId, "-info' class='gnw-info'><span class='gnw-info-tip'>&#128161; <span data-i18n='clicknode'></span></span></div>"
    Write "</div>"
    Write "</section>", !
}

/// 页面脚本：一次 fetch，三视图各自 gnwRender circos；i18n 单语切换（像 ResearchChatWithHITL）。
/// Page script: fetch once, render three Circos views; single-language i18n toggle.
ClassMethod RenderScript(pHas As %Boolean, pNN As %Integer, pNE As %Integer)
{
    Write "<script>", !
    Write "var GCHAS=", +pHas, ",GCNN=", +pNN, ",GCNE=", +pNE, ";", !
    // ---- i18n ----
    Write "var LANG=localStorage.getItem('gclang');", !
    Write "if(LANG!=='zh'&&LANG!=='en'){LANG=((navigator.language||'').toLowerCase().indexOf('zh')===0)?'zh':'en';}", !
    Write "var I18N={", !
    Write "brand:{zh:'基因组精准医疗 · Circos 圈图三视图',en:'Genome Precision Medicine · Circos Tri-View'},", !
    Write "langBtn:{zh:'EN',en:'中文'},", !
    Write "rebuild:{zh:'重建',en:'Rebuild'},", !
    Write "clear:{zh:'清理',en:'Clear'},", !
    Write "ready:{zh:'策展图已就绪',en:'Graph ready'},", !
    Write "building:{zh:'首次访问将自动构建策展基因组图',en:'Building curated genome graph on first load'},", !
    Write "nodes:{zh:'节点',en:'nodes'},", !
    Write "edges:{zh:'条有向边',en:'directed edges'},", !
    Write "patientP001:{zh:'样例病人 P001',en:'Sample patient P001'},", !
    Write "introB:{zh:'Circos 最初就是为基因组学发明的——这里让它回到主场。',en:'Circos was born for genomics — this is its home turf.'},", !
    Write "tabA:{zh:'视图 A · 基因组坐标',en:'View A · Genomic coordinates'},", !
    Write "tabB:{zh:'视图 B · 知识推理',en:'View B · Knowledge reasoning'},", !
    Write "tabC:{zh:'视图 C · 用药安全',en:'View C · Medication safety'},", !
    Write "focus:{zh:'聚焦病人 P001',en:'Focus patient P001'},", !
    Write "clearhi:{zh:'清除高亮',en:'Clear'},", !
    Write "xinfoDefault:{zh:'点击任意视图中的节点，其它视图会同步高亮同一实体（跨视图联动）。',en:'Click a node in any view to sync-highlight the same entity across views.'},", !
    Write "panelA:{zh:'基因组坐标 · 按染色体分弧段',en:'Genomic coordinates · arcs by chromosome'},", !
    Write "panelAd:{zh:'跨染色体基因融合为红色高亮弦（BCR-ABL1 / EML4-ALK）。变异（●）定位到所属基因（■）与 cytoband。',en:'Cross-chromosome gene fusions shown as red highlighted chords (BCR-ABL1 / EML4-ALK). Variants (●) map to their gene (■) and cytoband.'},", !
    Write "panelB:{zh:'知识推理 · 按节点类型分弧段',en:'Knowledge reasoning · arcs by node type'},", !
    Write "panelBd:{zh:'病人→变异→基因→通路/疾病→表型→药物，全部关系为弦，一图看尽多跳推理链。',en:'Patient→Variant→Gene→Pathway/Disease→Phenotype→Drug; every relation is a chord — the full multi-hop reasoning chain at a glance.'},", !
    Write "panelC:{zh:'用药安全 · 按基因分弧段',en:'Medication safety · arcs by gene'},", !
    Write "panelCd:{zh:'基因→药物 PK/PD 边按关系类别着色（代谢/靶点/转运/HLA风险/禁忌/耐药），跨基因共享的药物形成跨扇区弦。',en:'Gene→Drug PK/PD edges colored by category (metabolism/target/transport/HLA-risk/contraindication/resistance); drugs shared across genes form cross-sector chords.'},", !
    Write "fit:{zh:'适应',en:'Fit'},", !
    Write "loading:{zh:'加载图数据中…',en:'Loading graph…'},", !
    Write "clicknode:{zh:'点击节点查看详情',en:'Click a node for details'},", !
    Write "selected:{zh:'选中',en:'Selected'},", !
    Write "fusion:{zh:'基因融合（跨染色体弦）',en:'Gene fusion (cross-chr chord)'},", !
    Write "focusA:{zh:'聚焦病人 P001 可行动链：携带变异 ',en:'Patient P001 actionable chain · variants '},", !
    Write "focusB:{zh:' · 相关基因 ',en:' · genes '},", !
    Write "focusC:{zh:' · 受影响药物 ',en:' · affected drugs '},", !
    Write "focusD:{zh:'（三视图已同步高亮）',en:' (synced across views)'}", !
    Write "};", !
    Write "function t(k){var e=I18N[k];return e?(e[LANG]||e.en):k;}", !
    // ---- 类型 / 关系类别 多语标签 / lang-aware type & relation labels ----
    Write "var GCT={PT:{zh:'病人',en:'Patient'},V:{zh:'变异',en:'Variant'},G:{zh:'基因',en:'Gene'},PW:{zh:'通路',en:'Pathway'},D:{zh:'疾病',en:'Disease'},HP:{zh:'表型',en:'Phenotype'},RX:{zh:'药物',en:'Drug'}};", !
    Write "function gct(k){return (GCT[k]&&GCT[k][LANG])||k;}", !
    Write "var GCC={PT:'#0f172a',V:'#dc2626',G:'#2563eb',PW:'#0891b2',D:'#7c3aed',HP:'#db2777',RX:'#16a34a'};", !
    Write "var GCRC=[{kw:'target',c:'#16a34a',t:{zh:'靶点 Target/PD',en:'Target / PD'}},{kw:'transports',c:'#0891b2',t:{zh:'转运',en:'Transport'}},{kw:'HLA-risk',c:'#b91c1c',t:{zh:'HLA风险',en:'HLA-risk'}},{kw:'contraindicated',c:'#7f1d1d',t:{zh:'禁忌',en:'Contraindicated'}},{kw:'resistance',c:'#ea580c',t:{zh:'耐药',en:'Resistance'}},{kw:'activates',c:'#7c3aed',t:{zh:'代谢激活',en:'Activation'}},{kw:'metabolizes',c:'#2563eb',t:{zh:'代谢 Metabolism/PK',en:'Metabolism / PK'}}];", !
    // ---- 逻辑（纯 ASCII）/ logic (pure ASCII) ----
    Write "var DATA=null,RENDERED={},NETS={};", !
    Write "var NIDS={},LASTSEL=[];", !
    Write "function gcPal(){return ['#2563eb','#dc2626','#16a34a','#7c3aed','#ea580c','#0891b2','#db2777','#ca8a04','#0d9488','#9333ea','#65a30d','#e11d48','#0284c7','#a16207','#4f46e5','#be123c','#047857','#7e22ce','#b45309','#1d4ed8','#15803d','#c026d3','#0369a1','#334155'];}", !
    Write "function gcColor(key,map,used){if(map[key])return map[key];var pal=gcPal();map[key]=pal[used.n%pal.length];used.n++;return map[key];}", !
    Write "async function gcLoad(){if(DATA)return DATA;var r=await fetch('?action=data');DATA=await r.json();DATA.byId={};DATA.nodes.forEach(function(n){DATA.byId[n.id]=n;});return DATA;}", !
    Write "function gcRelCat(r){for(var i=0;i<GCRC.length;i++){if(r.indexOf(GCRC[i].kw)>=0)return GCRC[i];}return {kw:'other',c:'#94a3b8',t:{zh:'其它',en:'other'}};}", !
    Write "function gcWire(net,el){if(!net||!el)return;var b=el.querySelector('.gz-in'),o=el.querySelector('.gz-out'),f=el.querySelector('.gz-fit');if(b)b.onclick=function(){net.moveTo({scale:net.getScale()*1.25});};if(o)o.onclick=function(){net.moveTo({scale:net.getScale()*0.8});};if(f)f.onclick=function(){net.fit({animation:true});};}", !
    Write "function gcLegend(items){var h='';items.forEach(function(x){h+=`<span><i class='gnw-dot' style='background:${x.c}'></i>${x.t}</span>`;});return h;}", !
    Write "function gcMount(divId,nodes,edges,leg){var host=document.getElementById(divId);if(!host)return;host.innerHTML='';var el=host.closest('.gc-panel');var lg=el?el.querySelector('.gnw-legend'):null;if(lg)lg.innerHTML=gcLegend(leg);var nid={};nodes.forEach(function(n){nid[n.id]=1;});NIDS[divId]=nid;var net=gnwRender(divId,{nodes:nodes,edges:edges},{layout:'circos',groupBy:'group',nodeSize:7,nodeFont:10,band:12,bandGap:12});NETS[divId]=net;gcWire(net,el);if(net)net.on('click',function(p){if(p.nodes&&p.nodes.length)gcSelect(p.nodes[0]);});return net;}", !
    // 跨视图联动：把一组节点 id 同步高亮到所有已渲染视图 / cross-view highlight
    Write "function gcApply(ids){LASTSEL=ids.slice();Object.keys(NETS).forEach(function(k){var net=NETS[k],nid=NIDS[k]||{};if(!net)return;var f=ids.filter(function(id){return nid[id];});try{net.selectNodes(f);}catch(e){}});}", !
    Write "function gcSelect(id){gcApply([id]);var n=DATA.byId[id];var el=document.getElementById('gc-xinfo');if(el&&n)el.innerHTML=t('selected')+' '+gct(n.ty)+'\uff1a<b>'+n.name+'</b>'+(n.note?(' \u00b7 '+n.note):'')+(n.eff?(' \u00b7 '+n.eff):'');}", !
    Write "function gcPatientSet(){var pid=DATA.patient,set={},vars={},genes={},nd=0;set[pid]=1;DATA.edges.forEach(function(e){if(e.s===pid){vars[e.t]=1;set[e.t]=1;}});DATA.edges.forEach(function(e){if(vars[e.s]&&e.r.indexOf('located_in')>=0){genes[e.t]=1;set[e.t]=1;}});DATA.edges.forEach(function(e){if(genes[e.s]){var t=DATA.byId[e.t];if(t&&(t.ty==='RX'||t.ty==='D'||t.ty==='PW')){set[e.t]=1;if(t.ty==='RX')nd++;}}});return {ids:Object.keys(set).map(Number),nv:Object.keys(vars).length,ng:Object.keys(genes).length,nd:nd};}", !
    Write "function gcFocus(){var a=gcPatientSet();gcApply(a.ids);var el=document.getElementById('gc-xinfo');if(el)el.innerHTML=t('focusA')+a.nv+t('focusB')+a.ng+t('focusC')+a.nd+t('focusD');}", !
    Write "function gcClearHi(){LASTSEL=[];Object.keys(NETS).forEach(function(k){if(NETS[k])try{NETS[k].unselectAll();}catch(e){}});var el=document.getElementById('gc-xinfo');if(el)el.innerHTML=t('xinfoDefault');}", !
    // View A：染色体分弧段，基因(方)+变异(圆)，融合边为红色高亮弦
    Write "function gcViewA(){var cmap={},used={n:0},keep={};var genes=DATA.nodes.filter(function(n){return n.ty==='G';});var vars=DATA.nodes.filter(function(n){return n.ty==='V';});var arr=genes.concat(vars);var vnodes=arr.map(function(n){var chr=String(n.chr||'?');var col=gcColor(chr,cmap,used);keep[n.id]=1;var isV=n.ty==='V';return {id:n.id,group:'chr'+chr,label:n.name,title:(isV?gct('V'):gct('G'))+' '+n.name+' · chr'+chr+(n.locus?(' '+n.locus):'')+(n.eff?(' · '+n.eff):''),color:{background:col,border:isV?'#0f172a':col},font:{color:'#334155'},shape:isV?'dot':'square',size:isV?7:11,borderWidth:isV?1:2};});var vedges=DATA.edges.filter(function(e){return keep[e.s]&&keep[e.t];}).map(function(e){var loc=e.r.indexOf('located_in')>=0;return {from:e.s,to:e.t,label:loc?'':e.r,title:e.r,color:loc?{color:'#cbd5e1'}:{color:'#dc2626',highlight:'#dc2626'},width:loc?1:3,dashes:loc?true:false};});var leg=Object.keys(cmap).map(function(k){return {c:cmap[k],t:'chr'+k};});leg.push({c:'#dc2626',t:t('fusion')});gcMount('gcA',vnodes,vedges,leg);}", !
    // View B：类型分弧段，全部关系为弦
    Write "function gcViewB(){var order=['PT','V','G','PW','D','HP','RX'];var vnodes=DATA.nodes.map(function(n){return {id:n.id,group:n.ty,label:n.name,title:gct(n.ty)+' '+n.name+(n.note?(' · '+n.note):''),color:{background:GCC[n.ty],border:GCC[n.ty]},font:{color:'#334155'}};});vnodes.sort(function(a,b){return order.indexOf(DATA.byId[a.id].ty)-order.indexOf(DATA.byId[b.id].ty);});var vedges=DATA.edges.map(function(e){return {from:e.s,to:e.t,title:e.r,color:{color:'#cbd5e1'}};});var leg=order.map(function(ty){return {c:GCC[ty],t:gct(ty)};});gcMount('gcB',vnodes,vedges,leg);}", !
    // View C：基因分弧段，基因→药物 PK/PD 边按关系类别着色
    Write "function gcViewC(){var geneHasDrug={},drugGene={},cmap={},used={n:0};DATA.edges.forEach(function(e){var s=DATA.byId[e.s],t=DATA.byId[e.t];if(s&&t&&s.ty==='G'&&t.ty==='RX'){if(drugGene[t.id]==null)drugGene[t.id]=s.name;geneHasDrug[s.id]=1;}});var vnodes=[];DATA.nodes.forEach(function(n){if(n.ty==='G'&&geneHasDrug[n.id]){var col=gcColor(n.name,cmap,used);vnodes.push({id:n.id,group:n.name,label:n.name,title:gct('G')+' '+n.name,color:{background:col,border:col},font:{color:'#334155'},shape:'square',size:12});}});DATA.nodes.forEach(function(n){if(n.ty==='RX'&&drugGene[n.id]!=null){vnodes.push({id:n.id,group:drugGene[n.id],label:n.name,title:gct('RX')+' '+n.name,color:{background:'#e2e8f0',border:'#94a3b8'},font:{color:'#334155'},shape:'dot',size:7});}});var vedges=DATA.edges.filter(function(e){var s=DATA.byId[e.s],t=DATA.byId[e.t];return s&&t&&s.ty==='G'&&t.ty==='RX';}).map(function(e){var c=gcRelCat(e.r);return {from:e.s,to:e.t,title:e.r,color:{color:c.c,highlight:c.c},width:2};});gcMount('gcC',vnodes,vedges,GCRC.map(function(x){return {c:x.c,t:x.t[LANG]};}));}", !
    Write "async function gcShow(view){document.querySelectorAll('.gc-tab').forEach(function(b){b.classList.toggle('active',b.dataset.v===view);});document.querySelectorAll('.gc-panel').forEach(function(p){p.style.display=(p.dataset.v===view)?'':'none';});await gcLoad();if(!RENDERED[view]){RENDERED[view]=1;if(view==='A')gcViewA();else if(view==='B')gcViewB();else gcViewC();}var divId='gc'+view,net=NETS[divId];if(net){if(LASTSEL.length){var nid=NIDS[divId]||{};var f=LASTSEL.filter(function(id){return nid[id];});try{net.selectNodes(f);}catch(e){}}setTimeout(function(){net.fit({animation:false});},80);}}", !
    // i18n 应用 / apply language to DOM + dynamic strings + re-render current view
    Write "function gcSub(){var el=document.getElementById('gc-sub');if(!el)return;el.textContent=GCHAS?(t('ready')+' · '+GCNN+' '+t('nodes')+' / '+GCNE+' '+t('edges')+' · '+t('patientP001')):t('building');}", !
    Write "function gcIntro(){var el=document.getElementById('gc-introA');if(!el)return;el.innerHTML=(LANG==='zh')?('同一份病人基因组知识图谱（<b>'+GCNN+' 个节点</b>／<b>'+GCNE+' 条有向边</b>，物化进 <code>^GraphData</code>），前端一次 fetch，按不同 <code>groupBy</code>／过滤切换出三个 <b>Circos 圈图</b>视图。'):('One patient-genome knowledge graph (<b>'+GCNN+' nodes</b> / <b>'+GCNE+' directed edges</b>, materialized into <code>^GraphData</code>), fetched once and rendered as three <b>Circos</b> views by switching <code>groupBy</code> / filters.');}", !
    Write "function applyLang(){document.documentElement.lang=(LANG==='zh')?'zh-CN':'en';var els=document.querySelectorAll('[data-i18n]');for(var i=0;i<els.length;i++){els[i].textContent=t(els[i].getAttribute('data-i18n'));}gcSub();gcIntro();var xi=document.getElementById('gc-xinfo');if(xi&&!LASTSEL.length)xi.innerHTML=t('xinfoDefault');if(DATA){RENDERED={};NETS={};NIDS={};var a=document.querySelector('.gc-tab.active');gcShow(a?a.dataset.v:'A');}}", !
    Write "function toggleLang(){LANG=(LANG==='zh')?'en':'zh';localStorage.setItem('gclang',LANG);applyLang();}", !
    Write "window.addEventListener('DOMContentLoaded',function(){document.querySelectorAll('.gc-tab').forEach(function(b){b.onclick=function(){gcShow(b.dataset.v);};});var fb=document.getElementById('gc-focus');if(fb)fb.onclick=function(){gcLoad().then(gcFocus);};var cb=document.getElementById('gc-clear');if(cb)cb.onclick=gcClearHi;var lb=document.getElementById('langtoggle');if(lb)lb.onclick=toggleLang;applyLang();gcShow('A');});", !
    Write "</script>", !
}

/// 页面样式 / page CSS
ClassMethod CSS() As %String
{
    Set s = ""
    Set s = s _ "*{box-sizing:border-box}body{margin:0;font-family:-apple-system,'Segoe UI',Roboto,'PingFang SC','Microsoft YaHei',sans-serif;background:#f1f5f9;color:#0f172a}"
    Set s = s _ ".topbar{display:flex;align-items:center;gap:14px;flex-wrap:wrap;padding:14px 22px;background:linear-gradient(135deg,#0f172a,#1e3a8a);color:#fff}"
    Set s = s _ ".topbar .brand{font-size:18px;font-weight:700}.topbar .sub{font-size:13px;opacity:.85;flex:1 1 260px}"
    Set s = s _ ".topbar .rebuild{color:#fff;text-decoration:none;font-size:13px;border:1px solid rgba(255,255,255,.4);border-radius:8px;padding:5px 12px}"
    Set s = s _ ".topbar .rebuild:hover{background:rgba(255,255,255,.15)}.topbar .rebuild.danger{border-color:#fca5a5;color:#fecaca}"
    Set s = s _ ".card{background:#fff;border:1px solid #e2e8f0;border-radius:14px;padding:18px 20px;margin:16px 22px;box-shadow:0 1px 3px rgba(15,23,42,.06)}"
    Set s = s _ ".card h2{margin:0 0 6px;font-size:16px}.card p{margin:6px 0;line-height:1.6;font-size:14px}"
    Set s = s _ ".muted{color:#64748b}.small{font-size:12.5px}code{background:#f1f5f9;border-radius:5px;padding:1px 6px;font-size:12.5px}"
    Set s = s _ ".intro{border-left:4px solid #2563eb}"
    Set s = s _ ".gc-tabs{display:flex;gap:8px;flex-wrap:wrap;margin:16px 22px 0}"
    Set s = s _ ".gc-tab{cursor:pointer;border:1px solid #cbd5e1;background:#fff;color:#334155;border-radius:10px 10px 0 0;padding:9px 15px;font-size:13.5px;font-weight:600}"
    Set s = s _ ".gc-tab:hover{background:#f8fafc}.gc-tab.active{background:linear-gradient(135deg,#1e3a8a,#2563eb);color:#fff;border-color:#1e3a8a}"
    Set s = s _ ".gc-panel{margin-top:0;border-top-left-radius:0}"
    Set s = s _ ".gc-xbar{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin:12px 22px 0;padding:10px 14px;background:#fff;border:1px solid #e2e8f0;border-radius:12px}"
    Set s = s _ ".gc-x{cursor:pointer;border:1px solid #1e3a8a;background:linear-gradient(135deg,#1e3a8a,#2563eb);color:#fff;border-radius:9px;padding:7px 13px;font-size:13px;font-weight:600}"
    Set s = s _ ".gc-x:hover{filter:brightness(1.08)}.gc-x.ghost{background:#fff;color:#334155;border-color:#cbd5e1}.gc-x.ghost:hover{background:#f8fafc}"
    Set s = s _ ".gc-xinfo{flex:1 1 260px;font-size:13px;color:#475569;line-height:1.5}"
    Set s = s _ ".gload{display:flex;align-items:center;gap:10px;justify-content:center;height:100%;color:#64748b;font-size:14px}"
    Set s = s _ ".spin{width:16px;height:16px;border:3px solid #cbd5e1;border-top-color:#2563eb;border-radius:50%;animation:gcsp .8s linear infinite}"
    Set s = s _ "@keyframes gcsp{to{transform:rotate(360deg)}}"
    Quit s
}

}
