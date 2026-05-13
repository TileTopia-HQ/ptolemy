-- Enable third-party PostgreSQL extensions for advanced GIS capabilities.
-- Extensions that are not installed on the system will be silently skipped.

-- Helper: try to create an extension, skip if not available on this system.
CREATE OR REPLACE FUNCTION _try_create_extension(ext text) RETURNS void AS $$
BEGIN
    EXECUTE format('CREATE EXTENSION IF NOT EXISTS %I', ext);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Extension % not available, skipping: %', ext, SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- Core PostGIS (should always be present)
SELECT _try_create_extension('postgis');
SELECT _try_create_extension('postgis_topology');
SELECT _try_create_extension('postgis_raster');
SELECT _try_create_extension('pgcrypto');
SELECT _try_create_extension('pg_trgm');

-- Optional advanced extensions (skip gracefully if not installed)
SELECT _try_create_extension('pgrouting');
SELECT _try_create_extension('postgis_sfcgal');
SELECT _try_create_extension('h3');
SELECT _try_create_extension('pg_partman');
SELECT _try_create_extension('vector');
SELECT _try_create_extension('pointcloud');
SELECT _try_create_extension('pointcloud_postgis');
SELECT _try_create_extension('mobilitydb');

DROP FUNCTION _try_create_extension(text);

-- ─── Indexes leveraging core extensions ──────────────────────────────

-- Trigram index on dataset names for fuzzy search (pg_trgm)
DO $$ BEGIN
    CREATE INDEX IF NOT EXISTS idx_datasets_name_trgm
        ON datasets USING gin (name gin_trgm_ops);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Skipping trigram index: %', SQLERRM;
END $$;

-- GIN index on metadata keywords array for containment queries
CREATE INDEX IF NOT EXISTS idx_dataset_metadata_keywords
    ON dataset_metadata USING gin (keywords);

-- ─── pgRouting helper view (requires pgrouting + network_edges table) ─

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgrouting')
       AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'network_edges') THEN
        EXECUTE '
            CREATE OR REPLACE VIEW pgr_network_edges AS
            SELECT
                e.id::text::bigint AS id,
                e.from_junction::text::bigint AS source,
                e.to_junction::text::bigint AS target,
                e.cost,
                e.cost AS reverse_cost
            FROM network_edges e
            WHERE e.enabled = TRUE';
    END IF;
END $$;

-- ─── Trajectory support (MobilityDB) ────────────────────────────────

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'mobilitydb') THEN
        EXECUTE '
            CREATE TABLE IF NOT EXISTS trajectories (
                id UUID PRIMARY KEY,
                dataset_id UUID NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
                name TEXT NOT NULL DEFAULT '''',
                trip tgeompoint,
                period tstzspan,
                created_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_trajectories_dataset ON trajectories(dataset_id)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_trajectories_period ON trajectories USING gist(period)';
    ELSE
        -- Fallback: create trajectories table without MobilityDB types
        CREATE TABLE IF NOT EXISTS trajectories (
            id UUID PRIMARY KEY,
            dataset_id UUID NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
            name TEXT NOT NULL DEFAULT '',
            trip JSONB,
            period TSTZRANGE,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS idx_trajectories_dataset ON trajectories(dataset_id);
    END IF;
END $$;

-- ─── Point cloud support ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS pointcloud_catalogs (
    id UUID PRIMARY KEY,
    dataset_id UUID NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    srid INTEGER NOT NULL DEFAULT 4326,
    schema_xml TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pointcloud') THEN
        EXECUTE '
            CREATE TABLE IF NOT EXISTS pointcloud_patches (
                id UUID PRIMARY KEY,
                catalog_id UUID NOT NULL REFERENCES pointcloud_catalogs(id) ON DELETE CASCADE,
                pa pcpatch,
                bounds GEOMETRY(Polygon, 4326),
                num_points INTEGER NOT NULL DEFAULT 0
            )';
    ELSE
        -- Fallback: create without pcpatch type (store as bytea)
        CREATE TABLE IF NOT EXISTS pointcloud_patches (
            id UUID PRIMARY KEY,
            catalog_id UUID NOT NULL REFERENCES pointcloud_catalogs(id) ON DELETE CASCADE,
            pa BYTEA,
            bounds GEOMETRY(Polygon, 4326),
            num_points INTEGER NOT NULL DEFAULT 0
        );
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_pc_patches_catalog ON pointcloud_patches(catalog_id);
CREATE INDEX IF NOT EXISTS idx_pc_patches_bounds ON pointcloud_patches USING gist(bounds);

-- Note: Vector/H3 columns and features view are created in migration 016.
-- Note: pg_partman auto-partitioning is configured by DBA at deployment time
-- for tables that grow large (audit_log, feature_versions).