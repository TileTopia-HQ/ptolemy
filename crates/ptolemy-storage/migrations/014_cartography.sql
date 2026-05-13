-- Cartographic representations: symbology stored in DB
CREATE TABLE IF NOT EXISTS symbology_rules (
    id UUID PRIMARY KEY,
    dataset_id UUID NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    priority INTEGER NOT NULL DEFAULT 0,
    filter_expression TEXT,  -- SQL-like filter for which features this applies to
    min_scale DOUBLE PRECISION,
    max_scale DOUBLE PRECISION,
    symbol JSONB NOT NULL  -- {type: "simple_fill", color: [r,g,b,a], outline: {...}, ...}
);

CREATE TABLE IF NOT EXISTS label_rules (
    id UUID PRIMARY KEY,
    dataset_id UUID NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    priority INTEGER NOT NULL DEFAULT 0,
    field_expression TEXT NOT NULL,  -- field name or expression for label text
    filter_expression TEXT,
    min_scale DOUBLE PRECISION,
    max_scale DOUBLE PRECISION,
    font JSONB NOT NULL DEFAULT '{"family": "Arial", "size": 12, "bold": false}',
    placement JSONB NOT NULL DEFAULT '{"type": "point_on_surface"}',
    halo JSONB  -- {color: [255,255,255,200], width: 1}
);

CREATE INDEX IF NOT EXISTS idx_symbology_dataset ON symbology_rules(dataset_id, priority);
CREATE INDEX IF NOT EXISTS idx_labels_dataset ON label_rules(dataset_id, priority);
