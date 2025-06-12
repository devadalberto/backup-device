# Backup Device

This repository contains scripts and a Django backend used to back up media from a phone.

## Usage

The `setup.sh` script provides a unified command line interface:

```bash
./setup.sh create [--db-path=/absolute/host/path]
```

Scaffolds the Django project inside `backend/`. Pass `--db-path` to bind mount an existing directory for PostgreSQL data.
The scaffold also adds a basic Ninja API and a gallery view.

```bash
./setup.sh attach-phone
```

Lists USB devices from Windows, attaches the selected one to WSL and starts the Docker stack. The phone will be paired and mounted inside the `web` container.

```bash
./setup.sh cleanup
```

Stops and removes the Docker containers and volumes.

The legacy scripts (`create_backup_device.sh` and `attach_phone_and_run.sh`) remain, but using `setup.sh` is recommended.
