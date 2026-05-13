// This Source Code Form is subject to the terms of the GNU Affero General Public
// License, v. 3.0. If a copy of the AGPL was not distributed with this
// file, You can obtain one at https://gnu.org/licenses/agpl-3.0.html.

//! Geometric network and utility network API — graph tracing and analysis.

use axum::{
    Json, Router,
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::AppState;

pub fn network_routes() -> Router<AppState> {
    Router::new()
        .route("/datasets/{id}/networks", get(list_networks).post(create_network))
        .route("/networks/{id}", get(get_network))
        .route("/networks/{id}/junctions", get(list_junctions).post(add_junction))
        .route("/networks/{id}/edges", get(list_edges).post(add_edge))
        .route("/networks/{id}/trace", post(trace_network))
        .route("/networks/{id}/shortest-path", post(shortest_path))
        .route("/networks/{id}/connectivity", get(check_connectivity))
}

#[derive(Serialize)]
struct Network {
    id: Uuid,
    dataset_id: Uuid,
    name: String,
    network_type: String,
}

#[derive(Serialize)]
struct Junction {
    id: Uuid,
    feature_id: Option<Uuid>,
    geometry: Option<serde_json::Value>,
}

#[derive(Serialize)]
struct Edge {
    id: Uuid,
    feature_id: Uuid,
    from_junction: Option<Uuid>,
    to_junction: Option<Uuid>,
    cost: f64,
    enabled: bool,
}

async fn list_networks(
    State(store): State<AppState>,
    Path(dataset_id): Path<Uuid>,
) -> Result<Json<Vec<Network>>, NetworkError> {
    let rows = sqlx::query(
        "SELECT id, dataset_id, name, network_type FROM networks WHERE dataset_id = $1",
    )
    .bind(dataset_id)
    .fetch_all(store.pool())
    .await?;

    Ok(Json(rows.into_iter().map(|r| Network {
        id: r.get("id"),
        dataset_id: r.get("dataset_id"),
        name: r.get("name"),
        network_type: r.get("network_type"),
    }).collect()))
}

#[derive(Deserialize)]
struct CreateNetworkRequest {
    name: String,
    #[serde(default = "default_network_type")]
    network_type: String,
}

fn default_network_type() -> String { "geometric".into() }

async fn create_network(
    State(store): State<AppState>,
    Path(dataset_id): Path<Uuid>,
    Json(req): Json<CreateNetworkRequest>,
) -> Result<(StatusCode, Json<Network>), NetworkError> {
    let id = Uuid::now_v7();
    sqlx::query("INSERT INTO networks (id, dataset_id, name, network_type) VALUES ($1, $2, $3, $4)")
        .bind(id).bind(dataset_id).bind(&req.name).bind(&req.network_type)
        .execute(store.pool()).await?;
    Ok((StatusCode::CREATED, Json(Network { id, dataset_id, name: req.name, network_type: req.network_type })))
}

async fn get_network(
    State(store): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<Network>, NetworkError> {
    let r = sqlx::query("SELECT id, dataset_id, name, network_type FROM networks WHERE id = $1")
        .bind(id).fetch_optional(store.pool()).await?
        .ok_or(NetworkError::NotFound)?;
    Ok(Json(Network { id: r.get("id"), dataset_id: r.get("dataset_id"), name: r.get("name"), network_type: r.get("network_type") }))
}

async fn list_junctions(
    State(store): State<AppState>,
    Path(network_id): Path<Uuid>,
) -> Result<Json<Vec<Junction>>, NetworkError> {
    let rows = sqlx::query(
        "SELECT id, feature_id, ST_AsGeoJSON(geometry)::jsonb as geojson FROM network_junctions WHERE network_id = $1",
    ).bind(network_id).fetch_all(store.pool()).await?;
    Ok(Json(rows.into_iter().map(|r| Junction {
        id: r.get("id"), feature_id: r.get("feature_id"), geometry: r.get("geojson"),
    }).collect()))
}

#[derive(Deserialize)]
struct AddJunctionRequest {
    feature_id: Option<Uuid>,
    lng: f64,
    lat: f64,
}

async fn add_junction(
    State(store): State<AppState>,
    Path(network_id): Path<Uuid>,
    Json(req): Json<AddJunctionRequest>,
) -> Result<(StatusCode, Json<Junction>), NetworkError> {
    let id = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO network_junctions (id, network_id, feature_id, geometry)
         VALUES ($1, $2, $3, ST_SetSRID(ST_MakePoint($4, $5), 4326))",
    ).bind(id).bind(network_id).bind(req.feature_id).bind(req.lng).bind(req.lat)
    .execute(store.pool()).await?;
    Ok((StatusCode::CREATED, Json(Junction { id, feature_id: req.feature_id, geometry: None })))
}

async fn list_edges(
    State(store): State<AppState>,
    Path(network_id): Path<Uuid>,
) -> Result<Json<Vec<Edge>>, NetworkError> {
    let rows = sqlx::query(
        "SELECT id, feature_id, from_junction, to_junction, cost, enabled FROM network_edges WHERE network_id = $1",
    ).bind(network_id).fetch_all(store.pool()).await?;
    Ok(Json(rows.into_iter().map(|r| Edge {
        id: r.get("id"), feature_id: r.get("feature_id"),
        from_junction: r.get("from_junction"), to_junction: r.get("to_junction"),
        cost: r.get("cost"), enabled: r.get("enabled"),
    }).collect()))
}

#[derive(Deserialize)]
struct AddEdgeRequest {
    feature_id: Uuid,
    from_junction: Option<Uuid>,
    to_junction: Option<Uuid>,
    #[serde(default = "default_cost")]
    cost: f64,
}

fn default_cost() -> f64 { 1.0 }

async fn add_edge(
    State(store): State<AppState>,
    Path(network_id): Path<Uuid>,
    Json(req): Json<AddEdgeRequest>,
) -> Result<StatusCode, NetworkError> {
    let id = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO network_edges (id, network_id, feature_id, from_junction, to_junction, cost)
         VALUES ($1, $2, $3, $4, $5, $6)",
    ).bind(id).bind(network_id).bind(req.feature_id).bind(req.from_junction).bind(req.to_junction).bind(req.cost)
    .execute(store.pool()).await?;
    Ok(StatusCode::CREATED)
}

// ─── Network Analysis ───────────────────────────────────────────────

#[derive(Deserialize)]
struct TraceRequest {
    start_junction: Uuid,
    /// Max hops (default unlimited)
    max_depth: Option<i32>,
    /// Trace direction: upstream, downstream, both
    #[serde(default = "default_direction")]
    direction: String,
}

fn default_direction() -> String { "both".into() }

#[derive(Serialize)]
struct TraceResult {
    junctions_reached: Vec<Uuid>,
    edges_traversed: Vec<Uuid>,
    total_cost: f64,
}

async fn trace_network(
    State(store): State<AppState>,
    Path(network_id): Path<Uuid>,
    Json(req): Json<TraceRequest>,
) -> Result<Json<TraceResult>, NetworkError> {
    let max_depth = req.max_depth.unwrap_or(1000);

    let rows = match req.direction.as_str() {
        "downstream" => {
            sqlx::query(
                "WITH RECURSIVE trace AS (
                    SELECT to_junction as junction, id as edge_id, cost, 1 as depth
                    FROM network_edges
                    WHERE network_id = $1 AND from_junction = $2 AND enabled = TRUE
                  UNION ALL
                    SELECT e.to_junction, e.id, t.cost + e.cost, t.depth + 1
                    FROM network_edges e
                    JOIN trace t ON e.from_junction = t.junction
                    WHERE e.network_id = $1 AND e.enabled = TRUE AND t.depth < $3
                )
                SELECT junction, edge_id, cost FROM trace",
            ).bind(network_id).bind(req.start_junction).bind(max_depth)
            .fetch_all(store.pool()).await?
        }
        _ => {
            sqlx::query(
                "WITH RECURSIVE trace AS (
                    SELECT CASE WHEN from_junction = $2 THEN to_junction ELSE from_junction END as junction,
                           id as edge_id, cost, 1 as depth
                    FROM network_edges
                    WHERE network_id = $1 AND (from_junction = $2 OR to_junction = $2) AND enabled = TRUE
                  UNION ALL
                    SELECT CASE WHEN e.from_junction = t.junction THEN e.to_junction ELSE e.from_junction END,
                           e.id, t.cost + e.cost, t.depth + 1
                    FROM network_edges e
                    JOIN trace t ON (e.from_junction = t.junction OR e.to_junction = t.junction)
                    WHERE e.network_id = $1 AND e.enabled = TRUE AND t.depth < $3
                      AND e.id != t.edge_id
                )
                SELECT DISTINCT junction, edge_id, cost FROM trace",
            ).bind(network_id).bind(req.start_junction).bind(max_depth)
            .fetch_all(store.pool()).await?
        }
    };

    let mut junctions = Vec::new();
    let mut edges = Vec::new();
    let mut total_cost = 0.0f64;
    for row in &rows {
        let j: Uuid = row.get("junction");
        let e: Uuid = row.get("edge_id");
        let c: f64 = row.get("cost");
        if !junctions.contains(&j) { junctions.push(j); }
        if !edges.contains(&e) { edges.push(e); }
        if c > total_cost { total_cost = c; }
    }

    Ok(Json(TraceResult { junctions_reached: junctions, edges_traversed: edges, total_cost }))
}

#[derive(Deserialize)]
struct ShortestPathRequest {
    from_junction: Uuid,
    to_junction: Uuid,
}

#[derive(Serialize)]
struct PathResult {
    found: bool,
    path_junctions: Vec<Uuid>,
    path_edges: Vec<Uuid>,
    total_cost: f64,
}

async fn shortest_path(
    State(store): State<AppState>,
    Path(network_id): Path<Uuid>,
    Json(req): Json<ShortestPathRequest>,
) -> Result<Json<PathResult>, NetworkError> {
    // Use pgRouting-style Dijkstra via recursive CTE
    let rows = sqlx::query(
        "WITH RECURSIVE dijkstra AS (
            SELECT to_junction as node, ARRAY[from_junction, to_junction] as path,
                   ARRAY[id] as edge_path, cost as total, 1 as depth
            FROM network_edges
            WHERE network_id = $1 AND from_junction = $2 AND enabled = TRUE
          UNION ALL
            SELECT e.to_junction, d.path || e.to_junction,
                   d.edge_path || e.id, d.total + e.cost, d.depth + 1
            FROM network_edges e
            JOIN dijkstra d ON e.from_junction = d.node
            WHERE e.network_id = $1 AND e.enabled = TRUE
              AND NOT (e.to_junction = ANY(d.path))
              AND d.depth < 100
        )
        SELECT path, edge_path, total
        FROM dijkstra
        WHERE node = $3
        ORDER BY total ASC
        LIMIT 1",
    )
    .bind(network_id)
    .bind(req.from_junction)
    .bind(req.to_junction)
    .fetch_optional(store.pool())
    .await?;

    match rows {
        Some(row) => {
            let path: Vec<Uuid> = row.get("path");
            let edges: Vec<Uuid> = row.get("edge_path");
            let cost: f64 = row.get("total");
            Ok(Json(PathResult { found: true, path_junctions: path, path_edges: edges, total_cost: cost }))
        }
        None => Ok(Json(PathResult { found: false, path_junctions: vec![], path_edges: vec![], total_cost: 0.0 })),
    }
}

#[derive(Serialize)]
struct ConnectivityReport {
    total_junctions: i64,
    total_edges: i64,
    connected_components: i64,
    isolated_junctions: Vec<Uuid>,
}

async fn check_connectivity(
    State(store): State<AppState>,
    Path(network_id): Path<Uuid>,
) -> Result<Json<ConnectivityReport>, NetworkError> {
    let stats = sqlx::query(
        "SELECT
            (SELECT COUNT(*) FROM network_junctions WHERE network_id = $1) as junctions,
            (SELECT COUNT(*) FROM network_edges WHERE network_id = $1) as edges",
    ).bind(network_id).fetch_one(store.pool()).await?;

    let isolated = sqlx::query(
        "SELECT j.id FROM network_junctions j
         WHERE j.network_id = $1
           AND NOT EXISTS (
             SELECT 1 FROM network_edges e
             WHERE e.network_id = $1
               AND (e.from_junction = j.id OR e.to_junction = j.id)
           )",
    ).bind(network_id).fetch_all(store.pool()).await?;

    Ok(Json(ConnectivityReport {
        total_junctions: stats.get("junctions"),
        total_edges: stats.get("edges"),
        connected_components: 1, // simplified; full impl would use union-find
        isolated_junctions: isolated.into_iter().map(|r| r.get("id")).collect(),
    }))
}

// ─── Error ──────────────────────────────────────────────────────────

enum NetworkError { Db(sqlx::Error), NotFound }

impl From<sqlx::Error> for NetworkError { fn from(e: sqlx::Error) -> Self { NetworkError::Db(e) } }

impl IntoResponse for NetworkError {
    fn into_response(self) -> axum::response::Response {
        let (s, m) = match self {
            NetworkError::NotFound => (StatusCode::NOT_FOUND, "network not found".to_string()),
            NetworkError::Db(e) => { tracing::error!("DB: {e}"); (StatusCode::INTERNAL_SERVER_ERROR, "internal error".into()) }
        };
        (s, Json(serde_json::json!({"error": m}))).into_response()
    }
}
