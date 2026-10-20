Include %occInclude

/// 知识图谱可视化 · 标准页面组件（基于 vis-network）
/// Knowledge graph visualization - standard page component (based on vis-network)
///
/// 目标：把“交互式知识图谱”封装成可复用的页面组件，任何 CSP / HTML 页面
/// Goal: encapsulate an "interactive knowledge graph" into a reusable page component, so any CSP / HTML page
/// 只需三步即可嵌入一张可交互的属性图，无需重复编写 vis-network 初始化代码。
/// can embed an interactive property graph in just three steps, without rewriting vis-network initialization code.
///
/// == 用法（最简）==
/// == Usage (minimal) ==
///   1) 在 &lt;head&gt; 中引入依赖与辅助脚本：
///   1) In &lt;head&gt;, include dependencies and helper scripts:
///        Do ##class(Graph.UI.Network).Head()
///   2) 在样式表中并入组件 CSS：
///   2) Merge the component CSS into the stylesheet:
///        Write "&lt;style&gt;", ..PageCSS(), ##class(Graph.UI.Network).CSS(), "&lt;/style&gt;"
///   3) 在页面主体需要出现图的位置渲染组件：
///   3) Render the component where the graph should appear in the page body:
///        Set json = ##class(Graph.UI.Network).BuildFromGlobal("Research.", "Research.Demo")
///        Do ##class(Graph.UI.Network).Widget("net", json)
///
/// Widget 会自动输出：缩放工具条 + 画布容器 + 图例 + 初始化脚本。
/// Widget automatically outputs: zoom toolbar + canvas container + legend + initialization script.
/// 若未显式提供 groups 配色，会依据图中出现的分组自动分配一套均匀色板并生成图例。
/// If groups colors are not explicitly provided, it auto-assigns an even color palette based on the groups present in the graph and generates a legend.
///
/// == 数据格式 ==
/// == Data format ==
/// 图数据是一段 JSON 字符串：{"nodes":[{id,label,group,title},...],"edges":[{from,to,label},...]}
/// Graph data is a JSON string: {"nodes":[{id,label,group,title},...],"edges":[{from,to,label},...]}
///   - id     节点唯一标识（组件内部约定为 "&lt;Id&gt;~&lt;ClassName&gt;"）
///   - id     unique node identifier (internally conventioned as "&lt;Id&gt;~&lt;ClassName&gt;")
///   - label  节点显示文本
///   - label  node display text
///   - group  分组名（决定配色 / 图例，一般取短类名）
///   - group  group name (determines color / legend, usually the short class name)
///   - title  鼠标悬停提示（可选）
///   - title  mouse hover tooltip (optional)
/// 可用 BuildFromGlobal() 从图全局自动生成，或由调用方自行拼装。
/// Can be auto-generated from the graph global via BuildFromGlobal(), or assembled by the caller.
///
/// == 数据提供者（provider）==
/// == Data provider ==
/// BuildFromGlobal 需要一个 provider 类名，该类须实现：
/// BuildFromGlobal needs a provider class name; that class must implement:
///   ClassMethod Label(pOID As %List) As %String        // 必需：节点显示文本
///   ClassMethod Label(pOID As %List) As %String        // Required: node display text
///   ClassMethod NodeDesc(pOID As %List) As %String     // 可选：悬停提示
///   ClassMethod NodeDesc(pOID As %List) As %String     // Optional: hover tooltip
///
/// == 布局 Layouts（通过 pOpts("layout") 切换）==
/// == Layouts (switch via pOpts("layout")) ==
/// 组件内置一个标准渲染器 gnwRender（Head() 注入），一份图数据可用四种布局呈现：
/// The component ships a standard renderer gnwRender (injected by Head()); one graph, four layouts:
///   - "force"        力导向关系图（默认）。适合一般图关系。 Force-directed graph (default). General relations.
///   - "hierarchical" 分层树。需节点带 level；pOpts("direction")=UD/DU/LR/RL。 Layered tree; nodes need level.
///   - "radial"       同心圆。level 0 居中，第 L 代在第 L 圈；角度按子树叶子数分配；
///                    pOpts("ringLabelPrefix"/"ringLabelSuffix") 生成圈标注。 Concentric rings by level.
///   - "circos"       Circos 圈图。节点按 pOpts("groupBy")（默认 group）分组排成外圈弧段，
///                    彩色外环带 + 分组标签，边为向心弧弦。 Circos: nodes in arc sectors by group, chord edges.
///
/// == 节点/边可选字段（直接透传 vis-network）==
/// == Optional node/edge fields (passed straight to vis-network) ==
/// 节点：color / level（tree、radial、circos 分组用）/ size / shape / borderWidth / font。
/// Node: color / level (used by tree, radial, circos grouping) / size / shape / borderWidth / font.
/// 边：label / title / color / dashes。 Edge: label / title / color / dashes.
///
/// == 客户端异步渲染 Client-side async rendering ==
/// AJAX 页面（先 fetch 图数据再渲染）可直接调用 Head() 暴露的全局函数：
/// AJAX pages (fetch then render) can call the global exposed by Head() directly:
///   var net = gnwRender('divId', {nodes:[...], edges:[...]}, {layout:'circos', groupBy:'group'});
/// 容器需含 &lt;div id='divId'&gt; 与可选的 &lt;div id='divId-info'&gt; 详情面板；net 可接工具条按钮。
/// The container needs &lt;div id='divId'&gt; and an optional &lt;div id='divId-info'&gt; details panel.
///
/// Author: QP
/// Version: 2.0
/// Last Modified Date: 2026/08/10
Class Graph.UI.Network Extends %RegisteredObject
{

/// vis-network CDN 地址（如需私有部署可覆盖此参数）
/// vis-network CDN URL (override this parameter for private deployment)
Parameter LIBURL = "https://unpkg.com/vis-network/standalone/umd/vis-network.min.js";

/// 输出到 &lt;head&gt; 的依赖脚本与共享辅助函数（每个页面调用一次）
/// Dependency scripts and shared helper functions output to &lt;head&gt; (called once per page)
ClassMethod Head()
{
    Try {
        Write "<script src='", ..#LIBURL, "'></script>", !
        Write "<script>", !
        Write "window.__gnw=window.__gnw||{};", !
        Write "function gnwZoom(id,f){var n=window.__gnw[id];if(n)n.moveTo({scale:n.getScale()*f});}", !
        Write "function gnwFit(id){var n=window.__gnw[id];if(n)n.fit({animation:true});}", !
        // 标准渲染器：一个函数支持四种布局（force 力导 / hierarchical 树 / radial 同心圆 / circos 圈图）
        // Standard renderer: one function, four layouts (force / hierarchical tree / radial concentric / circos)
        Write "function gnwRender(divId,g,opts){try{opts=opts||{};var el=document.getElementById(divId);if(!el||!window.vis)return null;var nodes=(g&&g.nodes)||[],edges=(g&&g.edges)||[];var layout=opts.layout||'force';var directed=opts.directed!==false;var edgeHi=opts.edgeHighlight||'#6366f1';var o={groups:opts.groups||{},nodes:{shape:'dot',size:opts.nodeSize||16,borderWidth:2,font:{size:opts.nodeFont||13}},edges:{color:{color:'#cbd5e1',highlight:edgeHi},font:{size:10,color:'#64748b',strokeWidth:3,strokeColor:'#fff',align:'middle'}},interaction:{hover:true,tooltipDelay:120}};if(directed)o.edges.arrows={to:{enabled:true,scaleFactor:0.6}};var ri=null;if(layout==='hierarchical'){o.layout={hierarchical:{enabled:true,direction:opts.direction||'UD',sortMethod:'directed',shakeTowards:'roots',levelSeparation:opts.levelSeparation||120,nodeSpacing:opts.nodeSpacing||60,treeSpacing:opts.treeSpacing||100}};o.physics=false;var hz=(opts.direction==='LR'||opts.direction==='RL');o.edges.smooth={type:'cubicBezier',forceDirection:hz?'horizontal':'vertical',roundness:0.5};}else if(layout==='radial'){ri=gnwRadial(nodes,edges,opts);o.physics=false;o.layout={hierarchical:false};o.edges.smooth={type:'continuous',roundness:0.15};}else if(layout==='circos'){ri=gnwCircos(nodes,edges,opts);o.physics=false;o.layout={hierarchical:false};o.edges.smooth={type:'curvedCW',roundness:(opts.chord!==undefined?opts.chord:0.45)};}else{o.physics=(opts.physics===false)?false:{stabilization:{iterations:200},barnesHut:{gravitationalConstant:-9000,springLength:150,springConstant:0.04}};o.edges.smooth={type:'dynamic'};}var nodesDS=new vis.DataSet(nodes);var net=new vis.Network(el,{nodes:nodesDS,edges:new vis.DataSet(edges)},o);window.__gnw=window.__gnw||{};window.__gnw[divId]=net;if(ri&&ri.draw){net.on('beforeDrawing',ri.draw);}var ib=document.getElementById(divId+'-info');net.on('click',function(p){if(!ib)return;if(p.nodes.length){var nd=nodesDS.get(p.nodes[0]);var t=nd.title?String(nd.title):'';ib.innerHTML='<b>'+(nd.label||'')+'</b>'+(nd.group?' <span class=""gnw-info-g"">'+nd.group+'</span>':'')+(t?'<div class=""gnw-info-d"">'+t.replace(/\n/g,'<br>')+'</div>':'');}else{ib.innerHTML='<span class=""gnw-info-tip"">Click a node</span>';}});return net;}catch(e){return null;}}", !
        Write "function gnwRadial(nodes,edges,opts){var maxLvl=0;nodes.forEach(function(n){var L=n.level||0;if(L>maxLvl)maxLvl=L;});var nlvl={},byLvl={},ringColor={};nodes.forEach(function(n){var L=n.level||0;nlvl[n.id]=L;(byLvl[L]=byLvl[L]||[]).push(n.id);if(ringColor[L]===undefined){var c=(n.color&&(n.color.background||n.color))||null;if(c)ringColor[L]=c;}});var spacing=opts.nodeSpacing||22,minGap=opts.ringGap||130,radArr=[0];for(var L=1;L<=maxLvl;L++){var cnt=(byLvl[L]||[]).length;var need=cnt*spacing/(2*Math.PI);radArr[L]=Math.max((radArr[L-1]||0)+minGap,need);}var childMap={};edges.forEach(function(e){(childMap[e.from]=childMap[e.from]||[]).push(e.to);});var leaf={};function lc(id){var ch=childMap[id];if(!ch||!ch.length){leaf[id]=1;return 1;}var t=0;for(var i=0;i<ch.length;i++)t+=lc(ch[i]);leaf[id]=t;return t;}var roots=(byLvl[0]||[]),tot=0;roots.forEach(function(r){tot+=lc(r);});var pos={};function place(id,a0,a1){var L=nlvl[id]||0,R=radArr[L]||0,mid=(a0+a1)/2;pos[id]={x:R*Math.cos(mid),y:R*Math.sin(mid)};var ch=childMap[id];if(!ch||!ch.length)return;var span=a1-a0,acc=a0;for(var i=0;i<ch.length;i++){var w=leaf[ch[i]]/leaf[id];var na=acc+span*w;place(ch[i],acc,na);acc=na;}}var a=-Math.PI;roots.forEach(function(r){var w=tot?leaf[r]/tot:1/roots.length;var na=a+2*Math.PI*w;place(r,a,na);a=na;});nodes.forEach(function(n){var p=pos[n.id]||{x:0,y:0};n.x=p.x;n.y=p.y;n.fixed={x:true,y:true};n.physics=false;});var rl=opts.ringLabel;if(opts.rings===false)return{draw:null};return{draw:function(ctx){ctx.save();for(var L=1;L<=maxLvl;L++){var R=radArr[L]||0;if(R<=0)continue;var c=ringColor[L]||'#94a3b8';ctx.beginPath();ctx.arc(0,0,R,0,2*Math.PI);ctx.strokeStyle=c;ctx.globalAlpha=0.18;ctx.lineWidth=2;ctx.stroke();if(rl){ctx.globalAlpha=0.7;ctx.fillStyle=c;ctx.font='13px sans-serif';ctx.textAlign='center';ctx.fillText(rl(L),0,-R-6);}}ctx.restore();}};}", !
        Write "function gnwCircos(nodes,edges,opts){var key=opts.groupBy||'group';var order=[],byG={},colOf={};nodes.forEach(function(n){var g=(n[key]!==undefined&&n[key]!=='')?n[key]:(n.level!==undefined?('L'+n.level):'all');if(!byG[g]){byG[g]=[];order.push(g);}byG[g].push(n.id);if(colOf[g]===undefined){colOf[g]=(n.color&&(n.color.background||n.color))||null;}});var N=nodes.length||1;var spacing=opts.nodeSpacing||26;var R=Math.max(opts.radius||0,N*spacing/(2*Math.PI));var gap=(opts.groupGap!==undefined)?opts.groupGap:0.06;var G=order.length;var usable=2*Math.PI-gap*G;if(usable<0.5){usable=2*Math.PI*0.9;gap=(2*Math.PI*0.1)/(G||1);}var pal=['#4f46e5','#0891b2','#16a34a','#ca8a04','#dc2626','#7c3aed','#db2777','#ea580c'];var pos={},segs=[],ang=-Math.PI/2;order.forEach(function(g,gi){var ids=byG[g];var span=usable*(ids.length/N);var a0=ang,a1=ang+span;var col=colOf[g]||pal[gi%pal.length];for(var j=0;j<ids.length;j++){var aa=a0+span*((j+0.5)/ids.length);pos[ids[j]]={x:R*Math.cos(aa),y:R*Math.sin(aa)};}segs.push({a0:a0,a1:a1,c:col,name:String(g)});ang=a1+gap;});nodes.forEach(function(n){var p=pos[n.id]||{x:0,y:0};n.x=p.x;n.y=p.y;n.fixed={x:true,y:true};n.physics=false;});var band=opts.band||16;var bandGap=(opts.bandGap!==undefined)?opts.bandGap:30;var bandR=R+bandGap+band;return{draw:function(ctx){ctx.save();for(var i=0;i<segs.length;i++){var s=segs[i];ctx.beginPath();ctx.arc(0,0,bandR,s.a0,s.a1);ctx.strokeStyle=s.c;ctx.globalAlpha=0.85;ctx.lineWidth=band;ctx.stroke();if(opts.groupLabels!==false){var mid=(s.a0+s.a1)/2,lr=bandR+band/2+12;ctx.globalAlpha=0.95;ctx.fillStyle=s.c;ctx.font='12px sans-serif';ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillText(s.name,lr*Math.cos(mid),lr*Math.sin(mid));}}ctx.restore();}};}", !
        Write "</script>", !
    }
    Catch ex {}
}

/// 渲染一张完整的交互式图谱组件
/// Render a complete interactive graph component
///   pDivId    : 画布 DOM id（同一页面多张图需各自唯一）
///   pDivId    : canvas DOM id (must be unique per graph on the same page)
///   pGraphJSON: {"nodes":[...],"edges":[...]} 图数据 JSON
///   pGraphJSON: {"nodes":[...],"edges":[...]} graph data JSON
///   pOpts     : 可选，多维数组配置：
///   pOpts     : optional, multidimensional array configuration:
///        pOpts("height")        画布高度，默认 "520px"
///        pOpts("height")        canvas height, default "520px"
///        pOpts("toolbar")       1/0 是否显示缩放工具条，默认 1
///        pOpts("toolbar")       1/0 whether to show the zoom toolbar, default 1
///        pOpts("legend")        1/0 是否显示图例，默认 1
///        pOpts("legend")        1/0 whether to show the legend, default 1
///        pOpts("physics")       1/0 是否启用力导引物理布局，默认 1
///        pOpts("physics")       1/0 whether to enable force-directed physics layout, default 1
///        pOpts("edgeHighlight") 选中边高亮色，默认 "#6366f1"
///        pOpts("edgeHighlight") highlight color of selected edges, default "#6366f1"
///        pOpts("groups")        分组配色 JSON；缺省则按图中分组自动配色
///        pOpts("groups")        group color JSON; when omitted, colors are auto-assigned by the groups in the graph
///        pOpts("layout")        布局：force(默认)/hierarchical/radial/circos
///        pOpts("layout")        layout: force(default)/hierarchical/radial/circos
///        pOpts("direction")     hierarchical 方向 UD/DU/LR/RL
///        pOpts("direction")     hierarchical direction UD/DU/LR/RL
///        pOpts("groupBy")       circos 分组字段名，默认 "group"
///        pOpts("groupBy")       circos grouping field name, default "group"
///        pOpts("ringLabelPrefix"/"ringLabelSuffix")  radial 圈标注前后缀，如 "第"/"代"
///        pOpts("ringLabelPrefix"/"ringLabelSuffix")  radial ring-label prefix/suffix, e.g. "gen "/"" 
ClassMethod Widget(pDivId As %String, pGraphJSON As %String, ByRef pOpts)
{
    Try {
        Set tHeight = $Get(pOpts("height"), "520px")
        Set tToolbar = $Get(pOpts("toolbar"), 1)
        Set tLegend = $Get(pOpts("legend"), 1)
        Set tPhysics = $Get(pOpts("physics"), 1)
        Set tHi = $Get(pOpts("edgeHighlight"), "#6366f1")
        Set tGroups = $Get(pOpts("groups"), "")

        Kill tLeg
        If tGroups = "" {
            Set tGroups = ..AutoGroups(pGraphJSON, .tLeg)
        } ElseIf tLegend {
            Do ..LegendFromGroups(tGroups, .tLeg)
        }

        Write "<div class='gnw'>", !
        If tToolbar {
            Write "<div class='gnw-bar'>"
            Write "<button type='button' onclick=""gnwZoom('", pDivId, "',1.25)"">&#43;</button>"
            Write "<button type='button' onclick=""gnwZoom('", pDivId, "',0.8)"">&#8722;</button>"
            Write "<button type='button' onclick=""gnwFit('", pDivId, "')"">&#9635; 适应</button>"
            Write "</div>", !
        }
        Write "<div id='", pDivId, "' class='gnw-net' style='height:", tHeight, "'></div>", !
        If tLegend, $Data(tLeg) {
            Write "<div class='gnw-legend'>"
            Set tK = ""
            For {
                Set tK = $Order(tLeg(tK))
                Quit:tK=""
                Write "<span><i class='gnw-dot' style='background:", $ListGet(tLeg(tK), 1), "'></i>", ..esc($ListGet(tLeg(tK), 2)), "</span>"
            }
            Write "</div>", !
        }
        Write "<div id='", pDivId, "-info' class='gnw-info'><span class='gnw-info-tip'>&#128161; Click a node to see its details</span></div>", !
        Write "</div>", !

        // 初始化脚本：委托给标准渲染器 gnwRender（布局可切换）
        // Init script: delegate to the standard renderer gnwRender (switchable layout)
        Set tLayout = $Get(pOpts("layout"), "force")
        Set tPhysJS = $Select(tPhysics: "true", 1: "false")
        Set tExtra = ""
        If $Get(pOpts("direction")) '= "" { Set tExtra = tExtra _ ",direction:'" _ pOpts("direction") _ "'" }
        If $Get(pOpts("groupBy")) '= "" { Set tExtra = tExtra _ ",groupBy:'" _ pOpts("groupBy") _ "'" }
        If ($Get(pOpts("ringLabelPrefix")) '= "") || ($Get(pOpts("ringLabelSuffix")) '= "") {
            Set tExtra = tExtra _ ",ringLabel:function(L){return '" _ $Get(pOpts("ringLabelPrefix")) _ "'+L+'" _ $Get(pOpts("ringLabelSuffix")) _ "';}"
        }
        Write "<script>gnwRender('", pDivId, "',", pGraphJSON, ",{layout:'", tLayout, "',physics:", tPhysJS, ",edgeHighlight:'", tHi, "',groups:", $Select(tGroups = "": "{}", 1: tGroups), tExtra, "});</script>", !
    }
    Catch ex {}
}

/// 依据图数据里出现的分组，自动生成一套均匀色板（groups JSON），并回填图例
/// Based on the groups present in the graph data, auto-generate an even color palette (groups JSON) and fill in the legend
///   pLeg(序号) = $ListBuild(背景色, 分组名)
///   pLeg(index) = $ListBuild(background color, group name)
ClassMethod AutoGroups(pGraphJSON As %String, Output pLeg) As %String
{
    Kill pLeg
    Set tGroups = {}
    Try {
        Set tObj = ##class(%DynamicObject).%FromJSON(pGraphJSON)
        Set tIter = tObj.nodes.%GetIterator()
        Set tN = 0
        While tIter.%GetNext(.tK, .tNode) {
            Set tGrp = tNode.group
            Continue:tGrp=""
            Continue:$Data(tSeen(tGrp))
            Set tN = tN + 1, tSeen(tGrp) = tN, tList(tN) = tGrp
        }
        Quit:tN=0
        For tI = 1:1:tN {
            Set tGrp = tList(tI)
            Set tHue = ((tI - 1) * 360) \ tN
            Set tBg = "hsl(" _ tHue _ ",68%,55%)"
            Set tBd = "hsl(" _ tHue _ ",72%,42%)"
            Set tGO = ##class(%DynamicObject).%New()
            Set tCol = ##class(%DynamicObject).%New()
            Set tCol.background = tBg, tCol.border = tBd
            Set tGO.color = tCol
            Set tFnt = ##class(%DynamicObject).%New()
            Set tFnt.color = "#1e3a8a"
            Set tGO.font = tFnt
            Do tGroups.%Set(tGrp, tGO)
            Set pLeg(tI) = $ListBuild(tBg, tGrp)
        }
    } Catch {
    }
    Quit tGroups.%ToJSON()
}

/// 由外部提供的 groups JSON 反推图例
/// Derive the legend from an externally provided groups JSON
ClassMethod LegendFromGroups(pGroupsJSON As %String, Output pLeg)
{
    Kill pLeg
    Try {
        Set tObj = ##class(%DynamicObject).%FromJSON(pGroupsJSON)
        Set tIter = tObj.%GetIterator()
        Set tI = 0
        While tIter.%GetNext(.tGrp, .tG) {
            Set tI = tI + 1
            Set tBg = ""
            If $IsObject(tG), $IsObject(tG.color) { Set tBg = tG.color.background }
            Set pLeg(tI) = $ListBuild(tBg, tGrp)
        }
    } Catch {
    }
}

/// 扫描视图内各层的 ^GraphData.OUT，把源类以 pPrefix 开头的全部边构造成 vis-network 图数据
/// Scan ^GraphData.OUT of every layer in the view and build all edges whose source class starts with pPrefix into vis-network graph data
///   pPrefix   : 类名前缀，例如 "Research." 或 "Logistics."
///   pPrefix   : class name prefix, e.g. "Research." or "Logistics."
///   pProvider : 提供 Label()/NodeDesc() 的类名
///   pProvider : class name that provides Label()/NodeDesc()
ClassMethod BuildFromGlobal(pPrefix As %String, pProvider As %String, pLayers As %String = "") As %String
{
    Set tG = {}, tG.nodes = [], tG.edges = []                // 安全默认：空图 JSON | safe default: empty graph JSON
    Try {
        Set tNodes = [], tEdges = []
        Kill tSeen
        Set tPL = $Length(pPrefix)
        Set tViews = ##class(Graph.Layer).View(pLayers)
        For tLI = 1:1:$ListLength(tViews) {
        Set tRoot = ##class(Graph.Layer).Root("OUT", $List(tViews, tLI))
        Set tSrc = ""
        For {
            Set tSrc = $Order(@tRoot@(tSrc))
            Quit:tSrc=""
            Continue:($Extract($ListGet(tSrc, 2), 1, tPL)'=pPrefix)
            Set tTgt = ""
            For {
                Set tTgt = $Order(@tRoot@(tSrc, tTgt))
                Quit:tTgt=""
                Set tRel = ""
                For {
                    Set tRel = $Order(@tRoot@(tSrc, tTgt, tRel))
                    Quit:tRel=""
                    // 同一条边在多层出现只画一次 | draw an edge present in several layers once
                    Continue:$Data(tSeenE(tSrc, tTgt, tRel))
                    Set tSeenE(tSrc, tTgt, tRel) = ""
                    Do ..AddNode(tSrc, .tSeen, tNodes, pProvider)
                    Do ..AddNode(tTgt, .tSeen, tNodes, pProvider)
                    Set tE = {}
                    Set tE.from = ..nid(tSrc), tE.to = ..nid(tTgt), tE.label = tRel
                    Do tEdges.%Push(tE)
                }
            }
        }
        }
        Set tG = {}, tG.nodes = tNodes, tG.edges = tEdges
    }
    Catch ex {}
    Quit tG.%ToJSON()
}

/// 追加去重节点（label/title 委托 provider）
/// Append a deduplicated node (label/title delegated to the provider)
ClassMethod AddNode(pOID As %List, ByRef pSeen, pNodes As %DynamicArray, pProvider As %String)
{
    Try {
        Set tId = ..nid(pOID)
        Quit:$Data(pSeen(tId))
        Set pSeen(tId) = 1
        Set tN = {}
        Set tN.id = tId
        Set tN.group = $Piece($ListGet(pOID, 2), ".", *)
        Set tN.label = $classmethod(pProvider, "Label", pOID)
        Try { Set tN.title = $classmethod(pProvider, "NodeDesc", pOID) } Catch { }
        Do pNodes.%Push(tN)
    }
    Catch ex {}
}

/// 节点 id：OID($LB(Id,Class)) → "Id~Class"
/// Node id: OID($LB(Id,Class)) -> "Id~Class"
ClassMethod nid(pOID As %List) As %String
{
    Set tRet = ""
    Try {
        Set tRet = $ListGet(pOID, 1) _ "~" _ $ListGet(pOID, 2)
    }
    Catch ex {}
    Quit tRet
}

/// HTML 转义
/// HTML escaping
ClassMethod esc(pText As %String) As %String
{
    Set tRet = ""
    Try {
        Set tRet = $ZCONVERT(pText, "O", "HTML")
    }
    Catch ex {}
    Quit tRet
}

/// 组件样式（类名统一以 gnw- 前缀，避免与宿主页面冲突）
/// Component styles (class names uniformly prefixed with gnw- to avoid conflicts with the host page)
ClassMethod CSS() As %String
{
    Quit ".gnw{position:relative}"
     _ ".gnw-net{width:100%;border:1px solid #e2e8f0;border-radius:12px;background:#fafcff}"
     _ ".gnw-bar{display:flex;gap:6px;margin-bottom:10px}"
     _ ".gnw-bar button{border:1px solid #cbd5e1;background:#fff;color:#334155;border-radius:8px;padding:5px 12px;font-size:13px;cursor:pointer}"
     _ ".gnw-bar button:hover{background:#eef2ff;border-color:#a5b4fc;color:#4338ca}"
     _ ".gnw-legend{display:flex;flex-wrap:wrap;gap:14px;margin-top:12px;font-size:13px;color:#475569}"
     _ ".gnw-legend i.gnw-dot{display:inline-block;width:12px;height:12px;border-radius:50%;margin-right:6px;vertical-align:middle}"
     _ ".gnw-info{margin-top:12px;padding:10px 14px;border:1px solid #e2e8f0;border-left:4px solid #6366f1;border-radius:8px;background:#f8fafc;font-size:13px;color:#334155;min-height:20px}"
     _ ".gnw-info-tip{color:#94a3b8}"
     _ ".gnw-info-g{font-size:11px;color:#4338ca;background:#eef2ff;padding:1px 8px;border-radius:6px;vertical-align:middle}"
     _ ".gnw-info-d{margin-top:6px;color:#475569;white-space:pre-wrap;line-height:1.5}"
}

}
