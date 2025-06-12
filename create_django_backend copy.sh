#!/usr/bin/env bash
# create_backup_device.sh
# -------------------------------------------------
# • Scaffolds the *backup_device* Django project
# • Adds Dockerfile, docker-compose.yml, Makefile
# • Supports either host bind-mount or named volume
#   for PostgreSQL 16 data
# -------------------------------------------------
set -euo pipefail
trap 'echo "Error at line $LINENO"; exit 1' ERR

# ---------- CLI Arguments -------------------------
DB_PATH=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --db-path=*) DB_PATH="${1#*=}"; shift ;;
    -h|--help)
      echo "Usage: $0 [--db-path=/absolute/host/dir]"; exit 0 ;;
    *) echo "Unknown argument: $1" ; exit 1 ;;
  esac
done

# ---------- Interactive Prompt -------------------
if [[ -z "$DB_PATH" ]]; then
  read -rp "Bind-mount a host directory for Postgres data? [y/N] " yn
  if [[ $yn =~ ^[Yy]$ ]]; then
    while true; do
      read -rp "Enter absolute path (will be created if missing): " DB_PATH
      if [[ "$DB_PATH" = /* ]]; then
        mkdir -p "$DB_PATH" || echo "Warning: Could not create directory"
        break
      else
        echo "Error: Path must be absolute (start with '/'). Try again."
      fi
    done
  fi
fi

# ---------- Environment Setup --------------------
SECRET_KEY=$(python -c "import secrets; print(secrets.token_urlsafe(50))")
cat > .env.example <<EOF
# PostgreSQL
POSTGRES_DB=devices_media
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_PORT=5432

# Django
DJANGO_SECRET_KEY=$SECRET_KEY
DJANGO_DEBUG=0
BACKUP_DEST=/backups
ALLOWED_HOSTS=localhost,127.0.0.1,backup-device
CSRF_TRUSTED_ORIGINS=http://localhost,http://127.0.0.1

# Project
PROJECT_NAME=backend
EOF
cp .env.example .env

# ---------- Python Requirements ------------------
cat > requirements.txt <<'REQ'
django==4.2.11
gunicorn==21.2.0
whitenoise[brotli]==6.6.0
django-ninja==0.22.2
django-taggit==4.0.0
python-dotenv==1.0.1
psycopg2-binary==2.9.9
tqdm==4.66.2
REQ

# Create virtual environment
python -m venv .venv
source .venv/bin/activate
pip install --upgrade pip wheel
pip install -r requirements.txt

# ---------- Project Scaffolding ------------------
# Create project without dot to generate config directory
django-admin startproject config

mv config ${PROJECT_NAME}
cd ${PROJECT_NAME}

# Create apps
django-admin startapp media_lake
django-admin startapp backup_device

# ---------- Settings Modifications ---------------
# Modify settings file
cat > config/settings.py <<'EOF'
from pathlib import Path
import os

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = os.getenv('DJANGO_SECRET_KEY')
DEBUG = os.getenv('DJANGO_DEBUG', '0') == '1'
ALLOWED_HOSTS = os.getenv('ALLOWED_HOSTS', '').split(',')
CSRF_TRUSTED_ORIGINS = os.getenv('CSRF_TRUSTED_ORIGINS', '').split(',')

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'whitenoise.runserver_nostatic',
    'django_ninja',
    'django_taggit',
    'media_lake',
    'backup_device',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'config.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'config.wsgi.application'

# Database
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.getenv('POSTGRES_DB'),
        'USER': os.getenv('POSTGRES_USER'),
        'PASSWORD': os.getenv('POSTGRES_PASSWORD'),
        'HOST': 'db',
        'PORT': os.getenv('POSTGRES_PORT', '5432'),
    }
}

# Password validation
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

# Internationalization
LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

# Static files
STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'static'
STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'

# Media files
MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'

# Backup configuration
BACKUP_DEST = os.getenv('BACKUP_DEST', '/backups')
EOF

# ---------- URL Configuration --------------------
cat > config/urls.py <<'EOF'
from django.contrib import admin
from django.urls import path
from config.views.health import health_check

urlpatterns = [
    path('admin/', admin.site.urls),
    path('health/', health_check, name='health_check'),
]
EOF

# Health check view
mkdir -p config/views
cat > config/views/health.py <<'EOF'
from django.http import JsonResponse

def health_check(request):
    return JsonResponse({"status": "ok", "service": "backup_device"})
EOF

# Create core directories
mkdir -p media static

# ---------- Docker Setup -------------------------
cat > Dockerfile <<'DOCK'
# Builder stage
FROM python:3.12-slim as builder

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev

COPY requirements.txt .
RUN pip wheel --no-cache-dir --no-deps --wheel-dir=/app/wheels -r requirements.txt

# Final stage
FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/wheels /wheels
COPY --from=builder /app/requirements.txt .

RUN pip install --no-cache /wheels/* \
    && rm -rf /wheels

COPY . .

RUN python manage.py collectstatic --noinput

# Create media directory
RUN mkdir -p media

# Gunicorn configuration
CMD ["gunicorn", "config.wsgi:application", \
    "--bind", "0.0.0.0:8000", \
    "--workers", "4", \
    "--worker-class", "gthread", \
    "--threads", "2", \
    "--timeout", "120", \
    "--access-logfile", "-"]
DOCK

# Create .dockerignore
cat > .dockerignore <<'EOF'
**/__pycache__
**/*.pyc
**/*.pyo
**/*.pyd
.venv
.env
.git
.gitignore
.vscode
.idea
docker-compose.yml
Dockerfile
Makefile
README.md
backups
media
static
EOF

# docker-compose.yml
cat > docker-compose.yml <<EOF
version: "3.9"

services:
  web:
    build:
      context: .
      dockerfile: Dockerfile
    env_file: .env
    volumes:
      - media_volume:/app/media
      - backups_volume:/backups
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "8000:8000"
    restart: unless-stopped
    networks:
      - backend
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health/"]
      interval: 30s
      timeout: 10s
      retries: 3

  db:
    image: postgres:16
    env_file: .env
    restart: unless-stopped
    networks:
      - backend
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER}"]
      interval: 5s
      timeout: 5s
      retries: 5
EOF

# Add volume configuration based on choice
if [[ -n "$DB_PATH" ]]; then
  cat >> docker-compose.yml <<EOF
    volumes:
      - ${DB_PATH}:/var/lib/postgresql/data
EOF
else
  cat >> docker-compose.yml <<EOF
    volumes:
      - pgdata_backup_device:/var/lib/postgresql/data
EOF
fi

# Add volume declarations
cat >> docker-compose.yml <<EOF
volumes:
  media_volume:
  backups_volume:
EOF

if [[ -z "$DB_PATH" ]]; then
  cat >> docker-compose.yml <<EOF
  pgdata_backup_device:
EOF
fi

cat >> docker-compose.yml <<EOF
networks:
  backend:
    driver: bridge
EOF

# ---------- Makefile -----------------------------
cat > Makefile <<'MAKE'
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
	docker compose exec web python manage.py shell

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
MAKE

# ---------- Finalization -------------------------
echo "Project scaffolding complete"
echo ""
echo "Next steps:"
echo "1. Edit configuration: nano .env"
echo "2. Build containers: make build"
echo "3. Start services: make up"
echo "4. Run migrations: make migrate"
echo "5. Create superuser: make superuser"
echo "6. Access at: http://localhost:8000"
echo ""
echo "Management commands:"
echo "  make backup      # Trigger media backup"
echo "  make restore     # Restore media"
echo "  make health      # Check service status"
