SHELL := /bin/bash
SHA ?= $(shell git rev-parse HEAD 2>/dev/null || echo dev)
IMAGE ?= closed-loop-template:$(SHA)
PORT ?= 3000

.PHONY: install lint test check run docker-build smoke

install:
	npm ci --ignore-scripts

lint:
	npm run lint

test:
	npm test

check: lint test
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		APP_ENV_FILE=deploy/app.env.example docker compose \
			--env-file deploy/deploy.env.example \
			-f deploy/docker-compose.prod.yml config >/dev/null; \
		echo "compose config ok"; \
	else \
		echo "skip compose validation: docker daemon not available"; \
	fi

run:
	PORT=$(PORT) node app/server.js

docker-build:
	docker build --build-arg GIT_SHA=$(SHA) -t $(IMAGE) .

smoke: docker-build
	@docker rm -f closed-loop-smoke >/dev/null 2>&1 || true
	@docker run -d --name closed-loop-smoke -p 127.0.0.1:$(PORT):3000 $(IMAGE) >/dev/null
	@trap 'docker rm -f closed-loop-smoke >/dev/null 2>&1 || true' EXIT; \
	for i in $$(seq 1 30); do \
		if curl -fsS http://127.0.0.1:$(PORT)/health >/dev/null 2>&1; then \
			curl -fsS http://127.0.0.1:$(PORT)/version; echo; echo "smoke ok"; exit 0; \
		fi; \
		sleep 1; \
	done; \
	docker logs closed-loop-smoke; exit 1
