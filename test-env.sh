#!/usr/bin/env bash

set -e

FAKE_STREAMS_PATH=""
ACTION=""
DOCKER_COMPOSE_FILE="./docker-compose-generated.yml"
FFMPEG_VERSION="4.4-alpine"
MEDIAMTX_VERSION="1.13.0"


usage() {
  echo "Handy tool to bootstrap a dead simple Frigate test environment with (optional) fake camera streams from .mp4 files."
  echo ""
  echo "Usage:"
  echo "  $0 [--start|-s [-p|--fake-streams-path <arg>]] | [--stop]"
  echo ""
  echo "Example:"
  echo "  $0 --start --fake-streams-path /path/to/fake/streams"
  echo "  $0 --stop"
  exit 1
}

[[ $# -eq 0 ]] && usage

# Handle long options manually
while [[ $# -gt 0 ]]; do
  case "$1" in
    --start)
      if [[ -n "$ACTION" ]]; then
        echo "Error: Cannot combine --start and --stop"
        usage
      fi
      ACTION="start"
      shift
      ;;
    --stop)
      if [[ -n "$ACTION" ]]; then
        echo "Error: Cannot combine --start and --stop"
        usage
      fi
      ACTION="stop"
      shift
      ;;
    --fake-streams-path)
      if [[ "$ACTION" != "start" ]]; then
        echo "Error: --fake-streams-path can only be used with --start"
        usage
      fi
      if [[ -z "$2" ]]; then
        echo "Error: Missing argument for --fake-streams-path"
        usage
      fi
      FAKE_STREAMS_PATH="$2"
      shift 2
      ;;
    -s)
      if [[ -n "$ACTION" && "$ACTION" != "start" ]]; then
        echo "Error: Cannot combine --start/-s and --stop"
        usage
      fi
      ACTION="start"
      shift
      ;;
    -p)
      if [[ "$ACTION" != "start" ]]; then
        echo "Error: -p can only be used with --start/-s"
        usage
      fi
      if [[ -z "$2" ]]; then
        echo "Error: Missing argument for -p"
        usage
      fi
      FAKE_STREAMS_PATH="$2"
      shift 2
      ;;
    -sp*)
      # handle combined -spARG (e.g. -sp/tmp/fake)
      if [[ -n "$ACTION" && "$ACTION" != "start" ]]; then
        echo "Error: Cannot combine --start/-s and --stop"
        usage
      fi
      ACTION="start"
      # extract argument after -sp
      FAKE_STREAMS_PATH="${1:3}"
      if [[ -z "$FAKE_STREAMS_PATH" ]]; then
        echo "Error: Missing argument for -sp"
        usage
      fi
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      ;;
  esac
done

# Check prerequisites
command -v docker >/dev/null 2>&1 || { echo "docker not detected! stop."; exit 1; }

# Execute based on action
case "$ACTION" in
  start)
    echo "Starting test environment..."
    if [[ -n "$FAKE_STREAMS_PATH" ]]; then
      echo "Generating extra webcam streams from $FAKE_STREAMS_PATH"
      
      cat > "$DOCKER_COMPOSE_FILE" <<EOF
services:
  mediamtx:
    image: bluenviron/mediamtx:$MEDIAMTX_VERSION
    container_name: mediamtx
    ports:
      - "8554:8554"
    restart: unless-stopped
EOF

      count=1
      find "$FAKE_STREAMS_PATH" -maxdepth 1 -type f -name "*.mp4" -print0 | sort -z | while IFS= read -r -d '' file; do
        base=$(basename "$file")
        name=$(echo "$base" | sed -E 's/[^a-zA-Z0-9]+/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/^-*//;s/-*$//')

        cat >> "$DOCKER_COMPOSE_FILE" <<EOF
  ffmpeg-cam$count:
    image: jrottenberg/ffmpeg:$FFMPEG_VERSION
    container_name: ffmpeg-cam$count
    depends_on:
      - mediamtx
    volumes:
      - "\${VIDEOS_FOLDER}:/videos"
    command: >
      -re -stream_loop -1 -i "/videos/$base"
      -vcodec libx264 -preset veryfast -tune zerolatency
      -acodec aac -ar 44100 -b:a 128k
      -f rtsp rtsp://mediamtx:8554/stream$count
EOF
        count=$((count + 1))
      done
      
    fi
    ;;
  stop)
    echo "Stopping test environment..."
    [ -f "$DOCKER_COMPOSE_FILE" ] && docker compose -f $DOCKER_COMPOSE_FILE down || echo "$DOCKER_COMPOSE_FILE not found, nothing to do."
    ;;
  *)
    usage
    ;;
esac
