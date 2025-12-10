default: test

up:
    docker compose -f Tests/Server/docker-compose.yml up -d

down:
    docker compose -f Tests/Server/docker-compose.yml down

test: up
    swift test
