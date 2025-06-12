#!/usr/bin/env bash
# Unified command interface for the backup-device project
set -euo pipefail
trap 'echo "Error at line $LINENO" >&2; exit 1' ERR

usage() {
    cat <<USAGE
Usage: $0 <command> [options]

Commands:
  create         Scaffold the Django project
  attach-phone   Attach a phone and start services
  cleanup|down   Stop and remove Docker services
USAGE
    exit 1
}

[[ $# -gt 0 ]] || usage
cmd=$1; shift

case "$cmd" in
    create)
        "$(dirname "$0")/create_backup_device.sh" "$@"
        ;;
    attach-phone)
        "$(dirname "$0")/attach_phone_and_run.sh" "$@"
        ;;
    cleanup|down)
        docker compose down -v
        ;;
    -h|--help)
        usage
        ;;
    *)
        echo "Unknown command: $cmd" >&2
        usage
        ;;
esac
