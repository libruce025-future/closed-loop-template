SHELL := /bin/bash
SHA ?= $(shell git rev-parse HEAD 2>/dev/null || echo dev)
PORT ?= 3000

.PHONY: install lint build test check run

install:
	npm ci --ignore-scripts

lint:
	npm run lint

build:
	SHA=$(SHA) npm run build

test:
	SHA=$(SHA) npm test

check: lint build test

run: build
	PORT=$(PORT) node scripts/serve.mjs
