#!/usr/bin/env bash
#
# simulate-route.sh — walk/run an iOS Simulator through a closed-loop GPS
# route at a natural pace, for testing location-driven features (Tracking,
# History, and future location-dependent work) without a physical device.
#
# `xcrun simctl location <device> set <lat>,<lon>` only teleports to a single
# point instantly. This script repeatedly calls it with linearly-interpolated
# intermediate points between each waypoint, paced to a configurable average
# speed, and loops back from the last waypoint to the first indefinitely —
# so a short list of waypoints becomes continuous, repeatable lap traffic.
#
# (There is also a built-in `xcrun simctl location <device> start
# --speed=<m/s> <lat1>,<lon1> ...` that interpolates a single waypoint list
# in the background — but it doesn't loop back to the first waypoint on its
# own and gives no progress feedback while running, which is the actual gap
# this script fills.)
#
# USAGE
#   scripts/simulate-route.sh [options]
#
# OPTIONS
#   -r, --route <file>     Path to a waypoint CSV file (default:
#                           scripts/routes/sample-loop.csv, next to this
#                           script).
#   -d, --device <id>      Simulator UDID or name (default: booted). Use
#                           `xcrun simctl list devices booted` if you have
#                           more than one simulator running and need to pick.
#   -s, --speed <km/h>     Average pace to simulate (default: 5, a walking
#                           pace). Use e.g. 10-12 for running, 20+ for
#                           cycling.
#   -i, --interval <sec>   Seconds between each `simctl location set` call
#                           (default: 1). Smaller = smoother but noisier.
#   -h, --help             Show this help and exit.
#
# EDITING WAYPOINTS
#   Waypoints live in a plain CSV file, one "latitude,longitude" pair per
#   line (see scripts/routes/sample-loop.csv for the format and an example
#   loop). Add/remove/reorder lines to change the route; the script always
#   closes the loop by returning from the last waypoint to the first, so
#   don't repeat the first waypoint at the end of the file. Point --route at
#   a different file to keep multiple routes around for different tests.
#
# STOPPING
#   Ctrl+C. The script traps it, calls `simctl location <device> clear` so
#   the simulator doesn't stay stuck simulating a location, and exits.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEVICE="booted"
ROUTE_FILE="$SCRIPT_DIR/routes/sample-loop.csv"
SPEED_KMH="15"
INTERVAL="1"

usage() {
    sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}

positive_number() {
    case "$1" in
        ''|*[!0-9.]*) return 1 ;;
    esac
    awk -v n="$1" 'BEGIN { exit !(n > 0) }'
}

trim() {
    local value="$1"
    value="${value%$'\r'}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--route) ROUTE_FILE="$2"; shift 2 ;;
        -d|--device) DEVICE="$2"; shift 2 ;;
        -s|--speed) SPEED_KMH="$2"; shift 2 ;;
        -i|--interval) INTERVAL="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ ! -f "$ROUTE_FILE" ]]; then
    echo "Route file not found: $ROUTE_FILE" >&2
    exit 1
fi

if ! positive_number "$SPEED_KMH"; then
    echo "Invalid --speed (must be a positive number): $SPEED_KMH" >&2
    exit 1
fi

if ! positive_number "$INTERVAL"; then
    echo "Invalid --interval (must be a positive number): $INTERVAL" >&2
    exit 1
fi

waypoints=()
while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line="$(trim "${raw_line%%#*}")"
    [[ -z "$line" ]] && continue

    IFS=',' read -r lat lon <<< "$line"
    lat="$(trim "${lat:-}")"
    lon="$(trim "${lon:-}")"

    if [[ -z "$lat" || -z "$lon" ]]; then
        echo "Skipping malformed waypoint line: $raw_line" >&2
        continue
    fi

    waypoints+=("$lat,$lon")
done < "$ROUTE_FILE"

waypoint_count=${#waypoints[@]}
if (( waypoint_count < 2 )); then
    echo "Route must have at least 2 waypoints (found $waypoint_count in $ROUTE_FILE)" >&2
    exit 1
fi

echo "Route:    $ROUTE_FILE ($waypoint_count waypoints, closed loop)"
echo "Device:   $DEVICE"
echo "Speed:    ${SPEED_KMH} km/h"
echo "Interval: ${INTERVAL}s between updates"
echo "Press Ctrl+C to stop."
echo

cleanup() {
    echo
    echo "Stopping — clearing simulated location on $DEVICE."
    xcrun simctl location "$DEVICE" clear >/dev/null 2>&1 || true
    exit 0
}
trap cleanup INT TERM

lap=1

while true; do
    echo "--- Lap $lap ---"

    for (( i = 0; i < waypoint_count; i++ )); do
        from="${waypoints[$i]}"
        to="${waypoints[$(( (i + 1) % waypoint_count ))]}"

        IFS=',' read -r from_lat from_lon <<< "$from"
        IFS=',' read -r to_lat to_lon <<< "$to"

        # One awk call computes the great-circle segment distance (haversine)
        # and, from that plus the requested speed/interval, how many
        # intermediate `simctl location set` calls this segment needs.
        read -r segment_meters steps <<< "$(awk \
            -v lat1="$from_lat" -v lon1="$from_lon" \
            -v lat2="$to_lat" -v lon2="$to_lon" \
            -v speed_kmh="$SPEED_KMH" -v interval="$INTERVAL" '
            BEGIN {
                pi = atan2(0, -1)
                rad = pi / 180
                earth_radius_m = 6371000
                dlat = (lat2 - lat1) * rad
                dlon = (lon2 - lon1) * rad
                a = sin(dlat / 2) ^ 2 + cos(lat1 * rad) * cos(lat2 * rad) * sin(dlon / 2) ^ 2
                c = 2 * atan2(sqrt(a), sqrt(1 - a))
                distance_m = earth_radius_m * c

                speed_ms = speed_kmh * 1000 / 3600
                duration_s = distance_m / speed_ms
                steps = int(duration_s / interval + 0.5)
                if (steps < 1) steps = 1

                printf "%.3f %d", distance_m, steps
            }')"

        for (( step = 1; step <= steps; step++ )); do
            read -r cur_lat cur_lon <<< "$(awk \
                -v lat1="$from_lat" -v lon1="$from_lon" \
                -v lat2="$to_lat" -v lon2="$to_lon" \
                -v step="$step" -v steps="$steps" '
                BEGIN {
                    fraction = step / steps
                    printf "%.6f %.6f", lat1 + (lat2 - lat1) * fraction, lon1 + (lon2 - lon1) * fraction
                }')"

            xcrun simctl location "$DEVICE" set "$cur_lat,$cur_lon"
            printf 'Lap %-3d  waypoint %d -> %d  step %d/%d  (%.0fm segment)  now at %s,%s\n' \
                "$lap" "$((i + 1))" "$((( (i + 1) % waypoint_count ) + 1))" "$step" "$steps" \
                "$segment_meters" "$cur_lat" "$cur_lon"

            sleep "$INTERVAL"
        done
    done

    lap=$((lap + 1))
done
