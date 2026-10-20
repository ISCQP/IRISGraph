/// Graph REST API specification (spec-first / OpenAPI).
/// Exposes the Graph.Tools traversals plus Graph.Store data-layer edge writes as HTTP endpoints.
/// The implementation lives in Graph.REST.impl.
/// Author: QP
/// Version: 1.0
/// Last Modified Date: 2026/07/26
Class Graph.REST.spec Extends %REST.Spec [ ProcedureBlock ]
{

Parameter HandleCorsRequest = 1;

XData OpenAPI [ MimeType = application/json ]
{
{
  "swagger": "2.0",
  "schemes": [ "http" ],
  "securityDefinitions": {
    "basicAuth": { "type": "basic" }
  },
  "security": [ { "basicAuth": [] } ],
  "info": {
    "title": "Graph Query API",
    "description": "Property-graph traversal over ^GraphData (single-hop, multi-hop, shortest-path, BFS), plus data-layer edge writes (add/remove). Not backed by any SQL table.",
    "version": "1.0",
    "x-ISC_Namespace": "NEHR"
  },
  "basePath": "/api/graph",
  "definitions": {
    "NodeRef": {
      "type": "object",
      "description": "A graph node. Provide either 'id' (internal object id) or 'no' (business number, requires GetOIDByNO on the class).",
      "required": [ "class" ],
      "properties": {
        "class": { "type": "string", "description": "Full persistent class name, e.g. Test.Customer" },
        "id":    { "type": "string", "description": "Internal object id" },
        "no":    { "type": "string", "description": "Business number (resolved via <class>.GetOIDByNO)" }
      }
    },
    "NodeKey": {
      "type": "object",
      "description": "A generic data-layer node key. Maps to $ListBuild(id, class); no GetOIDByNO resolution.",
      "required": [ "class", "id" ],
      "properties": {
        "class": { "type": "string", "description": "Node type, e.g. Knowledge / Entity (2nd element of the key)" },
        "id":    { "type": "string", "description": "Node identifier (1st element of the key)" }
      }
    }
  },
  "paths": {
    "/singlehop": {
      "post": {
        "summary": "Single-hop neighbours of a node",
        "tags": [ "Graph" ],
        "operationId": "SingleHop",
        "x-ISC_CORS": true,
        "x-ISC_ServiceMethod": "SingleHop",
        "parameters": [
          {
            "in": "body",
            "name": "body",
            "description": "Single-hop query payload",
            "schema": {
              "type": "object",
              "required": [ "node" ],
              "properties": {
                "node":     { "$ref": "#/definitions/NodeRef" },
                "relation": { "type": "string", "description": "Relation filter; empty = all; comma-separated = multiple", "default": "" },
                "inverse":  { "type": "integer", "description": "0 = outgoing edges (node is source), 1 = incoming edges (node is target)", "default": 0 },
                "layers":   { "type": "string", "description": "Comma-separated graph layers to read (union); empty = default view (Core,User)", "default": "" }
              }
            }
          }
        ],
        "responses": { "200": { "description": "Matching edges" } }
      }
    },
    "/multihop": {
      "post": {
        "summary": "Multi-hop traversal along an ordered relation path",
        "tags": [ "Graph" ],
        "operationId": "MultiHop",
        "x-ISC_CORS": true,
        "x-ISC_ServiceMethod": "MultiHop",
        "parameters": [
          {
            "in": "body",
            "name": "body",
            "description": "Multi-hop query payload",
            "schema": {
              "type": "object",
              "required": [ "node", "relations" ],
              "properties": {
                "node": { "$ref": "#/definitions/NodeRef" },
                "relations": {
                  "type": "array",
                  "description": "Ordered relation steps",
                  "items": {
                    "type": "object",
                    "required": [ "relation" ],
                    "properties": {
                      "relation": { "type": "string" },
                      "inverse":  { "type": "integer", "default": 0 }
                    }
                  }
                },
                "layers": { "type": "string", "description": "Comma-separated graph layers to read (union); empty = default view", "default": "" }
              }
            }
          }
        ],
        "responses": { "200": { "description": "Endpoints reached by the relation path" } }
      }
    },
    "/shortestpath": {
      "post": {
        "summary": "Shortest path between two nodes",
        "tags": [ "Graph" ],
        "operationId": "ShortestPath",
        "x-ISC_CORS": true,
        "x-ISC_ServiceMethod": "ShortestPath",
        "parameters": [
          {
            "in": "body",
            "name": "body",
            "description": "Shortest-path query payload",
            "schema": {
              "type": "object",
              "required": [ "start", "end" ],
              "properties": {
                "start": { "$ref": "#/definitions/NodeRef" },
                "end":   { "$ref": "#/definitions/NodeRef" },
                "layers": { "type": "string", "description": "Comma-separated graph layers to read (union); empty = default view", "default": "" }
              }
            }
          }
        ],
        "responses": { "200": { "description": "Ordered path steps (empty if unreachable)" } }
      }
    },
    "/bfs": {
      "post": {
        "summary": "Breadth-first traversal with a depth limit",
        "tags": [ "Graph" ],
        "operationId": "BFS",
        "x-ISC_CORS": true,
        "x-ISC_ServiceMethod": "BFS",
        "parameters": [
          {
            "in": "body",
            "name": "body",
            "description": "BFS query payload",
            "schema": {
              "type": "object",
              "required": [ "node" ],
              "properties": {
                "node":     { "$ref": "#/definitions/NodeRef" },
                "maxDepth": { "type": "integer", "description": "Maximum number of hops", "default": 3 },
                "layers":   { "type": "string", "description": "Comma-separated graph layers to read (union); empty = default view", "default": "" }
              }
            }
          }
        ],
        "responses": { "200": { "description": "Edges discovered within maxDepth hops" } }
      }
    },
    "/bfsparallel": {
      "post": {
        "summary": "Parallel breadth-first traversal (multi-process, very large graphs)",
        "description": "Semantically identical to /bfs; expands each frontier level with %SYSTEM.WorkMgr worker processes. For very large / high-fan-out graphs.",
        "tags": [ "Graph" ],
        "operationId": "BFSParallel",
        "x-ISC_CORS": true,
        "x-ISC_ServiceMethod": "BFSParallel",
        "parameters": [
          {
            "in": "body",
            "name": "body",
            "description": "Parallel BFS query payload",
            "schema": {
              "type": "object",
              "required": [ "node" ],
              "properties": {
                "node":     { "$ref": "#/definitions/NodeRef" },
                "maxDepth": { "type": "integer", "description": "Maximum number of hops", "default": 3 },
                "workers":  { "type": "integer", "description": "Parallel work units per level (<=0 = default 8)", "default": 0 },
                "layers":   { "type": "string", "description": "Comma-separated graph layers to read (union); empty = default view", "default": "" }
              }
            }
          }
        ],
        "responses": { "200": { "description": "Edges discovered within maxDepth hops" } }
      }
    },
    "/addedge": {
      "post": {
        "summary": "Add a data-layer edge source --relation--> target",
        "description": "Writes a low-level edge via Graph.Store.AddEdge (maintains ^GraphData.OUT and ^GraphData.IN). For synthetic / virtual nodes not backed by a persistent class.",
        "tags": [ "Graph" ],
        "operationId": "AddEdge",
        "x-ISC_CORS": true,
        "x-ISC_ServiceMethod": "AddEdge",
        "parameters": [
          {
            "in": "body",
            "name": "body",
            "description": "Edge to add",
            "schema": {
              "type": "object",
              "required": [ "source", "relation", "target" ],
              "properties": {
                "source":   { "$ref": "#/definitions/NodeKey" },
                "relation": { "type": "string", "description": "Edge type, e.g. MENTIONS" },
                "target":   { "$ref": "#/definitions/NodeKey" },
                "layer":    { "type": "string", "description": "Target graph layer; empty = default write layer (User). Read-only layers reject writes.", "default": "" }
              }
            }
          }
        ],
        "responses": { "200": { "description": "Edge added" } }
      }
    },
    "/removeedge": {
      "post": {
        "summary": "Remove a data-layer edge source --relation--> target",
        "description": "Removes a low-level edge via Graph.Store.RemoveEdge (removes ^GraphData.OUT and ^GraphData.IN).",
        "tags": [ "Graph" ],
        "operationId": "RemoveEdge",
        "x-ISC_CORS": true,
        "x-ISC_ServiceMethod": "RemoveEdge",
        "parameters": [
          {
            "in": "body",
            "name": "body",
            "description": "Edge to remove",
            "schema": {
              "type": "object",
              "required": [ "source", "relation", "target" ],
              "properties": {
                "source":   { "$ref": "#/definitions/NodeKey" },
                "relation": { "type": "string", "description": "Edge type, e.g. MENTIONS" },
                "target":   { "$ref": "#/definitions/NodeKey" },
                "layer":    { "type": "string", "description": "Graph layer holding the edge; empty = default write layer (User)", "default": "" }
              }
            }
          }
        ],
        "responses": { "200": { "description": "Edge removed" } }
      }
    }
  }
}
}

}
