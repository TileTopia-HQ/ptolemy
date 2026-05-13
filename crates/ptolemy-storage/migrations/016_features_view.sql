-- Create convenience view "features" showing the latest version of each feature per branch.
-- This resolves the feature_versions temporal model into a flat queryable table.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

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

-- Add embedding and h3 columns to feature_versions (the real table)
ALTER TABLE feature_versions ADD COLUMN IF NOT EXISTS embedding vector(256);
ALTER TABLE feature_versions ADD COLUMN IF NOT EXISTS h3_index h3index;

-- Index for vector similarity on the real table
CREATE INDEX IF NOT EXISTS idx_fv_embedding ON feature_versions USING ivfflat (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS idx_fv_h3 ON feature_versions(h3_index);
