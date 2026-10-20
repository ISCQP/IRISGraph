Include %occInclude

/// Graph testbed 一键安装器：创建 TESTBED 命名空间与 Web 应用，加载 Graph 引擎与演示类，播种数据并自检。
/// One-click installer for the Graph testbed: creates the TESTBED namespace and web apps, loads the Graph engine and the demo classes, seeds data and self-checks.
///
/// 构建期分两次会话调用（任何失败都会以非零退出码终止构建）：
/// Called from two build sessions (any failure terminates the build with a non-zero exit code):
///   1) Setup + Seed   建命名空间/角色/Web 应用 → 加载编译类 → 播种数据
///   2) Finish         做一致性与用例自检
/// 运行期由 post-start.sh 调用 PostStart（仅在设置了 TESTBED_ADMIN_PASSWORD 时改管理员密码）。
/// Not included by design: ClinicalResearch.ClinicalAI.*, ProjectKB.*, the EMR/drug/gene sample, the PGx platform and GraphAction.
Class Install.Testbed Extends %RegisteredObject
{

Parameter NAMESPACE = "TESTBED";

/// 页面与 REST 应用角色：对 TESTBED 数据库有读写权限 / role of the page and REST apps: read-write on the TESTBED database
Parameter APPROLE = "TESTBED_App";

/// 步骤 1a（在 %SYS 中调用）：命名空间、角色，然后加载并编译 pRoot/src 下的全部类并创建 Web 应用
/// Step 1a (called in %SYS): namespace, role, then load and compile every class under pRoot/src and create the web apps
ClassMethod Setup(pRoot As %String = "/opt/testbed") As %Status
{
    Set sc = $$$OK, here = $Namespace
    Try {
        Zn "%SYS"
        Do ##class(Security.Users).UnExpireUserPasswords("*")
        $$$ThrowOnError(..CreateNamespace())
        $$$ThrowOnError(..CreateAppRole())
        Zn ..#NAMESPACE
        Do ..Say("loading and compiling classes from "_pRoot_"/src")
        $$$ThrowOnError($SYSTEM.OBJ.LoadDir(pRoot_"/src", "ck", .errs, 1))
        $$$ThrowOnError(..CreateWebApps())
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Zn here
    Quit sc
}

/// 步骤 1b（在 TESTBED 中调用）：播种演示数据
/// Step 1b (called in TESTBED): seed the demo data
ClassMethod Seed() As %Status
{
    Set sc = $$$OK
    Try {
        Do ..Say("Logistics risk tracing (Persian Gulf / Hormuz)")
        $$$ThrowOnError(##class(Logistics.Test.PersianGulfDemo).Setup())

        Do ..Say("EMR contact tracing (2000 people, fan-out 8)")
        Do ##class(EMR.Test.ContactTrace).Setup(2000, 8, 0)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// 步骤 2：做图镜像一致性与用例自检并打印摘要
/// Step 2: run the graph mirror consistency check and the use-case self-checks and print a summary
ClassMethod Finish() As %Status
{
    Set sc = $$$OK, fails = []
    Try {
        Set miss = ##class(Graph.Store).Verify(.out, .in)
        Do ..Say("graph mirror: OUT="_out_" IN="_in_" missing="_miss)
        If miss Do fails.%Push("graph IN mirror is missing "_miss_" entries")

        Do ..Say("layers: "_##class(Graph.Layer).List().%ToJSON())
        Do ..Say("User digest: "_##class(Graph.Layer).Digest("User").%ToJSON())

        Do ..Expect("the risk event affects one segment", "SELECT COUNT(*) FROM Logistics_Risk.RiskEvent r JOIN Graph.SingleHop('Logistics.Risk.RiskEvent', CAST(r.ID AS VARCHAR(20)), 'affects_segment', 0) h ON 1=1", 1, fails)
        Do ..Expect("risk -> impact -> shipment", "SELECT COUNT(*) FROM Logistics_Risk.RiskEvent r JOIN Graph.MultiHop('Logistics.Risk.RiskEvent', CAST(r.ID AS VARCHAR(20)), 'causes:0,impact_affects_shipment:0') h ON 1=1", 1, fails)
        Do ..Expect("contact tracing: person 1 has graph contacts (numeric ids)", "SELECT CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END FROM Graph.SingleHop('CTBench.Person', 1, '', 0)", 1, fails)

        If fails.%Size() Throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "self-check failed: "_fails.%ToJSON()))
        Do ..Say("self-check passed")
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// 运行一条 SQL，其单值结果必须等于 pExpected（pExpected="" 时只要求语句可执行）
/// Run one SQL statement whose single value must equal pExpected (with pExpected="" it only has to execute)
ClassMethod Expect(pName As %String, pSQL As %String, pExpected As %String, pFails As %DynamicArray) [ Private ]
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, pSQL)
    If rs.%SQLCODE < 0 {
        Do pFails.%Push(pName_": "_rs.%Message)
        Quit
    }
    If 'rs.%Next() {
        Do pFails.%Push(pName_": no row")
        Quit
    }
    Set got = rs.%GetData(1)
    Do ..Say("  check '"_pName_"' = "_got)
    If (pExpected '= "") && (got '= pExpected) Do pFails.%Push(pName_": expected "_pExpected_", got "_got)
}

/// 在 %SYS 中创建独立数据库与同名命名空间（幂等）；全局与例程都落在该库，并绑定独立资源 %DB_TESTBED
/// Create an own database and the namespace of the same name in %SYS (idempotent); globals and routines live in it, bound to its own resource %DB_TESTBED
ClassMethod CreateNamespace() As %Status
{
    Set sc = $$$OK, here = $Namespace, ns = ..#NAMESPACE
    Try {
        Zn "%SYS"
        If '##class(Config.Databases).Exists(ns) {
            Set dir = ##class(%File).NormalizeDirectory($SYSTEM.Util.ManagerDirectory()_$ZConvert(ns, "L"))
            If '##class(%File).DirectoryExists(dir), '##class(%File).CreateDirectoryChain(dir) Throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Cannot create "_dir))
            $$$ThrowOnError(##class(SYS.Database).CreateDatabase(dir))
            Set res = "%DB_"_$ZConvert(ns, "U")
            If '##class(Security.Resources).Exists(res) {
                $$$ThrowOnError(##class(Security.Resources).Create(res, "Graph testbed database "_ns))
            }
            Set db("Directory") = dir
            $$$ThrowOnError(##class(Config.Databases).Create(ns, .db))
            Set sysdb = ##class(SYS.Database).%OpenId(dir)
            If '$IsObject(sysdb) Throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Cannot open database "_dir))
            Set sysdb.ResourceName = res
            $$$ThrowOnError(sysdb.%Save())
        }
        If '##class(Config.Namespaces).Exists(ns) {
            Set nsprops("Globals") = ns, nsprops("Routines") = ns
            $$$ThrowOnError(##class(Config.Namespaces).Create(ns, .nsprops))
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Zn here
    Quit sc
}

/// 角色 TESTBED_App：对 TESTBED 数据库读写，供页面与 REST 应用以应用角色方式授予
/// Role TESTBED_App: read-write on the TESTBED database, granted to the page and REST apps as an application role
ClassMethod CreateAppRole() As %Status
{
    Set sc = $$$OK, here = $Namespace
    Try {
        Zn "%SYS"
        If '##class(Security.Roles).Exists(..#APPROLE) {
            $$$ThrowOnError(##class(Security.Roles).Create(..#APPROLE, "Graph testbed web application role (database access)", "%DB_"_$ZConvert(..#NAMESPACE, "U")_":RW"))
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Zn here
    Quit sc
}

/// 创建 Web 应用（幂等）：/csp/testbed（演示页面）与 /api/graph（Graph REST）。均为密码认证，不允许匿名
/// Create the web apps (idempotent): /csp/testbed (demo pages) and /api/graph (Graph REST). Both require password authentication; anonymous access is refused
ClassMethod CreateWebApps() As %Status
{
    Set sc = $$$OK, here = $Namespace
    Try {
        Zn "%SYS"
        Set dir = ##class(%File).NormalizeDirectory($SYSTEM.Util.InstallDirectory()_"csp/testbed")
        If '##class(%File).DirectoryExists(dir), '##class(%File).CreateDirectoryChain(dir) Throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Cannot create "_dir))
        For app = "/csp/testbed", "/api/graph" {
            Kill props
            Set props("NameSpace") = ..#NAMESPACE, props("Enabled") = 1, props("AutheEnabled") = 32, props("MatchRoles") = ":"_..#APPROLE
            Set props("Type") = 2, props("CSPZENEnabled") = 1, props("Recurse") = 1
            If app = "/csp/testbed" {
                Set props("Path") = dir, props("Description") = "Graph testbed demo pages"
            } Else {
                Set props("DispatchClass") = "Graph.REST.disp", props("Description") = "Graph REST API"
            }
            If ##class(Security.Applications).Exists(app) {
                $$$ThrowOnError(##class(Security.Applications).Modify(app, .props))
            } Else {
                $$$ThrowOnError(##class(Security.Applications).Create(app, .props))
            }
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Zn here
    Quit sc
}

/// 运行期入口（由 post-start.sh 调用）：仅当设置了环境变量 TESTBED_ADMIN_PASSWORD 时，改 _SYSTEM / SuperUser / Admin 的口令
/// Run-time entry (called by post-start.sh): only when TESTBED_ADMIN_PASSWORD is set, change the password of _SYSTEM / SuperUser / Admin
ClassMethod PostStart() As %Status
{
    Set sc = $$$OK, here = $Namespace
    Try {
        Set password = $SYSTEM.Util.GetEnviron("TESTBED_ADMIN_PASSWORD")
        If password = "" Quit
        Zn "%SYS"
        For user = "_SYSTEM", "SuperUser", "Admin" {
            If '##class(Security.Users).Exists(user) Continue
            Kill props
            Set props("Password") = password, props("ChangePassword") = 0
            $$$ThrowOnError(##class(Security.Users).Modify(user, .props))
        }
        Write "[testbed] administrator password updated from TESTBED_ADMIN_PASSWORD", !
    } Catch ex {
        Set sc = ex.AsStatus()
        Write "[testbed] PostStart failed: ", $SYSTEM.Status.GetErrorText(sc), !
    }
    Zn here
    Quit sc
}

ClassMethod Say(pText As %String) [ Private ]
{
    Write "[testbed] ", pText, !
}

/// 脚本出口：失败时打印原因并以非零退出码终止进程，使构建失败
/// Script exit: on failure print the reason and terminate the process with a non-zero exit code so the build fails
ClassMethod Exit(pStatus As %Status)
{
    If $$$ISERR(pStatus) {
        Write !, "TESTBED-INSTALL-FAILED: ", $SYSTEM.Status.GetErrorText(pStatus), !
        Do $ZUTIL(4, $JOB, 1)
    }
    Write !, "TESTBED-STEP-OK", !
}

}
