#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# Temporary workaround until https://github.com/LizardByte/pacman-repo/issues/39 is in stable repo
sudo ln -s /usr/lib/libminiupnpc.so.21 /usr/lib/libminiupnpc.so.19

# Start fake udev daemon
sudo -E /usr/bin/start-fake-udev &
FAKEUDEV_PID=$!

sudo chmod -R 777 /home/appuser/.config

# Workaround for DS5 permission issue in /dev/uhid
sudo setfacl -m g:input:rw /dev/uhid

# --- Seat Management ---
echo "Starting seatd..."
# --- Seat Management ---
echo "Starting seatd for seat-sunshine on ${SEATD_SOCKET_PATH}..."
# Run seatd with debug logging for verification
sudo -E seatd -u appuser -l debug &
SEATD_PID=$!
sleep 0.5

sudo chmod u+s /usr/sbin/bwrap
export STEAM_GAMESCOPE_FANCY_SCALING_SUPPORT=1
export SRT_URLOPEN_PREFER_STEAM=1
export QT_IM_MODULE=steam
export GTK_IM_MODULE=Steam

#ibus-daemon -d -r --panel=disable --emoji-extension=disable &
#$KB_PID=$!

# --- D-Bus System Bus Setup ---
echo "Starting D-Bus system bus..."
# Ensure the directory exists and has correct permissions (might be redundant with Dockerfile changes, but safe)
sudo mkdir -p /run/dbus
sudo chown dbus:dbus /run/dbus
sudo chmod 755 /run/dbus
# Start the system bus daemon
sudo -u dbus dbus-daemon --system --nofork --nopidfile &
DBUS_SYSTEM_PID=$!
echo "D-Bus system bus started with PID $DBUS_SYSTEM_PID"
# No need to export DBUS_SESSION_BUS_ADDRESS for the system bus

# --- D-Bus Setup ---
echo "Starting D-Bus session with dbus-daemon..."
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
dbus-daemon --session --address="${DBUS_SESSION_BUS_ADDRESS}" --nofork --nopidfile &
DBUS_PID=$!
echo "D-Bus daemon started with PID $DBUS_PID at ${DBUS_SESSION_BUS_ADDRESS}"

sleep 0.5

# --- Audio Setup ---
export PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR"
# --- Start Pipewire ---
echo "Starting Pipewire services..."
/usr/bin/pipewire &
PIPEWIRE_PID=$!
/usr/bin/pipewire-pulse &
PULSE_PID=$!
/usr/bin/wireplumber &
WP_PID=$!
echo "Pipewire PIDs: Pipewire=$PIPEWIRE_PID, Pulse=$PULSE_PID, Wireplumber=$WP_PID"


# --- Compositor Launch ---
echo "Starting Labwc (headless)..."
# labwc reads WLR_BACKENDS from its environment file, no need to set it here again
# Labwc will run its autostart script, which launches Sunshine
labwc -m &
LABWC_PID=$!

# Update D-Bus environment for Wayland applications
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=labwc

sleep 0.5

# Set up the environment for WayVNC
wayvnc 0.0.0.0 5900 &
WAYVNC_PID=$!
echo "WayVNC started with PID $WAYVNC_PID"

# Launch Sunshine in the foreground
# It will capture the headless sway output
echo "Starting Sunshine..."
exec /usr/bin/sunshine
# dbus-run-session -- sunshine

# --- Cleanup on exit ---
# This part might not run fully if 'exec' is used above,
# but keep it here in case 'exec' is removed for debugging.
cleanup() {
  echo "Caught signal, shutting down..."
  sudo kill $LABWC_PID || true
  sudo kill $WP_PID || true
  sudo kill $PULSE_PID || true
  sudo kill $PIPEWIRE_PID || true
  sudo kill $DBUS_SYSTEM_PID || true
  sudo kill $DBUS_PID || true
  sudo kill $WAYVNC_PID || true
  sudo kill $SEATD_PID || true
  # sudo kill $BTHD_PID || true
  # sudo kill $NM_PID || true
  sudo kill $FAKEUDEV_PID || true
  # sudo kill $KB_PID || true
  echo "Exited."
}

# Trap signals for graceful shutdown
trap cleanup SIGINT SIGTERM
