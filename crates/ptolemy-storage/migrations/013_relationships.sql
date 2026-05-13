-- Relationship classes: define relationships between datasets
CREATE TABLE IF NOT EXISTS relationship_classes (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    origin_dataset_id UUID NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
    destination_dataset_id UUID NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
    cardinality TEXT NOT NULL DEFAULT 'one_to_many',  -- one_to_one, one_to_many, many_to_many
    origin_primary_key TEXT NOT NULL DEFAULT 'id',
    origin_foreign_key TEXT NOT NULL,
    destination_primary_key TEXT NOT NULL DEFAULT 'id',
    destination_foreign_key TEXT,
    forward_label TEXT,
    backward_label TEXT,
    is_composite BOOLEAN NOT NULL DEFAULT FALSE,  -- composite: delete cascades
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Junction table for many-to-many relationships
CREATE TABLE IF NOT EXISTS relationship_records (
    id UUID PRIMARY KEY,
    relationship_class_id UUID NOT NULL REFERENCES relationship_classes(id) ON DELETE CASCADE,
    origin_feature_id UUID NOT NULL,
    destination_feature_id UUID NOT NULL,
    properties JSONB NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_rel_origin ON relationship_records(relationship_class_id, origin_feature_id);
CREATE INDEX IF NOT EXISTS idx_rel_destination ON relationship_records(relationship_class_id, destination_feature_id);
