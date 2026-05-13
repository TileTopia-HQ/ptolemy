#!/usr/bin/env bash
# Demo script: creates two branches that both edit the same features differently,
# producing conflicts that can be visualized in /conflicts UI.
set -euo pipefail

API="http://localhost:3000/api/v1"

echo "=== Ptolemy Conflict Resolution Demo ==="
echo ""

# 1. Create a dataset
echo "1. Creating dataset 'city_roads'..."
DS=$(curl -s -X POST "$API/datasets" \
  -H "Content-Type: application/json" \
  -d '{"name":"city_roads","srid":4326,"geometry_type":"linestring","created_by":"demo"}')
DS_ID=$(echo "$DS" | jq -r '.id')
echo "   Dataset ID: $DS_ID"

# 2. Create main branch
echo "2. Creating 'main' branch..."
MAIN=$(curl -s -X POST "$API/datasets/$DS_ID/branches" \
  -H "Content-Type: application/json" \
  -d '{"name":"main","created_by":"demo"}')
MAIN_ID=$(echo "$MAIN" | jq -r '.id')
echo "   Main branch ID: $MAIN_ID"

# 3. Add initial features (a road segment: LINESTRING)
# WKB for LINESTRING(-73.99 40.73, -73.98 40.74) in 4326
# Using well-known hex for PostGIS
ROAD1_ID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
ROAD2_ID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
ROAD3_ID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")

echo "3. Adding 3 road features to main..."
# POINT WKB is simpler for demo — let's use POINT geometry
# WKB hex for POINT(-73.99 40.73) SRID=4326:
# 0101000020E6100000F6285C8FC2F952C01F85EB51B85D4440
# Simplified - use a proper WKB point without SRID prefix for compatibility
# POINT(-73.99, 40.73) in WKB (little-endian, no SRID):
P1="0101000000295C8FC2F5F952C0AE47E17A145D4440"
P2="0101000000CDCCCCCCCCF852C0CDCCCCCCCC5C4440"
P3="0101000000713D0AD7A3F852C0EC51B81E855D4440"

COMMIT1=$(curl -s -X POST "$API/branches/$MAIN_ID/batch" \
  -H "Content-Type: application/json" \
  -d "{
    \"message\": \"Initial road data\",
    \"author\": \"surveyor_alice\",
    \"operations\": [
      {\"type\":\"insert\",\"feature_id\":\"$ROAD1_ID\",\"geometry_wkb_hex\":\"$P1\",\"properties\":{\"name\":\"Broadway\",\"lanes\":4,\"surface\":\"asphalt\",\"speed_limit\":35}},
      {\"type\":\"insert\",\"feature_id\":\"$ROAD2_ID\",\"geometry_wkb_hex\":\"$P2\",\"properties\":{\"name\":\"5th Avenue\",\"lanes\":3,\"surface\":\"asphalt\",\"speed_limit\":30}},
      {\"type\":\"insert\",\"feature_id\":\"$ROAD3_ID\",\"geometry_wkb_hex\":\"$P3\",\"properties\":{\"name\":\"Park Ave\",\"lanes\":2,\"surface\":\"cobblestone\",\"speed_limit\":25}}
    ]
  }")
echo "   Commit: $(echo "$COMMIT1" | jq -r '.changeset.id')"

# 4. Fork two branches from main
echo "4. Creating branch 'field_team_A'..."
BRANCH_A=$(curl -s -X POST "$API/datasets/$DS_ID/branches" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"field_team_A\",\"created_by\":\"alice\",\"fork_from_branch\":\"$MAIN_ID\"}")
BRANCH_A_ID=$(echo "$BRANCH_A" | jq -r '.id')
echo "   Branch A ID: $BRANCH_A_ID"

echo "5. Creating branch 'field_team_B'..."
BRANCH_B=$(curl -s -X POST "$API/datasets/$DS_ID/branches" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"field_team_B\",\"created_by\":\"bob\",\"fork_from_branch\":\"$MAIN_ID\"}")
BRANCH_B_ID=$(echo "$BRANCH_B" | jq -r '.id')
echo "   Branch B ID: $BRANCH_B_ID"

# 5. Team A: update features (move geometry + change properties)
echo "6. Team A edits: move Broadway, update lanes on 5th Ave..."
# Move Broadway slightly east
PA1="0101000000CDCCCCCCCCF952C0B81E85EB515D4440"
COMMIT_A=$(curl -s -X POST "$API/branches/$BRANCH_A_ID/batch" \
  -H "Content-Type: application/json" \
  -d "{
    \"message\": \"Field survey update - Team A\",
    \"author\": \"alice\",
    \"operations\": [
      {\"type\":\"update\",\"feature_id\":\"$ROAD1_ID\",\"geometry_wkb_hex\":\"$PA1\",\"properties\":{\"name\":\"Broadway\",\"lanes\":5,\"surface\":\"asphalt\",\"speed_limit\":40,\"surveyed_by\":\"alice\"}},
      {\"type\":\"update\",\"feature_id\":\"$ROAD2_ID\",\"properties\":{\"name\":\"5th Avenue\",\"lanes\":4,\"surface\":\"asphalt\",\"speed_limit\":30,\"bike_lane\":true}}
    ]
  }")
echo "   Team A commit: $(echo "$COMMIT_A" | jq -r '.changeset.id')"

# 6. Team B: update SAME features differently
echo "7. Team B edits: different Broadway position, different 5th Ave changes..."
# Move Broadway slightly west  
PB1="0101000000F6285C8FC2F952C0D7A3703D0A5D4440"
COMMIT_B=$(curl -s -X POST "$API/branches/$BRANCH_B_ID/batch" \
  -H "Content-Type: application/json" \
  -d "{
    \"message\": \"Field survey update - Team B\",
    \"author\": \"bob\",
    \"operations\": [
      {\"type\":\"update\",\"feature_id\":\"$ROAD1_ID\",\"geometry_wkb_hex\":\"$PB1\",\"properties\":{\"name\":\"Broadway\",\"lanes\":4,\"surface\":\"concrete\",\"speed_limit\":30,\"surveyed_by\":\"bob\"}},
      {\"type\":\"update\",\"feature_id\":\"$ROAD2_ID\",\"properties\":{\"name\":\"Fifth Avenue\",\"lanes\":3,\"surface\":\"asphalt\",\"speed_limit\":25,\"bus_lane\":true}},
      {\"type\":\"delete\",\"feature_id\":\"$ROAD3_ID\"}
    ]
  }")
echo "   Team B commit: $(echo "$COMMIT_B" | jq -r '.changeset.id')"

echo ""
echo "=== CONFLICT SCENARIO READY ==="
echo ""
echo "Target (main):    $MAIN_ID"
echo "Source (Team A):  $BRANCH_A_ID"
echo "Source (Team B):  $BRANCH_B_ID"
echo ""
echo "Conflicts will appear when merging Team A into Main, then Team B into Main."
echo ""
echo "Try merging Team A first (no conflicts - fast forward):"
echo "  curl -X POST $API/branches/$MAIN_ID/merge/$BRANCH_A_ID -H 'Content-Type: application/json' -d '{\"message\":\"merge team A\",\"author\":\"manager\"}'"
echo ""
echo "Then merge Team B (CONFLICTS!):"
echo "  Preview: curl $API/branches/$MAIN_ID/merge/$BRANCH_B_ID/preview"
echo "  → Open http://localhost:3000/conflicts"
echo "  → Enter Target: $MAIN_ID"
echo "  → Enter Source: $BRANCH_B_ID"
echo ""
echo "── Executing merge of Team A... ──"
MERGE_A=$(curl -s -X POST "$API/branches/$MAIN_ID/merge/$BRANCH_A_ID" \
  -H "Content-Type: application/json" \
  -d '{"message":"merge team A survey","author":"manager"}')
echo "   Merge A result: $(echo "$MERGE_A" | jq -c '.')"

echo ""
echo "── Now preview Team B merge (should show conflicts): ──"
PREVIEW=$(curl -s "$API/branches/$MAIN_ID/merge/$BRANCH_B_ID/preview")
echo "   Conflict count: $(echo "$PREVIEW" | jq '.conflict_count')"
echo "   Auto-mergeable: $(echo "$PREVIEW" | jq '.auto_mergeable')"
echo "   Conflicts:"
echo "$PREVIEW" | jq '.conflicts[] | {feature_id: .feature_id, type: .conflict_type, suggestion: .suggestion}'

echo ""
echo "══════════════════════════════════════════════"
echo "  Open http://localhost:3000/conflicts"
echo "  Target: $MAIN_ID"
echo "  Source: $BRANCH_B_ID"
echo "══════════════════════════════════════════════"
