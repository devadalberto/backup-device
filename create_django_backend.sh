# Create project root directory and navigate into it
mkdir backend
cd backend

# Initialize Django project and apps
django-admin startproject config .
python manage.py startapp media_lake
python manage.py startapp backup_device

# Add apps to settings.py (Linux/Mac)
sed -i '' "s/INSTALLED_APPS = \[/INSTALLED_APPS = \[\n    'media_lake',\n    'backup_device',/g" config/settings.py

# Create Dockerfile
cat > Dockerfile <<EOF
FROM python:3.9
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1
WORKDIR /code
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
EOF

# Create docker-compose.yml
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  backend:
    build: .
    command: sh -c "python manage.py migrate && python manage.py runserver 0.0.0.0:8000"
    volumes:
      - .:/code
    ports:
      - "8000:8000"
    env_file:
      - .env
EOF

# Create requirements.txt
echo "django>=3.2,<4.0" > requirements.txt

# Create .env with secure key
echo "SECRET_KEY=$(python -c 'import secrets; print(secrets.token_urlsafe(38))')" > .env
echo "DEBUG=1" >> .env

# Create .dockerignore
cat > .dockerignore <<EOF
**/__pycache__
.gitignore
.env
Dockerfile
docker-compose.yml
.git
EOF

# Build and start container
docker-compose up --build
