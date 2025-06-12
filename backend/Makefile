.PHONY: build up down logs psql shell migrate superuser backup restore health

build:
	docker compose build --pull --no-cache

up:
	docker compose up -d

down:
	docker compose down -v

logs:
	docker compose logs -f --tail=100

psql:
	docker compose exec db psql -U $$(grep POSTGRES_USER .env | cut -d= -f2) -d $$(grep POSTGRES_DB .env | cut -d= -f2)

shell:
	docker compose exec web python manage.py shell_plus

migrate:
	docker compose exec web python manage.py migrate

superuser:
	docker compose exec web python manage.py createsuperuser

backup:
	docker compose exec web python manage.py backup_media

restore:
	docker compose exec web python manage.py restore_media

health:
	curl -f http://localhost:8000/health/ || echo "Service unavailable"
