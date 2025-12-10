#!/bin/bash
set -e

# Cleanup function that runs on exit
cleanup() {
  echo "🧹 Cleaning up..."
  docker compose -f Tests/Server/docker-compose.yml down
}

# Register cleanup to run on script exit (success or failure)
trap cleanup EXIT

echo "🚀 Starting SSH test server..."
docker compose -f Tests/Server/docker-compose.yml up -d

echo "🧪 Running tests..."
swift test
