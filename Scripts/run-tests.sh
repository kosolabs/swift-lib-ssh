#!/bin/bash
set -e

# Cleanup function that runs on exit
cleanup() {
  echo "🧹 Cleaning up..."
  docker stop ssh-test-server 2>/dev/null || true
  docker rm ssh-test-server 2>/dev/null || true
}

# Register cleanup to run on script exit (success or failure)
trap cleanup EXIT

echo "🔨 Building SSH test server Docker image..."
docker build -f Tests/SwiftLibSSHTests/Resources/ssh-test-server.Dockerfile -t ssh-test-server Tests/SwiftLibSSHTests/Resources/

echo "🚀 Starting SSH test server..."
docker run -d --name ssh-test-server -p 2222:22 ssh-test-server

echo "⏳ Waiting for SSH server to be ready..."
for i in {1..10}; do
  if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
     -p 2222 myuser@localhost -i Tests/SwiftLibSSHTests/Resources/id_ed25519 whoami &>/dev/null; then
    echo "✅ SSH server is ready!"
    break
  fi
  echo "Waiting... ($i/10)"
  sleep 1
done

echo "🧪 Running tests..."
swift test
