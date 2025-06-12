#!/usr/bin/env bash
# attach_phone_and_run.sh
# -------------------------------------------------
# 1. Lists Windows USB devices (usbipd list)
# 2. Attaches the chosen device to WSL 2
#    – On "Device busy" it tries bind --force
# 3. Builds and starts the Docker stack
# 4. Pairs and mounts the phone at /mnt/phone inside the web container
# -------------------------------------------------
set -euo pipefail
trap 'echo "ERROR: stopped at line $LINENO" >&2; exit 1' ERR

COMPOSE="docker compose"

# ---------- Step 1: list devices on Windows -------------------------------
echo
echo "Windows USB devices:"
WIN_USB_LIST=$(usbipd.exe list)
if [ -z "$WIN_USB_LIST" ]; then
  echo "No devices found or usbipd.exe not in PATH."
  exit 1
fi

echo "$WIN_USB_LIST" | nl -ba
echo
read -rp "Enter the number of the device to attach to WSL: " IDX

BUSID=$(echo "$WIN_USB_LIST" | sed -n "${IDX}p" | awk '{print $1}')
if [ -z "$BUSID" ]; then
  echo "Invalid selection."
  exit 1
fi

# ---------- Step 2: attach (with busy fallback) ---------------------------
echo
echo "Attaching busid $BUSID to WSL..."
if ! usbipd.exe attach --wsl --busid "$BUSID"; then
  echo "Attach failed. Trying bind --force then re-attach."
  if ! usbipd.exe bind --busid "$BUSID" --force; then
    echo "usbipd bind failed. Run an elevated PowerShell prompt:"
    echo "  usbipd bind --busid $BUSID --force"
    exit 1
  fi
  sleep 1
  if ! usbipd.exe attach --wsl --busid "$BUSID"; then
    echo "Attach still failed. Ensure the device is not in use by Windows and try again."
    exit 1
  fi
fi

sleep 2
echo "Device appears attached. lsusb output:"
lsusb | grep "$BUSID" || echo "Device not yet visible in lsusb."

# ---------- Step 3: ensure host tools -------------------------------------
sudo apt-get update
sudo apt-get install -y libimobiledevice-utils ifuse usbmuxd jmtpfs adb fuse

# ---------- Step 4: build / start Docker stack ---------------------------
echo
echo "Building and starting Docker services..."
$COMPOSE pull
$COMPOSE build
$COMPOSE up -d

# ---------- Step 5: pair and mount inside container -----------------------
echo
echo "Pairing or mounting phone inside container..."
$COMPOSE exec -T web bash -c '
  set -e
  mkdir -p /mnt/phone
  if command -v idevicepair >/dev/null 2>&1; then
      idevicepair pair || true
      if ifuse /mnt/phone --camera 2>/dev/null; then
          echo "iPhone camera roll mounted at /mnt/phone"
      elif ifuse /mnt/phone --documents 2>/dev/null; then
          echo "iPhone documents mounted at /mnt/phone"
      else
          echo "ifuse could not mount the iPhone. Is it unlocked and trusted?"
      fi
  else
      if jmtpfs /mnt/phone 2>/dev/null; then
          echo "Android MTP storage mounted at /mnt/phone"
      else
          echo "jmtpfs failed. Enable File Transfer (MTP) on the phone."
      fi
  fi
'

echo
echo "Setup complete."
echo "Run 'make backup' to copy media."
echo
echo "When finished, detach the device in Windows PowerShell:"
echo "  usbipd.exe detach --busid $BUSID"
