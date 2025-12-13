default: test

build-test-server:
    docker compose -f Tests/docker-compose.yml build

start-test-server: build-test-server
    docker compose -f Tests/docker-compose.yml up -d

stop-test-server:
    docker compose -f Tests/docker-compose.yml down

test: stop-test-server start-test-server
    swift test
