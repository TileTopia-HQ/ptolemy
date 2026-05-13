-- Linear referencing: routes and events
CREATE TABLE IF NOT EXISTS routes (
    id UUID PRIMARY KEY,
    dataset_id UUID NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    geometry GEOMETRY(LineStringM, 4326),
    total_length DOUBLE PRECISION,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Route events: point or linear events along routes
CREATE TABLE IF NOT EXISTS route_events (
    id UUID PRIMARY KEY,
    route_id UUID NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL DEFAULT 'point',  -- point or linear
    from_measure DOUBLE PRECISION NOT NULL,
    to_measure DOUBLE PRECISION,  -- NULL for point events
    properties JSONB NOT NULL DEFAULT '{}',
    geometry GEOMETRY(Geometry, 4326)  -- derived from route + measures
);

CREATE INDEX IF NOT EXISTS idx_routes_dataset ON routes(dataset_id);
CREATE INDEX IF NOT EXISTS idx_routes_geom ON routes USING GIST(geometry);
CREATE INDEX IF NOT EXISTS idx_events_route ON route_events(route_id);
CREATE INDEX IF NOT EXISTS idx_events_measures ON route_events(route_id, from_measure, to_measure);
