-- Geometric networks: graph-based spatial network tracing
CREATE TABLE IF NOT EXISTS networks (
    id UUID PRIMARY KEY,
    dataset_id UUID NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    network_type TEXT NOT NULL DEFAULT 'geometric',  -- geometric, utility
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Network edges (lines connecting junctions)
CREATE TABLE IF NOT EXISTS network_edges (
    id UUID PRIMARY KEY,
    network_id UUID NOT NULL REFERENCES networks(id) ON DELETE CASCADE,
    feature_id UUID NOT NULL,
    from_junction UUID,
    to_junction UUID,
    cost DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    reverse_cost DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    enabled BOOLEAN NOT NULL DEFAULT TRUE
);

-- Network junctions (connection points)
CREATE TABLE IF NOT EXISTS network_junctions (
    id UUID PRIMARY KEY,
    network_id UUID NOT NULL REFERENCES networks(id) ON DELETE CASCADE,
    feature_id UUID,
    geometry GEOMETRY(Point, 4326)
);

CREATE INDEX IF NOT EXISTS idx_edges_network ON network_edges(network_id);
CREATE INDEX IF NOT EXISTS idx_edges_from ON network_edges(from_junction);
CREATE INDEX IF NOT EXISTS idx_edges_to ON network_edges(to_junction);
CREATE INDEX IF NOT EXISTS idx_junctions_network ON network_junctions(network_id);
CREATE INDEX IF NOT EXISTS idx_junctions_geom ON network_junctions USING GIST(geometry);
