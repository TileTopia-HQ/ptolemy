-- Create convenience view "features" showing the latest version of each feature per branch.
-- This resolves the feature_versions temporal model into a flat queryable table.

CREATE OR REPLACE VIEW features AS
WITH branch_chains AS (
    -- For each branch, get all changesets in its history
    SELECT b.id as branch_id, c.id as changeset_id
    FROM branches b
    JOIN changesets c ON c.branch_id = b.id
),
latest_versions AS (
    SELECT DISTINCT ON (bc.branch_id, fv.feature_id)
        fv.feature_id AS id,
        bc.branch_id,
        fv.dataset_id,
        fv.operation,
        fv.geometry,
        fv.properties,
        fv.created_at
    FROM feature_versions fv
    JOIN branch_chains bc ON fv.changeset_id = bc.changeset_id
    ORDER BY bc.branch_id, fv.feature_id, fv.created_at DESC
)
SELECT id, branch_id, dataset_id, geometry, properties, created_at
FROM latest_versions
WHERE operation != 'delete';

-- Add embedding column (pgvector) if the extension is available
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vector') THEN
        EXECUTE 'ALTER TABLE feature_versions ADD COLUMN IF NOT EXISTS embedding vector(256)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fv_embedding ON feature_versions USING ivfflat (embedding vector_cosine_ops)';
    END IF;
END $$;

-- Add h3_index column if h3 extension is available
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'h3') THEN
        EXECUTE 'ALTER TABLE feature_versions ADD COLUMN IF NOT EXISTS h3_index h3index';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fv_h3 ON feature_versions(h3_index)';
    END IF;
END $$;
