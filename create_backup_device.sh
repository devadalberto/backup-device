#!/usr/bin/env bash
# create_backup_device.sh
# -------------------------------------------------
# • Scaffolds the *backup_device* Django project
#   inside a top-level "backend" folder
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
      echo "Usage: $0 [--db-path=/absolute/host/dir]"
      exit 0 ;;
    *) echo "Unknown argument: $1" ; exit 1 ;;
  esac
done

# ---------- Interactive Prompt --------------------
if [[ -z "$DB_PATH" ]]; then
  read -rp "Bind-mount a host directory for Postgres data? [y/N] " yn
  if [[ $yn =~ ^[Yy]$ ]]; then
    while true; do
      read -rp "Enter absolute path (will be created if missing): " DB_PATH
      if [[ "$DB_PATH" = /* ]]; then
        mkdir -p "$DB_PATH" || echo "Warning: Could not create directory"
        break
      else
        echo "Error: path must be absolute (start with '/'). Try again."
      fi
    done
  fi
fi

# ---------- Project Root --------------------------
mkdir -p backend
cd backend

# ---------- Environment Setup ---------------------
SECRET_KEY=$(python - <<'PY'
import secrets, os, textwrap, json, sys
print(secrets.token_urlsafe(50))
PY
)

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

# ---------- Python Requirements -------------------
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

# ---------- Optional local venv (convenience) -----
if [[ ! -d .venv ]]; then
  python -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
pip install --upgrade pip wheel
pip install -r requirements.txt

# ---------- Django Project ------------------------
django-admin startproject config .
python manage.py startapp media_lake
python manage.py startapp backup_device

cat > backup_device/models.py <<'PY'
from django.db import models


class Device(models.Model):
    """Simple device representation."""

    name = models.CharField(max_length=100)
    created = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:  # pragma: no cover - simple representation
        return self.name
PY

cat > media_lake/models.py <<'PY'
from backup_device.models import Device
from django.db import models


class MediaFile(models.Model):
    """File stored in the media lake."""

    device = models.ForeignKey(
        Device, on_delete=models.CASCADE, related_name="media_files"
    )
    file = models.FileField(upload_to="uploads/")
    uploaded = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:  # pragma: no cover - simple representation
        return self.file.name
PY

cat > media_lake/views.py <<'PY'
from django.shortcuts import render

from .models import MediaFile


def gallery(request):
    """Display thumbnails and metadata for all ``MediaFile`` instances."""

    media_files = MediaFile.objects.all()
    return render(request, "media_lake/gallery.html", {"media_files": media_files})
PY

mkdir -p media_lake/templates/media_lake
cat > media_lake/templates/media_lake/gallery.html <<'HTML'
{% extends 'base.html' %}
{% block content %}
<h1>Media Gallery</h1>
<ul>
  {% for media in media_files %}
  <li>
    <img src="{{ media.thumbnail_url }}" alt="{{ media.name }}"/>
    <p>{{ media.metadata }}</p>
  </li>
  {% empty %}
  <li>No media files found.</li>
  {% endfor %}
</ul>
{% endblock %}
HTML

cat > api.py <<'PY'
from typing import List

from backup_device.models import Device
from django.shortcuts import get_object_or_404
from media_lake.models import MediaFile
from ninja import File, ModelSchema, NinjaAPI
from ninja.files import UploadedFile


class DeviceSchema(ModelSchema):
    class Config:
        model = Device
        model_fields = ["id", "name", "created"]


class DeviceCreateSchema(ModelSchema):
    class Config:
        model = Device
        model_fields = ["name"]


class MediaFileSchema(ModelSchema):
    class Config:
        model = MediaFile
        model_fields = ["id", "device_id", "file", "uploaded"]


api = NinjaAPI()


@api.get("/devices/", response=List[DeviceSchema])
def list_devices(request):
    return Device.objects.all()


@api.post("/devices/", response=DeviceSchema)
def create_device(request, payload: DeviceCreateSchema):
    device = Device.objects.create(**payload.dict())
    return device


@api.get("/media/", response=List[MediaFileSchema])
def list_media(request):
    return MediaFile.objects.all()


@api.post("/media/", response=MediaFileSchema)
def upload_media(request, device_id: int, file: UploadedFile = File(...)):
    device = get_object_or_404(Device, id=device_id)
    media = MediaFile.objects.create(device=device, file=file)
    return media
PY


# Add the two apps to INSTALLED_APPS
python - <<'PY'
import re, pathlib, sys, textwrap, json, os
settings = pathlib.Path("config/settings.py")
txt = settings.read_text()
pattern = r"INSTALLED_APPS\s*=\s*\["
if re.search(pattern, txt) and 'media_lake' not in txt:
    txt = re.sub(
        pattern,
        "INSTALLED_APPS = [\n    'media_lake',\n    'backup_device',",
        txt,
        count=1,
    )
settings.write_text(txt)
PY

# ---------- Replace settings.py -------------------
cat > config/settings.py <<'PY'
from pathlib import Path
import os, dj_database_url

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = os.getenv('DJANGO_SECRET_KEY', 'unsafe-secret-key')
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
    'taggit',
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

AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

STATIC_URL = '/static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'

MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'

BACKUP_DEST = os.getenv('BACKUP_DEST', '/backups')

# Configure default primary key field type to avoid warnings
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'
PY

# ---------- health check view ---------------------
mkdir -p config/views
cat > config/views/health.py <<'PY'
from django.http import JsonResponse


async def health_check(request):
    return JsonResponse({"status": "ok", "service": "backup_device"})
PY

cat > config/urls.py <<'PY'
from api import api
from config.views.health import health_check
from django.contrib import admin
from django.urls import path
from media_lake.views import gallery

urlpatterns = [
    path("admin/", admin.site.urls),
    path("health/", health_check, name="health_check"),
    path("gallery/", gallery, name="gallery"),
    path("api/", api.urls),
]
PY

# ---------- Project Media / Static dirs -----------
mkdir -p media staticfiles

# ---------- Dockerfile ----------------------------
cat > Dockerfile <<'DOCK'
# Builder stage
FROM python:3.12-slim AS builder
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libpq-dev
COPY requirements.txt .
RUN pip wheel --no-cache --no-deps --wheel-dir /app/wheels -r requirements.txt

# Final image
FROM python:3.12-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends libpq-dev \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/wheels /wheels
COPY --from=builder /app/requirements.txt .
RUN pip install --no-cache /wheels/* && rm -rf /wheels
COPY . .
RUN python manage.py collectstatic --noinput
CMD ["gunicorn", "config.wsgi:application", \
     "--bind", "0.0.0.0:8000", \
     "--workers", "4", \
     "--worker-class", "gthread", \
     "--threads", "2", \
     "--timeout", "120", \
     "--access-logfile", "-"]
DOCK

# ---------- .dockerignore -------------------------
cat > .dockerignore <<'EOF'
**/__pycache__
*.py[cod]
*.pyo
.venv
.env
.git
*.log
EOF

# ---------- docker-compose.yml --------------------
cat > docker-compose.yml <<EOF
version: "3.9"

services:
  web:
    build: .
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

# Append bind-mount or named volume
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

# Volume declarations & network
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

cat > docker-compose.override.yml <<'YML'
# docker-compose.override.yml
services:
  web:
    privileged: true            # allow FUSE & raw USB
    devices:
      - "/dev/bus/usb:/dev/bus/usb"
    cap_add:
      - SYS_ADMIN               # needed by ifuse
      - SYS_RAWIO
YML

# ---------- Makefile ------------------------------
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
MAKE

# ---------- Finalisation --------------------------
echo -e "\n🎉  Project scaffolding complete!\n"
echo "Next steps:"
echo "  1. cd backend"
echo "  2. Review .env"
echo "  3. make build"
echo "  4. make up"
echo "  5. make migrate"
echo "  6. make superuser"
echo -e "Access: http://localhost:8000 (admin at /admin)\n"
