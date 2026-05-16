# Short commands — run from repo root:  make dev | make prod
.PHONY: setup dev prod down down-dev logs logs-dev restart ps shell check-env backup

check-env:
	@test -f .env || (echo "Missing .env — run: make setup" && exit 1)

setup:
	./scripts/setup.sh

dev: check-env
	@test -f config/odoo.dev.conf || (echo "Missing config/odoo.dev.conf — run: make setup" && exit 1)
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

prod: check-env
	@test -f config/odoo.conf || (echo "Missing config/odoo.conf — run: make setup" && exit 1)
	docker compose --profile production up -d --build

down:
	docker compose --profile production down

down-dev:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml down

logs:
	docker compose --profile production logs -f web --tail 100

logs-dev:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml logs -f web --tail 100

restart:
	docker compose --profile production restart web

ps:
	docker compose --profile production ps

shell:
	docker compose --profile production exec web bash

backup:
	@test -f .env || (echo "Missing .env — run: make setup" && exit 1)
	./scripts/backup.sh
