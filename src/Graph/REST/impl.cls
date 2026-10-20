/// Graph REST API — business logic.<br/>
/// Endpoints are defined by the OpenAPI spec in Graph.REST.spec: read-only traversals wrap
/// Graph.Tools; the addedge / removeedge write endpoints wrap Graph.Store.<br/>
/// All responses return graph nodes as { "class": ..., "id": ... } objects
/// (the internal OID $ListBuild(Id, Class) is never leaked to JSON).
/// Author: QP
/// Version: 1.0
/// Last Modified Date: 2026/07/26
Class Graph.REST.impl Extends %REST.Impl [ ProcedureBlock ]
{

Parameter ExposeServerExceptions = 1;

/// Read request body as %DynamicObject
ClassMethod ReadBody(pBody As %Stream.Object) As %DynamicObject
{
    Try {
        If '$IsObject(pBody) || (pBody.Size = 0) {
            Return {}
        }
        Return ##class(%DynamicObject).%FromJSON(pBody)
    } Catch ex {
        Return {}
    }
}

/// Build a standard JSON response stream
ClassMethod BuildResponse(pPayload As %DynamicObject) As %Stream.Object
{
    Set tStream = ##class(%Stream.TmpCharacter).%New()
    Try {
        Do tStream.Write(pPayload.%ToJSON())
    } Catch ex {
    }
    Return tStream
}

/// Resolve a { class, id | no } node reference to an internal OID $ListBuild(Id, Class).
/// Returns "" and sets pError on failure.
ClassMethod ResolveNode(pNode As %DynamicObject, Output pError As %String) As %String
{
    Set pError = ""
    Try {
        If '$IsObject(pNode) {
            Set pError = "node is required"
            Return ""
        }
        Set tClass = pNode.%Get("class", "")
        If tClass = "" {
            Set pError = "node.class is required"
            Return ""
        }
        Set tId = pNode.%Get("id", "")
        If tId '= "" {
            Return $ListBuild(tId, tClass)
        }
        Set tNo = pNode.%Get("no", "")
        If tNo '= "" {
            Set tOID = ##class(Graph.Object.Tools).GetOID(tClass, tNo)
            If tOID = "" {
                Set pError = "node not found for class '" _ tClass _ "' no '" _ tNo _ "'"
            }
            Return tOID
        }
        Set pError = "node requires either 'id' or 'no'"
        Return ""
    } Catch ex {
        Set pError = ex.DisplayString()
        Return ""
    }
}

/// Resolve a { class, id } node reference to a generic node key $ListBuild(id, class).
/// Used by the data-layer write endpoints (no GetOIDByNO resolution).
/// Returns "" and sets pError on failure.
ClassMethod ResolveKey(pNode As %DynamicObject, Output pError As %String) As %String
{
    Set pError = ""
    Try {
        If '$IsObject(pNode) {
            Set pError = "node is required"
            Return ""
        }
        Set tClass = pNode.%Get("class", "")
        Set tId = pNode.%Get("id", "")
        If (tClass = "") || (tId = "") {
            Set pError = "node requires both 'class' and 'id'"
            Return ""
        }
        Return $ListBuild(tId, tClass)
    } Catch ex {
        Set pError = ex.DisplayString()
        Return ""
    }
}

/// Convert an internal OID $ListBuild(Id, Class) to { "class": ..., "id": ... }
ClassMethod NodeJSON(pOID As %String) As %DynamicObject
{
    Try {
        Return { "class": ($ListGet(pOID, 2)), "id": ($ListGet(pOID, 1)) }
    } Catch ex {
        Return {}
    }
}

/// Convert a Graph.Tools hop array (OID / Relation / TargetOID) to
/// [ { "source": {class,id}, "relation": ..., "target": {class,id} }, ... ]
ClassMethod FormatHops(pResult As %DynamicArray) As %DynamicArray
{
    Set tOut = []
    Try {
        For tI = 1:1:pResult.%Size() {
            Set tHop = pResult.%Get(tI - 1)
            Set tRow = {}
            Set tRow.source = ..NodeJSON(tHop.OID)
            Set tRow.relation = tHop.Relation
            Set tRow.target = ..NodeJSON(tHop.TargetOID)
            Do tOut.%Push(tRow)
        }
    } Catch ex {
    }
    Return tOut
}

/// Single-hop neighbours of a node.<br/>
/// body: { node:{class,id|no}, relation, inverse }
ClassMethod SingleHop(body As %Stream.Object) As %Stream.Object
{
    Do ..%SetStatusCode(200)
    Do ..%SetContentType("application/json")
    Try {
        Set tReq = ..ReadBody(body)
        Set tNode = ..ResolveNode(tReq.%Get("node"), .tErr)
        If tErr '= "" {
            Do ..%SetStatusCode(400)
            Return ..BuildResponse({ "error": (tErr) })
        }
        Set tRelation = tReq.%Get("relation", "")
        Set tInverse = +tReq.%Get("inverse", 0)

        Set tSC = ##class(Graph.Tools).SingleHop(tNode, tRelation, tInverse, .tResult, tReq.%Get("layers", ""))
        If $$$ISERR(tSC) {
            Do ..%SetStatusCode(500)
            Return ..BuildResponse({ "error": ($System.Status.GetErrorText(tSC)) })
        }

        Set tResponse = {}
        Set tResponse.edges = ..FormatHops(tResult)
        Set tResponse.count = tResponse.edges.%Size()
        Return ..BuildResponse(tResponse)
    } Catch ex {
        Do ..%SetStatusCode(500)
        Return ..BuildResponse({ "error": (ex.DisplayString()) })
    }
}

/// Multi-hop traversal along an ordered relation path.<br/>
/// body: { node:{class,id|no}, relations:[ {relation,inverse}, ... ] }
ClassMethod MultiHop(body As %Stream.Object) As %Stream.Object
{
    Do ..%SetStatusCode(200)
    Do ..%SetContentType("application/json")
    Try {
        Set tReq = ..ReadBody(body)
        Set tNode = ..ResolveNode(tReq.%Get("node"), .tErr)
        If tErr '= "" {
            Do ..%SetStatusCode(400)
            Return ..BuildResponse({ "error": (tErr) })
        }
        Set tRels = tReq.%Get("relations")
        If '$IsObject(tRels) || (tRels.%Size() = 0) {
            Do ..%SetStatusCode(400)
            Return ..BuildResponse({ "error": "relations is required and must be a non-empty array" })
        }

        // Adapt public (lowercase) relation steps to the keys Graph.Tools.MultiHop expects
        Set tRelList = []
        For tI = 1:1:tRels.%Size() {
            Set tStep = tRels.%Get(tI - 1)
            Do tRelList.%Push({ "Relation": (tStep.%Get("relation", "")), "Inverse": (+tStep.%Get("inverse", 0)) })
        }

        Set tSC = ##class(Graph.Tools).MultiHop(tNode, tRelList, .tResult, tReq.%Get("layers", ""))
        If $$$ISERR(tSC) {
            Do ..%SetStatusCode(500)
            Return ..BuildResponse({ "error": ($System.Status.GetErrorText(tSC)) })
        }

        Set tResponse = {}
        Set tResponse.endpoints = ..FormatHops(tResult)
        Set tResponse.count = tResponse.endpoints.%Size()
        Return ..BuildResponse(tResponse)
    } Catch ex {
        Do ..%SetStatusCode(500)
        Return ..BuildResponse({ "error": (ex.DisplayString()) })
    }
}

/// Shortest path between two nodes.<br/>
/// body: { start:{class,id|no}, end:{class,id|no} }
ClassMethod ShortestPath(body As %Stream.Object) As %Stream.Object
{
    Do ..%SetStatusCode(200)
    Do ..%SetContentType("application/json")
    Try {
        Set tReq = ..ReadBody(body)
        Set tStartNode = ..ResolveNode(tReq.%Get("start"), .tErr)
        If tErr '= "" {
            Do ..%SetStatusCode(400)
            Return ..BuildResponse({ "error": ("start: " _ tErr) })
        }
        Set tEndNode = ..ResolveNode(tReq.%Get("end"), .tErr)
        If tErr '= "" {
            Do ..%SetStatusCode(400)
            Return ..BuildResponse({ "error": ("end: " _ tErr) })
        }

        Set tSC = ##class(Graph.Tools).ShortestPath(tStartNode, tEndNode, .tResult, .tStats, "", tReq.%Get("layers", ""))
        If $$$ISERR(tSC) {
            Do ..%SetStatusCode(500)
            Return ..BuildResponse({ "error": ($System.Status.GetErrorText(tSC)) })
        }

        Set tSteps = []
        For tI = 1:1:tResult.%Size() {
            Set tStep = tResult.%Get(tI - 1)
            Set tRow = {}
            Set tRow.step = tI
            Set tRow.relation = tStep.Relation
            Set tRow.inverse = +tStep.Inverse
            Set tRow.source = ..NodeJSON(tStep.OID)
            Set tRow.target = ..NodeJSON(tStep.TargetOID)
            Do tSteps.%Push(tRow)
        }

        Set tResponse = {}
        Set tResponse.found = (tSteps.%Size() > 0)
        Set tResponse.length = tSteps.%Size()
        Set tResponse.path = tSteps
        Return ..BuildResponse(tResponse)
    } Catch ex {
        Do ..%SetStatusCode(500)
        Return ..BuildResponse({ "error": (ex.DisplayString()) })
    }
}

/// Breadth-first traversal with a depth limit.<br/>
/// body: { node:{class,id|no}, maxDepth }
ClassMethod BFS(body As %Stream.Object) As %Stream.Object
{
    Do ..%SetStatusCode(200)
    Do ..%SetContentType("application/json")
    Try {
        Set tReq = ..ReadBody(body)
        Set tNode = ..ResolveNode(tReq.%Get("node"), .tErr)
        If tErr '= "" {
            Do ..%SetStatusCode(400)
            Return ..BuildResponse({ "error": (tErr) })
        }
        Set tMaxDepth = +tReq.%Get("maxDepth", 3)
        If tMaxDepth <= 0 {
            Set tMaxDepth = 3
        }

        Set tSC = ##class(Graph.Tools).BFS(tNode, tMaxDepth, .tResult, tReq.%Get("layers", ""))
        If $$$ISERR(tSC) {
            Do ..%SetStatusCode(500)
            Return ..BuildResponse({ "error": ($System.Status.GetErrorText(tSC)) })
        }

        Set tResponse = {}
        Set tResponse.maxDepth = tMaxDepth
        Set tResponse.edges = ..FormatHops(tResult)
        Set tResponse.count = tResponse.edges.%Size()
        Return ..BuildResponse(tResponse)
    } Catch ex {
        Do ..%SetStatusCode(500)
        Return ..BuildResponse({ "error": (ex.DisplayString()) })
    }
}

/// Parallel breadth-first traversal (multi-process, for very large graphs).<br/>
/// Semantically identical to BFS; expands each frontier level with %SYSTEM.WorkMgr workers.<br/>
/// body: { node:{class,id|no}, maxDepth, workers }
ClassMethod BFSParallel(body As %Stream.Object) As %Stream.Object
{
    Do ..%SetStatusCode(200)
    Do ..%SetContentType("application/json")
    Try {
        Set tReq = ..ReadBody(body)
        Set tNode = ..ResolveNode(tReq.%Get("node"), .tErr)
        If tErr '= "" {
            Do ..%SetStatusCode(400)
            Return ..BuildResponse({ "error": (tErr) })
        }
        Set tMaxDepth = +tReq.%Get("maxDepth", 3)
        If tMaxDepth <= 0 {
            Set tMaxDepth = 3
        }
        Set tWorkers = +tReq.%Get("workers", 0)

        Set tSC = ##class(Graph.Tools).BFSParallel(tNode, tMaxDepth, .tResult, tWorkers, "", .tStats, 0, "", "", "", tReq.%Get("layers", ""))
        If $$$ISERR(tSC) {
            Do ..%SetStatusCode(500)
            Return ..BuildResponse({ "error": ($System.Status.GetErrorText(tSC)) })
        }

        Set tResponse = {}
        Set tResponse.maxDepth = tMaxDepth
        Set tResponse.workers = tWorkers
        Set tResponse.edges = ..FormatHops(tResult)
        Set tResponse.count = tResponse.edges.%Size()
        Return ..BuildResponse(tResponse)
    } Catch ex {
        Do ..%SetStatusCode(500)
        Return ..BuildResponse({ "error": (ex.DisplayString()) })
    }
}

/// Add a data-layer edge source --relation--> target (Graph.Store.AddEdge).<br/>
/// body: { source:{class,id}, relation, target:{class,id} }
ClassMethod AddEdge(body As %Stream.Object) As %Stream.Object
{
    Do ..%SetStatusCode(200)
    Do ..%SetContentType("application/json")
    Try {
        Set tReq = ..ReadBody(body)
        Set tSrc = ..ResolveKey(tReq.%Get("source"), .tErr)
        If tErr '= "" {
            Do ..%SetStatusCode(400)
            Return ..BuildResponse({ "error": ("source: " _ tErr) })
        }
        Set tTgt = ..ResolveKey(tReq.%Get("target"), .tErr)
        If tErr '= "" {
            Do ..%SetStatusCode(400)
            Return ..BuildResponse({ "error": ("target: " _ tErr) })
        }
        Set tRelation = tReq.%Get("relation", "")
        If tRelation = "" {
            Do ..%SetStatusCode(400)
            Return ..BuildResponse({ "error": "relation is required" })
        }

        Set tSC = ##class(Graph.Store).AddEdge(tSrc, tRelation, tTgt, 1, tReq.%Get("layer", ""))
        If $$$ISERR(tSC) {
            Do ..%SetStatusCode(500)
            Return ..BuildResponse({ "error": ($System.Status.GetErrorText(tSC)) })
        }

        Set tResponse = {}
        Set tResponse.ok = 1
        Set tResponse.source = ..NodeJSON(tSrc)
        Set tResponse.relation = tRelation
        Set tResponse.target = ..NodeJSON(tTgt)
        Return ..BuildResponse(tResponse)
    } Catch ex {
        Do ..%SetStatusCode(500)
        Return ..BuildResponse({ "error": (ex.DisplayString()) })
    }
}

/// Remove a data-layer edge source --relation--> target (Graph.Store.RemoveEdge).<br/>
/// body: { source:{class,id}, relation, target:{class,id} }
ClassMethod RemoveEdge(body As %Stream.Object) As %Stream.Object
{
    Do ..%SetStatusCode(200)
    Do ..%SetContentType("application/json")
    Try {
        Set tReq = ..ReadBody(body)
        Set tSrc = ..ResolveKey(tReq.%Get("source"), .tErr)
        If tErr '= "" {
            Do ..%SetStatusCode(400)
            Return ..BuildResponse({ "error": ("source: " _ tErr) })
        }
        Set tTgt = ..ResolveKey(tReq.%Get("target"), .tErr)
        If tErr '= "" {
            Do ..%SetStatusCode(400)
            Return ..BuildResponse({ "error": ("target: " _ tErr) })
        }
        Set tRelation = tReq.%Get("relation", "")
        If tRelation = "" {
            Do ..%SetStatusCode(400)
            Return ..BuildResponse({ "error": "relation is required" })
        }

        Set tSC = ##class(Graph.Store).RemoveEdge(tSrc, tRelation, tTgt, 1, tReq.%Get("layer", ""))
        If $$$ISERR(tSC) {
            Do ..%SetStatusCode(500)
            Return ..BuildResponse({ "error": ($System.Status.GetErrorText(tSC)) })
        }

        Set tResponse = {}
        Set tResponse.ok = 1
        Set tResponse.source = ..NodeJSON(tSrc)
        Set tResponse.relation = tRelation
        Set tResponse.target = ..NodeJSON(tTgt)
        Return ..BuildResponse(tResponse)
    } Catch ex {
        Do ..%SetStatusCode(500)
        Return ..BuildResponse({ "error": (ex.DisplayString()) })
    }
}

}
