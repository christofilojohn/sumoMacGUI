#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  Scripts/make-large-benchmark-scenario.sh --bbox west,south,east,north [options]
  Scripts/make-large-benchmark-scenario.sh --preset athens [options]
  Scripts/make-large-benchmark-scenario.sh --osm path/to/map.osm.xml [options]

Builds a large SUMO benchmark scenario from OpenStreetMap data, writes it under
.build/benchmarks by default, and runs NetParseBenchmark against the generated
.net.xml unless --skip-parser-benchmark is used.

Options:
  --bbox VALUE                  Download OSM data for west,south,east,north.
  --preset NAME                 Convenience bbox: athens (Athens, Greece).
  --osm FILE                    Use an existing .osm.xml file instead of downloading.
  --output-dir DIR              Output directory. Default: .build/benchmarks/osm-large
  --prefix NAME                 Output filename prefix. Default: sumogui-large
  --begin SECONDS               Route generation begin time. Default: 0
  --end SECONDS                 Route generation end time. Default: 3600
  --vehicles COUNT              Target random trips. Default: 50000
  --period SECONDS              Override derived trip period.
  --seed INT                    randomTrips.py seed. Default: 42
  --min-distance METERS         Minimum random trip distance. Default: 1000
  --vehicle-class CLASS         SUMO vehicle class. Default: passenger
  --netconvert-options VALUE    Comma-separated osmBuild.py netconvert options.
  --skip-routes                 Only build the network, not routes/.sumocfg.
  --skip-parser-benchmark       Do not run NetParseBenchmark after generation.
  -h, --help                    Show this help.

Examples:
  Scripts/make-large-benchmark-scenario.sh --preset athens
  Scripts/make-large-benchmark-scenario.sh --bbox 23.68,37.95,23.78,38.02 --prefix athens
  Scripts/make-large-benchmark-scenario.sh --osm ~/Downloads/city.osm.xml --vehicles 25000
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

BBOX=""
OSM_FILE=""
OUTPUT_DIR="$REPO_ROOT/.build/benchmarks/osm-large"
PREFIX="sumogui-large"
BEGIN_TIME="0"
END_TIME="3600"
VEHICLES="50000"
PERIOD=""
SEED="42"
MIN_DISTANCE="1000"
VEHICLE_CLASS="passenger"
BUILD_ROUTES=1
RUN_PARSER_BENCHMARK=1
NETCONVERT_OPTIONS="--geometry.remove,--roundabouts.guess,--ramps.guess,--junctions.join,--tls.guess-signals,--tls.discard-simple,--remove-edges.isolated"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bbox)
      BBOX="${2:-}"
      shift 2
      ;;
    --preset)
      case "${2:-}" in
        athens)
          BBOX="23.680,37.950,23.780,38.020"
          ;;
        *)
          echo "error: unknown preset '${2:-}'" >&2
          exit 2
          ;;
      esac
      shift 2
      ;;
    --osm)
      OSM_FILE="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --prefix)
      PREFIX="${2:-}"
      shift 2
      ;;
    --begin)
      BEGIN_TIME="${2:-}"
      shift 2
      ;;
    --end)
      END_TIME="${2:-}"
      shift 2
      ;;
    --vehicles)
      VEHICLES="${2:-}"
      shift 2
      ;;
    --period)
      PERIOD="${2:-}"
      shift 2
      ;;
    --seed)
      SEED="${2:-}"
      shift 2
      ;;
    --min-distance)
      MIN_DISTANCE="${2:-}"
      shift 2
      ;;
    --vehicle-class)
      VEHICLE_CLASS="${2:-}"
      shift 2
      ;;
    --netconvert-options)
      NETCONVERT_OPTIONS="${2:-}"
      shift 2
      ;;
    --skip-routes)
      BUILD_ROUTES=0
      shift
      ;;
    --skip-parser-benchmark)
      RUN_PARSER_BENCHMARK=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -n "$BBOX" && -n "$OSM_FILE" ]]; then
  echo "error: use either --bbox/--preset or --osm, not both" >&2
  exit 2
fi

if [[ -z "$BBOX" && -z "$OSM_FILE" ]]; then
  echo "error: provide --bbox, --preset, or --osm" >&2
  usage >&2
  exit 2
fi

if [[ -n "$OSM_FILE" && ! -f "$OSM_FILE" ]]; then
  echo "error: OSM file not found: $OSM_FILE" >&2
  exit 1
fi

PYTHON="${PYTHON:-python3}"
SUMO_BIN="$("$REPO_ROOT/Scripts/find-sumo.sh")"
SUMO_BIN_DIR="$(cd -- "$(dirname -- "$SUMO_BIN")" && pwd)"

if [[ -n "${SUMO_HOME:-}" && -d "$SUMO_HOME/tools" ]]; then
  SUMO_SHARE="$SUMO_HOME"
else
  SUMO_ROOT="$(cd -- "$SUMO_BIN_DIR/.." && pwd)"
  SUMO_SHARE="$SUMO_ROOT/share/sumo"
  export SUMO_HOME="$SUMO_SHARE"
fi

SUMO_TOOLS="$SUMO_SHARE/tools"
OSM_GET="$SUMO_TOOLS/osmGet.py"
OSM_BUILD="$SUMO_TOOLS/osmBuild.py"
RANDOM_TRIPS="$SUMO_TOOLS/randomTrips.py"

for tool in "$OSM_BUILD" "$RANDOM_TRIPS"; do
  if [[ ! -f "$tool" ]]; then
    echo "error: SUMO tool not found: $tool" >&2
    echo "hint: set SUMO_HOME to the SUMO share directory, e.g. /Library/Frameworks/EclipseSUMO.framework/Versions/Current/EclipseSUMO/share/sumo" >&2
    exit 1
  fi
done

if [[ -n "$BBOX" && ! -f "$OSM_GET" ]]; then
  echo "error: SUMO OSM download tool not found: $OSM_GET" >&2
  exit 1
fi

export PATH="$SUMO_BIN_DIR:$PATH"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd -- "$OUTPUT_DIR" && pwd)"

if [[ -n "$BBOX" ]]; then
  echo "Downloading OSM data for bbox $BBOX..."
  "$PYTHON" "$OSM_GET" --bbox "$BBOX" --prefix "$PREFIX" --output-dir "$OUTPUT_DIR"
  OSM_FILE="$OUTPUT_DIR/${PREFIX}_bbox.osm.xml"
fi

if [[ ! -f "$OSM_FILE" ]]; then
  echo "error: expected OSM file was not produced: $OSM_FILE" >&2
  exit 1
fi

NET_FILE="$OUTPUT_DIR/$PREFIX.net.xml"
ROUTE_FILE="$OUTPUT_DIR/$PREFIX.rou.xml"
CONFIG_FILE="$OUTPUT_DIR/$PREFIX.sumocfg"
BENCHMARK_FILE="$OUTPUT_DIR/$PREFIX.net-benchmark.txt"

echo "Building SUMO network..."
"$PYTHON" "$OSM_BUILD" \
  --osm-file "$OSM_FILE" \
  --prefix "$PREFIX" \
  --output-directory "$OUTPUT_DIR" \
  --vehicle-classes "$VEHICLE_CLASS" \
  --netconvert-options "$NETCONVERT_OPTIONS"

if [[ ! -f "$NET_FILE" ]]; then
  echo "error: expected network was not produced: $NET_FILE" >&2
  exit 1
fi

if [[ "$BUILD_ROUTES" -eq 1 ]]; then
  if [[ -z "$PERIOD" ]]; then
    PERIOD="$(awk -v begin="$BEGIN_TIME" -v end="$END_TIME" -v vehicles="$VEHICLES" 'BEGIN {
      duration = end - begin
      if (duration <= 0 || vehicles <= 0) {
        exit 1
      }
      printf "%.6f", duration / vehicles
    }')"
  fi

  echo "Generating approximately $VEHICLES random trips with period $PERIOD..."
  "$PYTHON" "$RANDOM_TRIPS" \
    --net-file "$NET_FILE" \
    --route-file "$ROUTE_FILE" \
    --begin "$BEGIN_TIME" \
    --end "$END_TIME" \
    --period "$PERIOD" \
    --seed "$SEED" \
    --min-distance "$MIN_DISTANCE" \
    --vehicle-class "$VEHICLE_CLASS" \
    --validate \
    --remove-loops

  cat > "$CONFIG_FILE" <<EOF
<configuration>
    <input>
        <net-file value="$(basename "$NET_FILE")"/>
        <route-files value="$(basename "$ROUTE_FILE")"/>
    </input>
    <time>
        <begin value="$BEGIN_TIME"/>
        <end value="$END_TIME"/>
    </time>
    <processing>
        <time-to-teleport value="-1"/>
    </processing>
    <report>
        <no-step-log value="true"/>
    </report>
</configuration>
EOF
fi

if [[ "$RUN_PARSER_BENCHMARK" -eq 1 ]]; then
  echo "Running parser benchmark..."
  "$REPO_ROOT/Scripts/benchmark-net-parse.sh" "$NET_FILE" | tee "$BENCHMARK_FILE"
fi

echo
echo "Benchmark scenario ready:"
echo "  network: $NET_FILE"
if [[ "$BUILD_ROUTES" -eq 1 ]]; then
  echo "  routes:  $ROUTE_FILE"
  echo "  config:  $CONFIG_FILE"
fi
if [[ "$RUN_PARSER_BENCHMARK" -eq 1 ]]; then
  echo "  parse:   $BENCHMARK_FILE"
fi
