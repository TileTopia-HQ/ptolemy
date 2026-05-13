-- Raster/imagery support via PostGIS raster
CREATE EXTENSION IF NOT EXISTS postgis_raster;

CREATE TABLE IF NOT EXISTS raster_catalogs (
    id UUID PRIMARY KEY,
    dataset_id UUID NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    srid INTEGER NOT NULL DEFAULT 4326,
    pixel_type TEXT NOT NULL DEFAULT 'uint8',
    num_bands INTEGER NOT NULL DEFAULT 1,
    tile_width INTEGER NOT NULL DEFAULT 256,
    tile_height INTEGER NOT NULL DEFAULT 256,
    nodata_value DOUBLE PRECISION,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS raster_tiles (
    id UUID PRIMARY KEY,
    catalog_id UUID NOT NULL REFERENCES raster_catalogs(id) ON DELETE CASCADE,
    rast RASTER,
    bounds GEOMETRY(Polygon, 4326),
    zoom_level INTEGER NOT NULL DEFAULT 0,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_raster_tiles_catalog ON raster_tiles(catalog_id);
CREATE INDEX IF NOT EXISTS idx_raster_tiles_bounds ON raster_tiles USING GIST(bounds);
CREATE INDEX IF NOT EXISTS idx_raster_tiles_zoom ON raster_tiles(catalog_id, zoom_level);
