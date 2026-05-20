#!/usr/bin/env bash
# Real Estate MVP Setup Script
# Creates parcel and sales datasets in Ptolemy for real estate workflows.
#
# Usage: ./scripts/re-setup.sh [PTOLEMY_URL]
# Default: http://localhost:3000/api/v1

set -euo pipefail

API="${1:-http://localhost:3000/api/v1}"

echo "=== TileTopia Real Estate MVP Setup ==="
echo "API: $API"
echo

# 1. Create Parcels dataset
echo "Creating parcels dataset..."
PARCELS=$(curl -sf -X POST "$API/datasets" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "parcels",
    "geometry_type": "Polygon",
    "schema": {
      "apn": "string",
      "address": "string",
      "owner": "string",
      "area_sqft": "float",
      "zoning": "string",
      "land_use": "string",
      "assessed_value": "float",
      "market_value": "float",
      "year_built": "integer",
      "building_sqft": "float",
      "flood_zone": "string",
      "tax_rate": "float"
    }
  }')
PARCELS_ID=$(echo "$PARCELS" | jq -r '.id')
echo "  Created: $PARCELS_ID"

# 2. Create Sales dataset
echo "Creating sales dataset..."
SALES=$(curl -sf -X POST "$API/datasets" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "sales",
    "geometry_type": "Point",
    "schema": {
      "address": "string",
      "sale_date": "string",
      "sale_price": "float",
      "sqft": "float",
      "bedrooms": "integer",
      "bathrooms": "float",
      "year_built": "integer",
      "apn": "string",
      "buyer": "string",
      "seller": "string"
    }
  }')
SALES_ID=$(echo "$SALES" | jq -r '.id')
echo "  Created: $SALES_ID"

# 3. Create Zoning overlay dataset
echo "Creating zoning dataset..."
ZONING=$(curl -sf -X POST "$API/datasets" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "zoning",
    "geometry_type": "Polygon",
    "schema": {
      "zone_code": "string",
      "zone_name": "string",
      "description": "string",
      "max_height_ft": "float",
      "max_density": "float",
      "min_lot_size": "float",
      "allowed_uses": "string"
    }
  }')
ZONING_ID=$(echo "$ZONING" | jq -r '.id')
echo "  Created: $ZONING_ID"

# 4. Create main branch for each
for ID in "$PARCELS_ID" "$SALES_ID" "$ZONING_ID"; do
  curl -sf -X POST "$API/datasets/$ID/branches" \
    -H "Content-Type: application/json" \
    -d '{"name": "main"}' > /dev/null
done

echo
echo "=== Setup Complete ==="
echo
echo "Datasets created:"
echo "  Parcels: $PARCELS_ID"
echo "  Sales:   $SALES_ID"
echo "  Zoning:  $ZONING_ID"
echo
echo "Next steps:"
echo "  1. Import parcel shapefile:  geodukt import --format shapefile --dataset $PARCELS_ID parcels.shp"
echo "  2. Import sales CSV:         geodukt import --format csv --dataset $SALES_ID sales.csv"
echo "  3. Import zoning GeoJSON:    geodukt import --format geojson --dataset $ZONING_ID zoning.geojson"
echo
echo "  Or download from your county assessor's open data portal."
echo
echo "Configure viewtopia:"
echo "  VITE_PARCELS_DATASET=$PARCELS_ID"
echo "  VITE_SALES_DATASET=$SALES_ID"
echo "  VITE_ZONING_DATASET=$ZONING_ID"
