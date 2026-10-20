Include %occInclude

/// Graph.UI.Network 组件演示页
/// Graph.UI.Network component demo page
///
/// 访问：/csp/healthshare/nehr/Graph.UI.Demo.cls
/// Access: /csp/healthshare/nehr/Graph.UI.Demo.cls
///       ?action=setup 重建演示场景数据
///       ?action=setup rebuilds the demo scenario data
///
/// 本页仅用于演示如何用最少的代码把「知识图谱标准组件」嵌入任意 CSP 页面：
/// This page only demonstrates how to embed the "standard knowledge graph component" into any CSP page with minimal code:
///   1) &lt;head&gt; 里 Do ##class(Graph.UI.Network).Head()
///   1) In &lt;head&gt;: Do ##class(Graph.UI.Network).Head()
///   2) 样式表并入 ##class(Graph.UI.Network).CSS()
///   2) Merge into the stylesheet: ##class(Graph.UI.Network).CSS()
///   3) 页面主体 Do ##class(Graph.UI.Network).Widget(divId, json, .opts)
///   3) In the page body: Do ##class(Graph.UI.Network).Widget(divId, json, .opts)
///
/// 数据沿用 Research.Demo 的精准医疗知识图谱（Research.* 全部边），
/// Data reuses Research.Demo's precision-medicine knowledge graph (all Research.* edges),
/// 节点 label / 悬停提示由 provider 类 Research.Demo 提供。
/// node label / hover tooltip are provided by the provider class Research.Demo.
Class Graph.UI.Demo Extends %CSP.Page
{

Parameter CONTENTTYPE = "text/html";

Parameter CHARSET = "UTF-8";

/// 页面入口
/// Page entry point
ClassMethod OnPage() As %Status
{
    Set tSC = $$$OK
    Try {
        // 首访 / ?action=setup 确保有演示数据
        // First visit / ?action=setup ensures demo data exists
        Set tAction = %request.Get("action")
        If tAction = "setup" {
            Do ##class(Research.Demo).Setup(0)
        } Else {
            Set tCnt = 0
            &sql(SELECT COUNT(*) INTO :tCnt FROM Research.Patient)
            If +tCnt = 0 { Do ##class(Research.Demo).Setup(0) }
        }

        // === 从图全局构造图数据（provider = 本页，提供 Label/NodeDesc）===
        // === Build graph data from the graph global (provider = this page, provides Label/NodeDesc) ===
        Set tJSON = ##class(Graph.UI.Network).BuildFromGlobal("Research.", "Graph.UI.Demo")

        Write "<!DOCTYPE html>", !
        Write "<html lang='zh-CN'><head><meta charset='UTF-8'>", !
        Write "<meta name='viewport' content='width=device-width, initial-scale=1.0'>", !
        Write "<title>Graph.UI.Network 组件演示</title>", !
        // 步骤 1：引入组件依赖
        // Step 1: include component dependencies
        Do ##class(Graph.UI.Network).Head()
        // 步骤 2：并入组件样式
        // Step 2: merge in component styles
        Write "<style>", ..CSS(), ##class(Graph.UI.Network).CSS(), "</style>", !
        Write "</head><body>", !

        Write "<header class='topbar'>"
        Write "<div class='brand'>&#128209; Graph.UI.Network &#183; 知识图谱标准组件</div>"
        Write "<div class='sub'>三行代码把交互式属性图嵌入任意 CSP 页面</div>"
        Write "<a class='rebuild' href='?action=setup'>&#8635; 重建数据</a>"
        Write "</header>", !

        // --- 用法说明 ---
        // --- Usage notes ---
        Write "<section class='card'><h2>组件用法</h2>"
        Write "<pre class='code'>"
        Write ..esc("// 1) <head> 引入依赖与辅助脚本") _ $Char(10)
        Write ..esc("Do ##class(Graph.UI.Network).Head()") _ $Char(10) _ $Char(10)
        Write ..esc("// 2) 样式表并入组件 CSS") _ $Char(10)
        Write ..esc("Write ""<style>"", ..CSS(), ##class(Graph.UI.Network).CSS(), ""</style>""") _ $Char(10) _ $Char(10)
        Write ..esc("// 3) 构造图数据并渲染组件") _ $Char(10)
        Write ..esc("Set json = ##class(Graph.UI.Network).BuildFromGlobal(""Research."", ""Research.Demo"")") _ $Char(10)
        Write ..esc("Do ##class(Graph.UI.Network).Widget(""net"", json)")
        Write "</pre></section>", !

        // --- 示例一：自动配色 + 自动图例（零配置）---
        // --- Example 1: auto colors + auto legend (zero config) ---
        Write "<section class='card'><h2>示例一 · 零配置（自动配色 + 自动图例）</h2>"
        Write "<p class='desc'>不传任何 groups，组件按图中出现的分组自动分配色板并生成图例。</p>"
        Do ##class(Graph.UI.Network).Widget("netAuto", tJSON)
        Write "</section>", !

        // --- 示例二：自定义高度 + 关闭物理布局 ---
        // --- Example 2: custom height + physics layout disabled ---
        Write "<section class='card'><h2>示例二 · 自定义参数（固定高度 / 关闭物理布局）</h2>"
        Write "<p class='desc'>通过 opts 控制高度、工具条、图例、物理布局、边高亮色等。</p>"
        Kill tOpts
        Set tOpts("height") = "380px"
        Set tOpts("physics") = 0
        Set tOpts("edgeHighlight") = "#f59e0b"
        Do ##class(Graph.UI.Network).Widget("netFixed", tJSON, .tOpts)
        Write "</section>", !

        Write "<footer class='foot'>组件 Graph.UI.Network &#183; 数据 Research.Demo &#183; 图边由 Graph.Object.Index 功能索引自动维护</footer>", !

        Write "</body></html>", !
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
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

/// provider · 节点显示文本（复用 Research.Demo 的标签逻辑）
/// provider - node display text (reuses Research.Demo's label logic)
ClassMethod Label(pOID As %List) As %String
{
    Set tRet = ""
    Try {
        Set tRet = ##class(Research.Demo).Label(pOID)
    }
    Catch ex {}
    Quit tRet
}

/// provider · 节点悬停提示
/// provider - node hover tooltip
ClassMethod NodeDesc(pOID As %List) As %String
{
    Set tRet = ""
    Try {
        Set tId = $ListGet(pOID, 1), tCls = $ListGet(pOID, 2)
        Set tObj = $classmethod(tCls, "%OpenId", tId)
        If $IsObject(tObj) {
            If tCls = "Research.Patient" {
                Set tRet = "患者 " _ tObj.MRN _ " · 性别 " _ tObj.Gender _ " · 出生 " _ tObj.BirthYear
            } ElseIf tCls = "Research.Condition" {
                Set tRet = "疾病 [" _ tObj.Code _ "] " _ tObj.Name
            } ElseIf tCls = "Research.Drug" {
                Set tRet = "药物 [" _ tObj.Code _ "] " _ tObj.Name
            } ElseIf tCls = "Research.Gene" {
                Set tRet = "基因 " _ tObj.Symbol _ " · " _ tObj.Name
            } ElseIf tCls = "Research.Study" {
                Set tRet = "研究 [" _ tObj.Code _ "] " _ tObj.Title
            }
        }
    }
    Catch ex {}
    Quit tRet
}

/// 页面样式（仅本演示页外壳，图组件样式来自 Graph.UI.Network.CSS()）
/// Page styles (only this demo page shell; graph component styles come from Graph.UI.Network.CSS())
ClassMethod CSS() As %String
{
    Quit "*{box-sizing:border-box}body{margin:0;font-family:system-ui,-apple-system,'Segoe UI',Roboto,'PingFang SC','Microsoft YaHei',sans-serif;background:#f1f5f9;color:#0f172a}"
     _ ".topbar{background:linear-gradient(90deg,#0f766e,#0891b2);color:#fff;padding:16px 28px;display:flex;align-items:center;gap:16px;box-shadow:0 2px 10px rgba(0,0,0,.15)}"
     _ ".brand{font-size:20px;font-weight:700}.sub{color:#cffafe;font-size:13px;flex:1}"
     _ ".rebuild{color:#e2e8f0;background:#0e7490;padding:8px 14px;border-radius:8px;text-decoration:none;font-size:13px}.rebuild:hover{background:#06b6d4}"
     _ ".card{background:#fff;border-radius:14px;padding:20px 24px;margin:20px 24px;box-shadow:0 1px 6px rgba(0,0,0,.06)}"
     _ ".card h2{margin:0 0 12px;font-size:17px}"
     _ ".desc{color:#475569;font-size:14px;margin:0 0 14px}"
     _ ".code{background:#0f172a;color:#e2e8f0;border-radius:10px;padding:16px 18px;font-family:'SFMono-Regular',Consolas,'Liberation Mono',monospace;font-size:13px;line-height:1.6;overflow-x:auto;margin:0}"
     _ ".foot{color:#64748b;font-size:12px;text-align:center;padding:24px}"
}

}
