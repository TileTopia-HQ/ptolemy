-- Enable third-party PostgreSQL extensions for advanced GIS capabilities.
-- These extensions must be installed on the PostgreSQL server.

-- pgRouting: graph analysis (Dijkstra, A*, TSP, isochrones)
CREATE EXTENSION IF NOT EXISTS pgrouting;

-- PostGIS Topology: native topology primitives
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- SFCGAL: 3D geometry operations (requires PostGIS SFCGAL backend)
CREATE EXTENSION IF NOT EXISTS postgis_sfcgal;

-- h3: Uber H3 hexagonal spatial indexing
CREATE EXTENSION IF NOT EXISTS h3;

-- pg_partman: automatic table partitioning
CREATE EXTENSION IF NOT EXISTS pg_partman;

-- pgvector: vector similarity search
CREATE EXTENSION IF NOT EXISTS vector;

-- pg_trgm: trigram-based fuzzy text search
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- pointcloud: LiDAR/point cloud storage
CREATE EXTENSION IF NOT EXISTS pointcloud;
CREATE EXTENSION IF NOT EXISTS pointcloud_postgis;

-- MobilityDB: moving objects and trajectories
CREATE EXTENSION IF NOT EXISTS mobilitydb;

-- ─── Indexes leveraging new extensions ───────────────────────────────

-- Trigram index on dataset names for fuzzy search
CREATE INDEX IF NOT EXISTS idx_datasets_name_trgm
    ON datasets USING gin (name gin_trgm_ops);

-- Trigram index on catalog metadata keywords
CREATE INDEX IF NOT EXISTS idx_dataset_metadata_keywords_trgm
    ON dataset_metadata USING gin (keywords gin_trgm_ops);

-- ─── pgRouting helper view ───────────────────────────────────────────

-- Create a view that pgRouting functions can consume directly
CREATE OR REPLACE VIEW pgr_network_edges AS
SELECT
    e.id::text::bigint AS id,
    e.from_junction::text::bigint AS source,
    e.to_junction::text::bigint AS target,
    e.cost,
    e.cost AS reverse_cost
FROM network_edges e
WHERE e.enabled = TRUE;

-- ─── Trajectory support (MobilityDB) ────────────────────────────────

CREATE TABLE IF NOT EXISTS trajectories (
    id UUID PRIMARY KEY,
    dataset_id UUID NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
    feature_id UUID REFERENCES features(id) ON DELETE SET NULL,
    name TEXT NOT NULL DEFAULT '',
    trip tgeompoint,
    period tstzspan,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_trajectories_dataset ON trajectories(dataset_id);
CREATE INDEX IF NOT EXISTS idx_trajectories_period ON trajectories USING gist(period);

-- ─── Point cloud support ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS pointcloud_catalogs (
    id UUID PRIMARY KEY,
    dataset_id UUID NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    srid INTEGER NOT NULL DEFAULT 4326,
    schema_xml TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pointcloud_patches (
    id UUID PRIMARY KEY,
    catalog_id UUID NOT NULL REFERENCES pointcloud_catalogs(id) ON DELETE CASCADE,
    pa pcpatch,
    bounds GEOMETRY(Polygon, 4326),
    num_points INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_pc_patches_catalog ON pointcloud_patches(catalog_id);
CREATE INDEX IF NOT EXISTS idx_pc_patches_bounds ON pointcloud_patches USING gist(bounds);

-- ─── Vector embeddings for feature similarity ────────────────────────

ALTER TABLE features ADD COLUMN IF NOT EXISTS embedding vector(256);
CREATE INDEX IF NOT EXISTS idx_features_embedding ON features USING ivfflat (embedding vector_cosine_ops);

-- ─── H3 spatial index columns ────────────────────────────────────────

ALTER TABLE features ADD COLUMN IF NOT EXISTS h3_index h3index;
CREATE INDEX IF NOT EXISTS idx_features_h3 ON features(h3_index);

-- ─── Partitioning setup (pg_partman) ─────────────────────────────────
-- Note: pg_partman manages partition creation automatically.
-- For existing tables, we add partitioning metadata.

SELECT partman.create_parent(
    p_parent_table := 'public.audit_log',
    p_control := 'timestamp',
    p_type := 'range',
    p_interval := '1 month'
);
