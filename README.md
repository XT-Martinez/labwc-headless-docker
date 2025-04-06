# Labwc Headless Docker with Advanced Input Handling

This project runs a headless Labwc Wayland session inside a Docker container, primarily designed for remote access via Sunshine and WayVNC. It features isolated input device handling (thanks to this [post](https://games-on-whales.github.io/wolf/stable/dev/fake-udev.html) from the [Wolf project](https://games-on-whales.github.io/wolf/stable/index.html)), allowing passthrough of keyboards, mice, touchscreens, and gamepads, along with custom gesture recognition ([lisgd](https://git.sr.ht/~mil/lisgd)) and button remapping ([Makima](https://github.com/cyber-sushi/makima)).

## Key Features

*   **Labwc:** Lightweight Wayland compositor based on wlroots.
*   **Sunshine:** Self-hosted, low-latency game stream host compatible with Moonlight clients.
*   **WayVNC:** VNC server for Wayland compositors.
*   **Pipewire:** Modern audio server for handling audio within the container.
*   **Fake Udev (`start-fake-udev.sh`):** Custom script that monitors host udev events for specific input devices and simulates their addition/removal within the container using `mknod` and `fake-udev` from the Wolf project. This provides input device isolation.
*   **`lisgd`:** Touchscreen gesture daemon. Integrated with `start-fake-udev.sh` to start/stop automatically when a "Touch passthrough" device is detected/removed. Gestures are configured directly within `start-fake-udev.sh`.
    *   *Default Gestures (Configured in `start-fake-udev.sh`):*
        *   3-finger swipe UP: Launch `kitty` terminal.
        *   3-finger swipe DOWN: Launch `rofi` application launcher (with D-PAD navigation).
*   **`makima`:** Input device remapper daemon. Used here primarily to remap gamepad D-PAD inputs to keyboard arrow keys, enabling gamepad navigation in applications like Rofi. Configuration is per-device.
*   **Rofi Wrapper (`rofi-makima.sh`):** A script designed to launch `makima` *only* when Rofi is active and kill it when Rofi closes. This works around `makima`'s lack of application-specific binding support under Labwc.
*   **Configuration via Volumes:** Most application configurations are mounted from the host, allowing easy customization without rebuilding the container.

## Prerequisites

*   **Docker & Docker Compose:** Ensure Docker and Docker Compose (or `docker compose`) are installed on the host system.
*   **Host User Permissions:** The user running Docker needs appropriate permissions to manage Docker.
*   **`input` Group:** The host user should ideally be part of the `input` group to allow monitoring udev events (though the script runs as root inside the container, access might still be relevant depending on host setup). The container explicitly adds the `appuser` to group GID `104` (a common `input` GID) - **verify this GID matches the `input` group GID on your host** (`getent group input | cut -d: -f3`) and adjust the `group_add` section in `docker-compose.yml` if necessary.
*   **Kernel Modules:** Ensure the `uinput` kernel module is loaded on the host (`sudo modprobe uinput`). You might need to configure it to load automatically on boot.
*   **Graphics Drivers:** Appropriate host graphics drivers (e.g., NVIDIA, AMD, Intel) are required for GPU acceleration within the container (passed via `/dev/dri`).

## Configuration

This project uses configuration files mounted from the host into the container. Key configuration directories within this repository are:

*   `config/labwc/`: Labwc configuration (`rc.xml`, `autostart`, `themerc`, etc.).
*   `config/sunshine/`: Sunshine configuration files.
*   `config/makima/`: Makima device remapping configuration files.
    *   Files must be named exactly after the device name reported by `evtest` or `libinput list-devices` (e.g., `Sunshine X-Box One (virtual) pad.toml`).
    *   Place your `.toml` files here; they will be mounted to `/home/appuser/.config/makima` inside the container.
*   `config/sfwbar/`: Configuration for sfwbar (if used).
*   `config/wireplumber/`: Pipewire session manager configuration.
*   `executables/`: Contains helper scripts.
    *   `start-fake-udev.sh`: Manages device simulation and starts/stops `lisgd`. Gesture commands are configured here.
    *   `rofi-makima.sh`: Wrapper script to run `makima` alongside Rofi. **Note:** This script uses `sudo` internally and requires the `appuser` (UID 1000) inside the container to have passwordless `sudo` permissions for `makima` and `kill`, or the script needs modification. You also need to ensure this script is placed in a location accessible within the container's `$PATH` or called via its full path. The Labwc `rc.xml` and `start-fake-udev.sh` should be updated to call this script instead of `rofi` directly if you want the conditional `makima` behavior.

Modify the files in these directories on the host to customize the container's behavior.

## Build

To build the Docker image:

```bash
docker compose build
# or
docker-compose build
```

## Run

To start the container in detached mode:

```bash
docker compose up -d
# or
docker-compose up -d
```

## Connecting

*   **Sunshine:** Access the Sunshine web UI (usually `https://<host-ip>:47990`) to pair clients (like Moonlight). Streaming occurs over the other configured ports.
*   **WayVNC:** Connect using a VNC client to `<host-ip>:5900`.

## Input Handling Explained

The container uses a multi-layered approach for input devices passed through from the host:

1.  **`start-fake-udev.sh`:** Runs inside the container with elevated privileges. It monitors host `udevadm` events for specific device names (configured in the script). When a target device is added/removed on the host, this script creates/removes the corresponding `/dev/input/event*` node inside the container using `mknod` and sends a simulated udev event using the `fake-udev` utility. This makes the container's system (and compositors like Labwc) aware of the device.
2.  **`lisgd`:** This script also starts/stops `lisgd` when a "Touch passthrough" device is added/removed, binding gestures defined within the script itself.
3.  **`makima`:** This daemon reads device events directly. It's configured via `.toml` files named after specific devices. It can remap buttons/keys. In this setup, it's used to map gamepad D-PAD events to keyboard arrow keys. It can be run constantly as a service or conditionally using the `rofi-makima.sh` wrapper.

## Troubleshooting

*   **Logs:** Check container logs for errors: `docker compose logs -f labwc-sunshine` (or `docker-compose ...`).
*   **Permissions:** Ensure correct host user permissions (Docker group) and that the `input` group GID in `docker-compose.yml` matches the host. Check `/dev/dri`, `/dev/uinput`, `/dev/uhid` permissions on the host.
*   **Device Names:** Verify the device names in `start-fake-udev.sh` and the filenames in `config/makima/` match the actual device names reported by `evtest` or `libinput list-devices` on the *host*.
*   **`rofi-makima.sh` Sudo:** If using the wrapper script, ensure the `appuser` (UID 1000) inside the container has the necessary passwordless `sudo` rights configured, or modify the script to avoid `sudo` if `makima` can run without it (depends on group memberships and device permissions).
