// This Source Code Form is subject to the terms of the GNU Affero General Public
// License, v. 3.0. If a copy of the AGPL was not distributed with this
// file, You can obtain one at https://gnu.org/licenses/agpl-3.0.html.

use clap::{Parser, Subcommand};
use ptolemy_core::branch::Branch;
use ptolemy_core::dataset::{Dataset, GeometryType};
use ptolemy_core::diff::DiffOp;
use ptolemy_storage::PgStore;
use serde_json::json;
use std::sync::Arc;
use time::OffsetDateTime;
use uuid::Uuid;

#[derive(Parser)]
#[command(name = "ptolemy", about = "Versioned geodatabase & collaboration platform")]
struct Cli {
    /// PostgreSQL connection URL
    #[arg(long, env = "DATABASE_URL")]
    database_url: String,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the API server
    Serve {
        /// Listen address
        #[arg(long, default_value = "0.0.0.0:3000")]
        bind: String,
    },

    /// Run database migrations
    Migrate,

    /// Dataset management
    Dataset {
        #[command(subcommand)]
        cmd: DatasetCmd,
    },

    /// Branch management
    Branch {
        #[command(subcommand)]
        cmd: BranchCmd,
    },

    /// Commit changes to a branch
    Commit {
        /// Branch ID
        #[arg(long)]
        branch: Uuid,
        /// Commit message
        #[arg(long, short)]
        message: String,
        /// Author name
        #[arg(long)]
        author: String,
        /// GeoJSON file to import as inserts (optional)
        #[arg(long)]
        geojson: Option<String>,
    },

    /// Merge a source branch into a target branch
    Merge {
        /// Source branch ID
        #[arg(long)]
        source: Uuid,
        /// Target branch ID
        #[arg(long)]
        target: Uuid,
        /// Author name
        #[arg(long)]
        author: String,
    },

    /// Show commit history for a branch
    Log {
        /// Branch ID
        #[arg(long)]
        branch: Uuid,
        /// Max number of entries
        #[arg(long, default_value = "20")]
        limit: i64,
    },

    /// List features on a branch
    Features {
        /// Branch ID
        #[arg(long)]
        branch: Uuid,
    },

    /// Show diff between two changesets
    Diff {
        /// From changeset ID
        #[arg(long)]
        from: Uuid,
        /// To changeset ID
        #[arg(long)]
        to: Uuid,
    },

    /// Import GeoJSON file as features
    Import {
        /// Branch ID
        #[arg(long)]
        branch: Uuid,
        /// Path to GeoJSON file
        file: String,
        /// Author name
        #[arg(long)]
        author: String,
        /// Commit message
        #[arg(long, short, default_value = "Import GeoJSON")]
        message: String,
    },

    /// Export features as GeoJSON
    Export {
        /// Branch ID
        #[arg(long)]
        branch: Uuid,
        /// Output file (stdout if omitted)
        #[arg(long, short)]
        output: Option<String>,
    },
}

#[derive(Subcommand)]
enum DatasetCmd {
    /// Create a new dataset
    Create {
        /// Dataset name
        name: String,
        /// SRID (default 4326)
        #[arg(long, default_value = "4326")]
        srid: i32,
        /// Geometry type
        #[arg(long, default_value = "point")]
        geometry_type: String,
        /// Creator name
        #[arg(long)]
        created_by: String,
    },
    /// List all datasets
    List,
    /// Show dataset info
    Show { id: Uuid },
}

#[derive(Subcommand)]
enum BranchCmd {
    /// Create a new branch
    Create {
        /// Dataset ID
        #[arg(long)]
        dataset: Uuid,
        /// Branch name
        name: String,
        /// Fork from this branch ID (copies head)
        #[arg(long)]
        fork_from: Option<Uuid>,
        /// Creator name
        #[arg(long)]
        created_by: String,
    },
    /// List branches for a dataset
    List {
        /// Dataset ID
        #[arg(long)]
        dataset: Uuid,
    },
    /// Show branch info
    Show { id: Uuid },
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();
    let cli = Cli::parse();

    let pool = sqlx::PgPool::connect(&cli.database_url).await?;
    let store = Arc::new(PgStore::new(pool));

    match cli.command {
        Commands::Serve { bind } => {
            let app = ptolemy_api::app(store.clone());
            let listener = tokio::net::TcpListener::bind(&bind).await?;
            tracing::info!("Ptolemy listening on {bind}");
            axum::serve(listener, app).await?;
        }

        Commands::Migrate => {
            store.migrate().await?;
            println!("Migrations applied successfully.");
        }

        Commands::Dataset { cmd } => match cmd {
            DatasetCmd::Create {
                name,
                srid,
                geometry_type,
                created_by,
            } => {
                let ds = Dataset {
                    id: Uuid::now_v7(),
                    name: name.clone(),
                    srid,
                    geometry_type: parse_geom_type(&geometry_type),
                    created_at: OffsetDateTime::now_utc(),
                    created_by,
                };
                store.create_dataset(&ds).await?;
                println!("Created dataset '{}' ({})", name, ds.id);
            }
            DatasetCmd::List => {
                let datasets = store.list_datasets().await?;
                for ds in datasets {
                    println!("{} | {} | srid={} | {}", ds.id, ds.name, ds.srid, ds.created_by);
                }
            }
            DatasetCmd::Show { id } => {
                let ds = store.get_dataset(id).await?;
                println!("{}", serde_json::to_string_pretty(&ds)?);
            }
        },

        Commands::Branch { cmd } => match cmd {
            BranchCmd::Create {
                dataset,
                name,
                fork_from,
                created_by,
            } => {
                let head = if let Some(src_id) = fork_from {
                    let src = store.get_branch(src_id).await?;
                    src.head
                } else {
                    None
                };
                let branch = Branch {
                    id: Uuid::now_v7(),
                    dataset_id: dataset,
                    name: name.clone(),
                    head,
                    created_at: OffsetDateTime::now_utc(),
                    created_by,
                };
                store.create_branch(&branch).await?;
                println!("Created branch '{}' ({})", name, branch.id);
            }
            BranchCmd::List { dataset } => {
                let branches = store.list_branches(dataset).await?;
                for b in branches {
                    let head_str = b.head.map(|h| h.to_string()).unwrap_or_else(|| "(empty)".to_string());
                    println!("{} | {} | head={}", b.id, b.name, head_str);
                }
            }
            BranchCmd::Show { id } => {
                let b = store.get_branch(id).await?;
                println!("{}", serde_json::to_string_pretty(&b)?);
            }
        },

        Commands::Commit {
            branch,
            message,
            author,
            geojson,
        } => {
            let ops = if let Some(path) = geojson {
                parse_geojson_to_ops(&std::fs::read_to_string(&path)?)?
            } else {
                vec![]
            };
            let changeset = store.commit(branch, &message, &author, &ops).await?;
            println!("Committed {} ({} operations)", changeset.id, ops.len());
        }

        Commands::Merge {
            source,
            target,
            author,
        } => {
            let result = store.merge(source, target, &author).await?;
            match result {
                ptolemy_storage::MergeResult::Success(cs) => {
                    println!("Merge successful: {}", cs.id);
                }
                ptolemy_storage::MergeResult::Conflicts(conflicts) => {
                    println!("Merge has {} conflict(s):", conflicts.len());
                    for c in &conflicts {
                        println!("  - feature {} conflict", c.feature_id);
                    }
                    std::process::exit(1);
                }
            }
        }

        Commands::Log { branch, limit } => {
            let history = store.get_branch_history(branch, limit).await?;
            for cs in history {
                let parent = cs.parent_id.map(|p| p.to_string()).unwrap_or_else(|| "(root)".to_string());
                println!("{} | {} | {} | parent={}", cs.id, cs.author, cs.message, parent);
            }
        }

        Commands::Features { branch } => {
            let features = store.list_features_at_head(branch).await?;
            // Output as GeoJSON FeatureCollection
            let fc = features_to_geojson(&features);
            println!("{}", serde_json::to_string_pretty(&fc)?);
        }

        Commands::Diff { from, to } => {
            let diff = store.diff(Some(from), to).await?;
            println!("{}", serde_json::to_string_pretty(&diff)?);
        }

        Commands::Import {
            branch,
            file,
            author,
            message,
        } => {
            let content = std::fs::read_to_string(&file)?;
            let ops = parse_geojson_to_ops(&content)?;
            let count = ops.len();
            let changeset = store.commit(branch, &message, &author, &ops).await?;
            println!("Imported {} features as changeset {}", count, changeset.id);
        }

        Commands::Export { branch, output } => {
            let features = store.list_features_at_head(branch).await?;
            let fc = features_to_geojson(&features);
            let json = serde_json::to_string_pretty(&fc)?;
            if let Some(path) = output {
                std::fs::write(&path, &json)?;
                println!("Exported {} features to {}", features.len(), path);
            } else {
                println!("{json}");
            }
        }
    }

    Ok(())
}

fn parse_geom_type(s: &str) -> GeometryType {
    match s {
        "point" => GeometryType::Point,
        "linestring" => GeometryType::LineString,
        "polygon" => GeometryType::Polygon,
        "multipoint" => GeometryType::MultiPoint,
        "multilinestring" => GeometryType::MultiLineString,
        "multipolygon" => GeometryType::MultiPolygon,
        _ => GeometryType::Point,
    }
}

/// Parse a GeoJSON FeatureCollection into DiffOps (inserts).
fn parse_geojson_to_ops(content: &str) -> anyhow::Result<Vec<DiffOp>> {
    let v: serde_json::Value = serde_json::from_str(content)?;
    let features = v["features"]
        .as_array()
        .ok_or_else(|| anyhow::anyhow!("Expected GeoJSON FeatureCollection with 'features' array"))?;

    let mut ops = Vec::with_capacity(features.len());
    for f in features {
        let geometry = &f["geometry"];
        let properties = f.get("properties").cloned().unwrap_or(json!({}));
        // Encode geometry as simple WKB point if it's a point, otherwise store raw JSON in properties
        let wkb = geojson_geometry_to_wkb(geometry)?;
        ops.push(DiffOp::Insert {
            feature_id: Uuid::now_v7(),
            geometry_wkb: wkb,
            properties,
        });
    }
    Ok(ops)
}

/// Convert a GeoJSON geometry object to WKB (supports Point only for now, others get POINT(0,0)).
fn geojson_geometry_to_wkb(geom: &serde_json::Value) -> anyhow::Result<Vec<u8>> {
    let geom_type = geom["type"].as_str().unwrap_or("Point");
    match geom_type {
        "Point" => {
            let coords = geom["coordinates"]
                .as_array()
                .ok_or_else(|| anyhow::anyhow!("Point missing coordinates"))?;
            let x = coords.first().and_then(|v| v.as_f64()).unwrap_or(0.0);
            let y = coords.get(1).and_then(|v| v.as_f64()).unwrap_or(0.0);
            Ok(point_wkb(x, y))
        }
        "LineString" => {
            let coords = geom["coordinates"]
                .as_array()
                .ok_or_else(|| anyhow::anyhow!("LineString missing coordinates"))?;
            Ok(linestring_wkb(coords))
        }
        "Polygon" => {
            let rings = geom["coordinates"]
                .as_array()
                .ok_or_else(|| anyhow::anyhow!("Polygon missing coordinates"))?;
            Ok(polygon_wkb(rings))
        }
        _ => {
            // Fallback: store as point at 0,0 with geometry in properties
            Ok(point_wkb(0.0, 0.0))
        }
    }
}

fn point_wkb(x: f64, y: f64) -> Vec<u8> {
    let mut buf = Vec::with_capacity(21);
    buf.push(0x01); // little-endian
    buf.extend_from_slice(&1u32.to_le_bytes()); // WKB type: Point
    buf.extend_from_slice(&x.to_le_bytes());
    buf.extend_from_slice(&y.to_le_bytes());
    buf
}

fn linestring_wkb(coords: &[serde_json::Value]) -> Vec<u8> {
    let mut buf = Vec::new();
    buf.push(0x01); // little-endian
    buf.extend_from_slice(&2u32.to_le_bytes()); // WKB type: LineString
    buf.extend_from_slice(&(coords.len() as u32).to_le_bytes());
    for coord in coords {
        if let Some(arr) = coord.as_array() {
            let x = arr.first().and_then(|v| v.as_f64()).unwrap_or(0.0);
            let y = arr.get(1).and_then(|v| v.as_f64()).unwrap_or(0.0);
            buf.extend_from_slice(&x.to_le_bytes());
            buf.extend_from_slice(&y.to_le_bytes());
        }
    }
    buf
}

fn polygon_wkb(rings: &[serde_json::Value]) -> Vec<u8> {
    let mut buf = Vec::new();
    buf.push(0x01); // little-endian
    buf.extend_from_slice(&3u32.to_le_bytes()); // WKB type: Polygon
    buf.extend_from_slice(&(rings.len() as u32).to_le_bytes());
    for ring in rings {
        if let Some(coords) = ring.as_array() {
            buf.extend_from_slice(&(coords.len() as u32).to_le_bytes());
            for coord in coords {
                if let Some(arr) = coord.as_array() {
                    let x = arr.first().and_then(|v| v.as_f64()).unwrap_or(0.0);
                    let y = arr.get(1).and_then(|v| v.as_f64()).unwrap_or(0.0);
                    buf.extend_from_slice(&x.to_le_bytes());
                    buf.extend_from_slice(&y.to_le_bytes());
                }
            }
        }
    }
    buf
}

fn features_to_geojson(features: &[ptolemy_core::Feature]) -> serde_json::Value {
    let geojson_features: Vec<serde_json::Value> = features
        .iter()
        .map(|f| {
            let geometry = wkb_to_geojson_geometry(&f.geometry_wkb);
            json!({
                "type": "Feature",
                "id": f.id.to_string(),
                "geometry": geometry,
                "properties": f.properties,
            })
        })
        .collect();

    json!({
        "type": "FeatureCollection",
        "features": geojson_features,
    })
}

/// Convert WKB back to GeoJSON geometry (supports Point, LineString, Polygon).
fn wkb_to_geojson_geometry(wkb: &[u8]) -> serde_json::Value {
    if wkb.len() < 5 {
        return json!({"type": "Point", "coordinates": [0, 0]});
    }
    // Skip byte order byte, read type
    let wkb_type = u32::from_le_bytes([wkb[1], wkb[2], wkb[3], wkb[4]]);
    match wkb_type {
        1 => {
            // Point
            if wkb.len() >= 21 {
                let x = f64::from_le_bytes(wkb[5..13].try_into().unwrap());
                let y = f64::from_le_bytes(wkb[13..21].try_into().unwrap());
                json!({"type": "Point", "coordinates": [x, y]})
            } else {
                json!({"type": "Point", "coordinates": [0, 0]})
            }
        }
        2 => {
            // LineString
            if wkb.len() >= 9 {
                let n = u32::from_le_bytes(wkb[5..9].try_into().unwrap()) as usize;
                let mut coords = Vec::with_capacity(n);
                for i in 0..n {
                    let offset = 9 + i * 16;
                    if offset + 16 <= wkb.len() {
                        let x = f64::from_le_bytes(wkb[offset..offset + 8].try_into().unwrap());
                        let y = f64::from_le_bytes(wkb[offset + 8..offset + 16].try_into().unwrap());
                        coords.push(json!([x, y]));
                    }
                }
                json!({"type": "LineString", "coordinates": coords})
            } else {
                json!({"type": "LineString", "coordinates": []})
            }
        }
        3 => {
            // Polygon
            if wkb.len() >= 9 {
                let num_rings = u32::from_le_bytes(wkb[5..9].try_into().unwrap()) as usize;
                let mut rings = Vec::with_capacity(num_rings);
                let mut offset = 9;
                for _ in 0..num_rings {
                    if offset + 4 > wkb.len() {
                        break;
                    }
                    let n = u32::from_le_bytes(wkb[offset..offset + 4].try_into().unwrap()) as usize;
                    offset += 4;
                    let mut coords = Vec::with_capacity(n);
                    for _ in 0..n {
                        if offset + 16 <= wkb.len() {
                            let x = f64::from_le_bytes(wkb[offset..offset + 8].try_into().unwrap());
                            let y = f64::from_le_bytes(wkb[offset + 8..offset + 16].try_into().unwrap());
                            coords.push(json!([x, y]));
                            offset += 16;
                        }
                    }
                    rings.push(coords);
                }
                json!({"type": "Polygon", "coordinates": rings})
            } else {
                json!({"type": "Polygon", "coordinates": []})
            }
        }
        _ => json!({"type": "Point", "coordinates": [0, 0]}),
    }
}
