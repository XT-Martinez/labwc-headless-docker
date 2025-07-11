# Base Arch Linux image
FROM archlinux:latest

RUN echo -e '\n\
    [lizardbyte] \n\
    SigLevel = Optional \n\
    Server = https://github.com/LizardByte/pacman-repo/releases/latest/download/ \n\
    \n\
    [multilib] \n\
    Include = /etc/pacman.d/mirrorlist \n\
    ' >> /etc/pacman.conf

ENV XDG_RUNTIME_DIR=/run/user/1000

# Create non-root user 'appuser' with UID/GID 1000
RUN useradd -m -u 1000 -G wheel,video,audio,input -s /bin/bash appuser && \
    # Add user to necessary groups for input, video, audio, rendering
    usermod -aG input,video,audio,render appuser && \
    # Allow sudo for easier debugging inside the container (optional, remove for production)
    echo 'appuser ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers && \
    mkdir -p "$XDG_RUNTIME_DIR" /home/appuser/.config && \
    chown -R appuser:appuser "$XDG_RUNTIME_DIR" /home/appuser && \
    chmod 0700 "$XDG_RUNTIME_DIR" && \
    # Prepare D-Bus system bus environment
    dbus-uuidgen --ensure && \
    mkdir -p /run/dbus && \
    chown dbus:dbus /run/dbus && \
    chmod 755 /run/dbus && \
    dbus-uuidgen > /etc/machine-id

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed base-devel git sudo vim

USER appuser
WORKDIR /home/appuser

RUN git clone https://aur.archlinux.org/paru.git && \
    cd paru && \
    makepkg -si --noconfirm && \
    cd .. && \
    rm -rf paru

# Install Heroic Games Launcher from AUR
RUN paru -S --noconfirm heroic-games-launcher-bin sfwbar lisgd

USER root

# Update system and install necessary packages
RUN pacman -S --noconfirm --needed \
    # labwc and Wayland essentials
    labwc xorg-xwayland wlr-randr \
    wayland \
    wayland-protocols \
    xdg-desktop-portal-wlr \
    wayvnc \
    # Sunshine and dependencies
    sunshine \
    # Audio
    pipewire pipewire-pulse wireplumber libpulse \
    # Input and devices
    libinput udev evtest \
    # D-Bus
    dbus dbus-broker \
    # Fonts and basic terminal
    ttf-dejavu adwaita-fonts ttf-font-awesome kitty \
    # UI Components
    waybar rofi-wayland networkmanager swaybg mako \
    # Utilities
    mesa inetutils xdg-utils thunar curl 7zip unzip zip cabextract zenity file-roller \
    # Graphics drivers (Mesa for software/headless rendering)
    libva-mesa-driver vulkan-intel vulkan-radeon vulkan-icd-loader \
    vulkan-mesa-layers vulkan-tools \
    # Intel media driver for hardware-accelerated video decoding
    intel-media-driver libva-utils \
    # Gaming deps
    mangohud lib32-mangohud gamescope gamemode lib32-gamemode fuse2 wine-staging \
    # 32-bit libraries
    lib32-glibc lib32-sdl2-compat \
    lib32-freetype2 \
    lib32-libva-intel-driver \
    lib32-libva-mesa-driver \
    lib32-mesa-utils \
    lib32-mesa \
    lib32-vulkan-radeon \
    lib32-vulkan-intel \
    libva-intel-driver \
    lib32-vulkan-mesa-layers \
    libva-utils \
    mesa \
    lib32-gcc-libs \
    lib32-libpulse \
    lib32-libunwind \
    lib32-renderdoc-minimal \
    # Apps
    chromium

RUN usermod -aG seat,input appuser

# Expose Sunshine ports (actual mapping happens in docker-compose)
EXPOSE 5900
EXPOSE 48010/tcp
EXPOSE 47984/udp
EXPOSE 47989/udp
EXPOSE 47990/udp

# Switch to non-root user
# Add dbus user to necessary groups if needed (e.g., for specific hardware access)
RUN usermod -aG seat,input dbus

ENV PUID=1000
ENV PGID=1000
ENV HOME=/home/appuser
ENV UNAME=appuser
ENV DISPLAY=:0
ENV XDG_SESSION_CLASS=user
ENV XDG_SESSION_ID=1
ENV LIBSEAT_BACKEND=seatd
ENV WLR_BACKENDS=headless,libinput
ENV WLR_RENDERER=vulkan
ENV WLR_LIBINPUT_NO_DEVICES=1
ENV XDG_CURRENT_DESKTOP=labwc
ENV XDG_SESSION_DESKTOP=labwc
ENV XDG_SESSION_TYPE=wayland
ENV GTK_THEME=Adwaita:dark
ENV WAYLAND_DISPLAY=wayland-0
ENV SEATD_VTBOUND=0

COPY executables/fake-udev /usr/bin/fake-udev
RUN chmod +x /usr/bin/fake-udev

COPY executables/start-fake-udev.sh /usr/bin/start-fake-udev
RUN chmod +x /usr/bin/start-fake-udev

COPY executables/makima /usr/bin/makima
RUN chmod +x /usr/bin/makima

COPY executables/rofi-makima.sh /usr/bin/rofi-makima
RUN chmod +x /usr/bin/rofi-makima

COPY --chown=appuser:appuser config/electron-flags.conf /home/appuser/.config/electron-flags.conf
COPY --chown=appuser:appuser config/electron-flags.conf /home/appuser/.config/chromium-flags.conf

# Copy and set permissions for the entrypoint script
COPY --chown=appuser:appuser entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER appuser

# Define the entrypoint
ENTRYPOINT ["/entrypoint.sh"]
