default: test

test-server-build:
    docker compose -f Tests/docker-compose.yml build

test-server-up:
    docker compose -f Tests/docker-compose.yml up -d

test-server-down:
    docker compose -f Tests/docker-compose.yml down

test: test-server-up
    swift test
