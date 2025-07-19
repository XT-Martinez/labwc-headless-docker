#!/bin/bash

# --- Configuration ---
# Names found in the parent device events
TARGET_PARENT_DEVICE_NAMES=(
    "Keyboard passthrough"
    "Mouse passthrough"
    "Wolf mouse (abs) virtual device"
    "Mouse passthrough (absolute)"
    "Touch passthrough"
    "Pen passthrough"
    "Sunshine Nintendo (virtual) pad"
    "Sunshine X-Box One (virtual) pad"
    # DS5
    "Sunshine DualSense (virtual) pad"
    "Sunshine DualSense (virtual) pad Motion Sensors"
    "Sunshine DualSense (virtual) pad Touchpad"
    "Sunshine PS5 (virtual) pad"
    # "Sunshine PS5 (virtual) pad Motion Sensors"
    # "Sunshine PS5 (virtual) pad Touchpad"
    # Makima
    "Makima Virtual Keyboard/Mouse"
)

# --- Global State ---
declare -A parent_device_names # Map: Parent DEVPATH -> NAME
declare -A parent_device_uniqs # Map: Parent DEVPATH -> UNIQ
declare -A lisgd_pids          # Map: DEVNAME -> lisgd PID

# --- Helper Functions ---
log_debug() {
    if [[ "$DEBUG" -eq 1 ]]; then
        echo "[DEBUG] $@" >&2
    fi
}

log_info() {
    echo "[INFO] $@" >&2
}

log_error() {
    echo "[ERROR] $@" >&2
}

# Function to check if a value exists in an array
contains_element() {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

# Function to convert multi-line udev properties (from stdin) to null-separated string
properties_to_null_separated() {
    # Reads from stdin
    # Prints null byte BEFORE lines 2+, avoids trailing null byte
    awk 'NR > 1 { printf "\\0" }; { printf "%s", $0 }'
}

# Function to generate a random locally administered MAC address (e.g., 02:XX:XX:XX:XX:XX)
generate_random_mac() {
    local rand_bytes
    # Prefer openssl if available
    if command -v openssl &> /dev/null; then
        rand_bytes=$(openssl rand -hex 5)
    else
        # Fallback using /dev/urandom and hexdump/xxd
        if command -v hexdump &> /dev/null; then
             rand_bytes=$(head -c 5 /dev/urandom | hexdump -v -e '/1 "%02x"')
        elif command -v xxd &> /dev/null; then
             rand_bytes=$(head -c 5 /dev/urandom | xxd -p)
        else
             # Basic fallback
             rand_bytes=$(for i in {1..5}; do printf '%02x' $((RANDOM % 256)); done)
        fi
    fi
    # Format with colons
    printf '02:%s\n' "$(echo "$rand_bytes" | sed 's/\(..\)/\1:/g; s/:$//')"
}

# --- Cleanup Function ---
cleanup() {
    log_info "Cleaning up lisgd processes..."
    if [[ ${#lisgd_pids[@]} -gt 0 ]]; then
        for devname in "${!lisgd_pids[@]}"; do
            local pid="${lisgd_pids[$devname]}"
            log_info "Killing lisgd (PID: $pid) for device $devname"
            kill "$pid" 2>/dev/null || log_debug "Process $pid already gone."
        done
    fi
    log_info "Cleanup finished."
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT


# --- DB Content Generation (for /run/udev/data/c*:* file) ---
# --- DB Content Generation (for /run/udev/data/c*:* file) ---
# Arguments: $1=MAJOR, $2=MINOR, $3=PARENT_NAME
generate_keyboard_db_content() {
    local major="$1" minor="$2" parent_name="$3"
    cat <<EOF
I:$(date +%s%N | cut -b1-11)
E:ID_INPUT=1
E:ID_INPUT_KEY=1
E:ID_INPUT_KEYBOARD=1
E:ID_SERIAL=container-kbd-${minor}
G:seat
G:uaccess
Q:seat
Q:uaccess
V:1
EOF
}

generate_mouse_db_content() {
    local major="$1" minor="$2" parent_name="$3"
     cat <<EOF
I:$(date +%s%N | cut -b1-11)
E:ID_INPUT=1
E:ID_INPUT_MOUSE=1
E:ID_SERIAL=container-mouse-${minor}
G:seat
G:uaccess
Q:seat
Q:uaccess
V:1
EOF
}

generate_mouse_abs_db_content() {
    local major="$1" minor="$2" parent_name="$3"
     cat <<EOF
I:$(date +%s%N | cut -b1-11)
E:ID_INPUT=1
E:ID_INPUT_MOUSE=1
E:ID_INPUT_WIDTH_MM=685
E:ID_INPUT_HEIGHT_MM=428
E:ID_SERIAL=container-mouse-abs-${minor}
G:seat
G:uaccess
Q:seat
Q:uaccess
V:1
EOF
}

generate_touch_db_content() {
    local major="$1" minor="$2" parent_name="$3"
     cat <<EOF
I:$(date +%s%N | cut -b1-11)
E:ID_INPUT=1
E:ID_INPUT_TOUCHSCREEN=1
E:ID_SERIAL=container-touch-${minor}
G:seat
G:uaccess
Q:seat
Q:uaccess
V:1
EOF
}

generate_pen_db_content() {
    local major="$1" minor="$2" parent_name="$3"
     cat <<EOF
I:$(date +%s%N | cut -b1-11)
E:ID_INPUT=1
E:ID_INPUT_TABLET=1
E:ID_SERIAL=container-pen-${minor}
G:seat
G:uaccess
Q:seat
Q:uaccess
V:1
EOF
}

generate_gamepad_db_content() {
    local major="$1" minor="$2" parent_name="$3"
    cat <<EOF
I:$(date +%s%N | cut -b1-11)
E:ID_INPUT=1
E:ID_INPUT_JOYSTICK=1
E:ID_SERIAL=noserial
G:seat
G:seat0
G:uaccess
Q:seat
Q:uaccess
Q:seat0
V:1
EOF
}

generate_ds5_gamepad_db_content() {
    local major="$1" minor="$2" parent_name="$3" uniq="$4"
    cat <<EOF
I:$(date +%s%N | cut -b1-11)
E:ID_INPUT=1
E:ID_INPUT_JOYSTICK=1
E:ID_BUS=usb
E:ID_SERIAL=noserial
E:UNIQ=${uniq}
G:seat
G:uaccess
Q:seat
Q:uaccess
V:1
EOF
}

generate_ds5_gyro_db_content() {
    local major="$1" minor="$2" parent_name="$3" uniq="$4"
    cat <<EOF
I:$(date +%s%N | cut -b1-11)
E:ID_INPUT=1
E:ID_INPUT_ACCELEROMETER=1
E:ID_INPUT_WIDTH_MM=8
E:ID_INPUT_HEIGHT_MM=8
E:ID_BUS=usb
E:IIO_SENSOR_PROXY_TYPE=input-accel
E:UNIQ=${uniq}
G:seat
G:uaccess
Q:seat
Q:uaccess
V:1
EOF
}

generate_ds5_touchpad_db_content() {
    local major="$1" minor="$2" parent_name="$3" uniq="$4"
    cat <<EOF
I:$(date +%s%N | cut -b1-11)
E:ID_INPUT=1
E:ID_INPUT_TOUCHPAD=1
E:ID_BUS=usb
E:UNIQ=${uniq}
G:seat
G:uaccess
Q:seat
Q:uaccess
V:1
EOF
}

generate_hidraw_db_content() {
    local major="$1" minor="$2" parent_name="$3" uniq="$4"
    cat <<EOF
I:$(date +%s%N | cut -b1-11)
E:ID_BUS=usb
E:UNIQ=${uniq}
G:seat
G:uaccess
Q:seat
Q:uaccess
V:1
EOF
}

# --- Payload Generation (for /usr/bin/fake-udev) ---
# Arguments: $1=DEVNAME, $2=MAJOR, $3=MINOR, $4=DEVPATH, $5=PARENT_NAME
generate_keyboard_payload() {
    local devname="$1" major="$2" minor="$3" devpath="$4" parent_name="$5"
    cat <<EOF | properties_to_null_separated
ACTION=add
DEVPATH=${devpath}
SUBSYSTEM=input
DEVNAME=${devname}
SEQNUM=7
USEC_INITIALIZED=$(date +%s)
ID_INPUT=1
ID_INPUT_KEY=1
ID_INPUT_KEYBOARD=1
.INPUT_CLASS=kbd
NAME=${parent_name} (Container Event)
ID_SERIAL=container-kbd-${minor}
MAJOR=${major}
MINOR=${minor}
TAGS=:seat:uaccess:
CURRENT_TAGS=:seat:uaccess:

EOF
}

generate_mouse_payload() {
    local devname="$1" major="$2" minor="$3" devpath="$4" parent_name="$5"
    cat <<EOF | properties_to_null_separated
ACTION=add
DEVPATH=${devpath}
SUBSYSTEM=input
DEVNAME=${devname}
SEQNUM=7
USEC_INITIALIZED=$(date +%s)
ID_INPUT=1
ID_INPUT_MOUSE=1
.INPUT_CLASS=mouse
NAME=${parent_name} (Container Event)
ID_SERIAL=container-mouse-${minor}
MAJOR=${major}
MINOR=${minor}
TAGS=:seat:uaccess:
CURRENT_TAGS=:seat:uaccess:

EOF
}

generate_mouse_abs_payload() {
    local devname="$1" major="$2" minor="$3" devpath="$4" parent_name="$5"
    cat <<EOF | properties_to_null_separated
ACTION=add
DEVPATH=${devpath}
SUBSYSTEM=input
DEVNAME=${devname}
SEQNUM=7
USEC_INITIALIZED=$(date +%s)
ID_INPUT=1
ID_INPUT_MOUSE=1
ID_INPUT_WIDTH_MM=685
ID_INPUT_HEIGHT_MM=428
.INPUT_CLASS=mouse
NAME=${parent_name} (Container Event)
ID_SERIAL=container-mouse-${minor}
MAJOR=${major}
MINOR=${minor}
TAGS=:seat:uaccess:
CURRENT_TAGS=:seat:uaccess:

EOF
}

generate_touch_payload() {
    local devname="$1" major="$2" minor="$3" devpath="$4" parent_name="$5"
    cat <<EOF | properties_to_null_separated
ACTION=add
DEVPATH=${devpath}
SUBSYSTEM=input
DEVNAME=${devname}
SEQNUM=7
USEC_INITIALIZED=$(date +%s)
ID_INPUT=1
ID_INPUT_TOUCHSCREEN=1
.INPUT_CLASS=touchscreen
NAME=${parent_name} (Container Event)
ID_SERIAL=container-touch-${minor}
MAJOR=${major}
MINOR=${minor}
TAGS=:seat:uaccess:
CURRENT_TAGS=:seat:uaccess:

EOF
}

generate_pen_payload() {
    local devname="$1" major="$2" minor="$3" devpath="$4" parent_name="$5"
    cat <<EOF | properties_to_null_separated
ACTION=add
DEVPATH=${devpath}
SUBSYSTEM=input
DEVNAME=${devname}
SEQNUM=7
USEC_INITIALIZED=$(date +%s)
ID_INPUT=1
ID_INPUT_TABLET=1
.INPUT_CLASS=tablet
NAME=${parent_name} (Container Event)
ID_SERIAL=container-pen-${minor}
MAJOR=${major}
MINOR=${minor}
TAGS=:seat:uaccess:
CURRENT_TAGS=:seat:uaccess:

EOF
}

generate_gamepad_payload() {
    local devname="$1" major="$2" minor="$3" devpath="$4" parent_name="$5"
    local mac_addr=$(generate_random_mac) # Generate the random MAC
    log_debug "Generated UNIQ MAC for $devname: $mac_addr"
    cat <<EOF | properties_to_null_separated
ACTION=add
DEVPATH=${devpath}
SUBSYSTEM=input
DEVNAME=${devname}
SEQNUM=7
USEC_INITIALIZED=$(date +%s)
UNIQ=${mac_addr}
ID_INPUT=1
ID_INPUT_JOYSTICK=1
ID_SERIAL=noserial
.INPUT_CLASS=joystick
NAME=${parent_name} (Container Event)
MAJOR=${major}
MINOR=${minor}
TAGS=:seat:uaccess:
CURRENT_TAGS=:seat:uaccess:

EOF
}

generate_ds5_gamepad_payload() {
    local devname="$1" major="$2" minor="$3" devpath="$4" parent_name="$5" uniq="$6"
    cat <<EOF | properties_to_null_separated
ACTION=add
DEVPATH=${devpath}
SUBSYSTEM=input
DEVNAME=${devname}
SEQNUM=7
USEC_INITIALIZED=$(date +%s)
UNIQ=${uniq}
ID_INPUT=1
ID_INPUT_JOYSTICK=1
ID_SERIAL=noserial
.INPUT_CLASS=joystick
NAME=${parent_name} (Container Event)
MAJOR=${major}
MINOR=${minor}
TAGS=:seat:uaccess:
CURRENT_TAGS=:seat:uaccess:

EOF
}

generate_ds5_gyro_payload() {
    local devname="$1" major="$2" minor="$3" devpath="$4" parent_name="$5" uniq="$6"
    cat <<EOF | properties_to_null_separated
ACTION=add
DEVPATH=${devpath}
SUBSYSTEM=input
DEVNAME=${devname}
SEQNUM=7
USEC_INITIALIZED=$(date +%s)
ID_INPUT=1
ID_INPUT_ACCELEROMETER=1
ID_INPUT_WIDTH_MM=8
ID_INPUT_HEIGHT_MM=8
ID_BUS=usb
ID_SERIAL=noserial
UNIQ=${uniq}
IIO_SENSOR_PROXY_TYPE=input-accel
NAME=${parent_name} (Container Event)
MAJOR=${major}
MINOR=${minor}
TAGS=:seat:uaccess:
CURRENT_TAGS=:seat:uaccess:

EOF
}

generate_ds5_touchpad_payload() {
    local devname="$1" major="$2" minor="$3" devpath="$4" parent_name="$5" uniq="$6"
    cat <<EOF | properties_to_null_separated
ACTION=add
DEVPATH=${devpath}
SUBSYSTEM=input
DEVNAME=${devname}
SEQNUM=7
USEC_INITIALIZED=$(date +%s)
ID_INPUT=1
ID_INPUT_TOUCHPAD=1
ID_INPUT_TOUCHPAD_INTEGRATION=internal
ID_BUS=usb
ID_SERIAL=noserial
.INPUT_CLASS=mouse
UNIQ=${uniq}
IIO_SENSOR_PROXY_TYPE=input-accel
NAME=${parent_name} (Container Event)
MAJOR=${major}
MINOR=${minor}
TAGS=:seat:uaccess:
CURRENT_TAGS=:seat:uaccess:

EOF
}
generate_hidraw_payload() {
    local devname="$1" major="$2" minor="$3" devpath="$4" parent_name="$5" uniq="$6"
    cat <<EOF | properties_to_null_separated
ACTION=add
DEVPATH=${devpath}
SUBSYSTEM=hidraw
DEVNAME=${devname}
SEQNUM=7
USEC_INITIALIZED=$(date +%s)
UNIQ=${uniq}
ID_BUS=usb
NAME=${parent_name} (Container HIDRAW)
MAJOR=${major}
MINOR=${minor}
TAGS=:seat:uaccess:
CURRENT_TAGS=:seat:uaccess:
EOF
}

# --- Main Processing ---
 

log_info "Ensuring /run/udev setup..."
mkdir -p /run/udev/data /dev/input
touch /run/udev/control
chmod 755 /run/udev /run/udev/data /dev/input
chmod 644 /run/udev/control

log_info "Monitoring udev events for input subsystem..."
declare -A event_props # Associative array to hold properties for one event

stdbuf -oL udevadm monitor --kernel --property | while IFS= read -r line; do
    # Remove potential leading/trailing whitespace
    line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Detect start of a new event block or empty line indicating end of block
    if [[ -z "$line" || "$line" =~ ^KERNEL ]]; then
        # Process the previously collected properties if any exist
        if [[ ${#event_props[@]} -gt 0 ]]; then
            log_debug "--- Processing Event Block ---"
            for k in "${!event_props[@]}"; do log_debug "  $k = ${event_props[$k]}"; done

            # --- Stage 1: Check if this is a Parent device we care about ---
            if [[ -v event_props["NAME"] && -v event_props["DEVPATH"] ]]; then
                current_name="${event_props["NAME"]}"
                current_devpath="${event_props["DEVPATH"]}"
                if contains_element "$current_name" "${TARGET_PARENT_DEVICE_NAMES[@]}"; then
                    log_debug "Remembering Parent: DEVPATH='$current_devpath' NAME='$current_name'"
                    parent_device_names["$current_devpath"]="$current_name"
                    if [[ -v event_props["UNIQ"] ]]; then
                        log_debug "Remembering UNIQ: ${event_props["UNIQ"]}"
                        parent_device_uniqs["$current_devpath"]="${event_props["UNIQ"]}"
                    fi
                fi
            # Also catch hid devices by HID_NAME
            elif [[ "${event_props["SUBSYSTEM"]}" == "hid" && -v event_props["HID_NAME"] && -v event_props["DEVPATH"] ]]; then
                current_name="${event_props["HID_NAME"]}"
                current_devpath="${event_props["DEVPATH"]}"
                if contains_element "$current_name" "${TARGET_PARENT_DEVICE_NAMES[@]}"; then
                    log_debug "Remembering Parent (from HID): DEVPATH='$current_devpath' NAME='$current_name'"
                    parent_device_names["$current_devpath"]="$current_name"
                    if [[ -v event_props["HID_UNIQ"] ]]; then
                        log_debug "Remembering UNIQ (from HID): ${event_props["HID_UNIQ"]}"
                        parent_device_uniqs["$current_devpath"]="${event_props["HID_UNIQ"]}"
                    fi
                fi
            fi

            # --- Stage 2: Check if this is a child /dev/input/event* OR /dev/input/js* node ---
            if [[ -v event_props["ACTION"] && \
                  -v event_props["DEVNAME"] && \
                  ( "${event_props["DEVNAME"]}" == /dev/input/event* || "${event_props["DEVNAME"]}" == /dev/input/js* || "${event_props["DEVNAME"]}" == /dev/hidraw* ) && \
                  -v event_props["MAJOR"] && \
                  -v event_props["MINOR"] && \
                  -v event_props["SUBSYSTEM"] && \
                  "${event_props["SUBSYSTEM"]}" == "input" && \
                  -v event_props["DEVPATH"] ]]; then

                action="${event_props["ACTION"]}"
                devname="${event_props["DEVNAME"]}"
                major="${event_props["MAJOR"]}"
                minor="${event_props["MINOR"]}"
                devpath="${event_props["DEVPATH"]}"
                seqnum_orig="${event_props["SEQNUM"]:-7}" # Default SEQNUM if missing, use 7 for consistency
                device_type=""
                parent_path_found=""
                temp_path="$devpath"
                # Walk up the devpath to find a known parent
                while [[ "$temp_path" != "/" && "$temp_path" != "." && -z "$parent_path_found" ]]; do
                    parent_path=$(dirname "$temp_path")
                    if [[ -v parent_device_names["$parent_path"] ]]; then
                        device_type="${parent_device_names["$parent_path"]}"
                        parent_path_found="$parent_path"
                        log_debug "Device node $devname corresponds to parent '$device_type' ($parent_path_found)"
                    fi
                    temp_path="$parent_path"
                done

                # Fallback to checking the event's own name if no parent was found
                if [[ -z "$device_type" ]]; then
                    event_name=""
                    if [[ -v event_props["NAME"] ]]; then event_name="${event_props["NAME"]}"; fi

                    if contains_element "$event_name" "${TARGET_PARENT_DEVICE_NAMES[@]}"; then
                         log_debug "Device node $devname has a directly targeted NAME '$event_name'. Using it."
                         device_type="$event_name"
                    else
                         log_debug "Device node $devname does not correspond to a known parent and its own name '$event_name' is not targeted. Skipping."
                         event_props=()
                         continue
                    fi
                fi

                # Get UNIQ from parent if available, otherwise from event, otherwise generate one
                if [[ -n "$parent_path_found" && -v parent_device_uniqs["$parent_path_found"] ]]; then
                    uniq="${parent_device_uniqs["$parent_path_found"]}"
                    log_debug "Using UNIQ '$uniq' from parent $parent_path_found"
                else
                    uniq="${event_props["UNIQ"]:-$(generate_random_mac)}"
                    log_debug "Using UNIQ '$uniq' from event or generated"
                fi

                # We have a child event/js node linked to a known parent type
                internal_dev_node="$devname"
                internal_db_file="/run/udev/data/c${major}:${minor}"

                if [[ "$action" == "add" ]]; then
                    log_debug "Action: ADD $devname (Type: '$device_type', Major: $major, Minor: $minor)"

                    # 1. Generate DB content and Payload based on matched *parent* device type
                    db_content=""
                    fake_udev_payload=""

                    if [[ "$devname" == /dev/hidraw* ]]; then
                        log_debug "Device is hidraw, using hidraw generators for type '$device_type'"
                        db_content=$(generate_hidraw_db_content "$major" "$minor" "$device_type" "$uniq")
                        fake_udev_payload=$(generate_hidraw_payload "$devname" "$major" "$minor" "$devpath" "$device_type" "$uniq")
                    else
                        # Determine generator based on parent type for event* or js*
                        log_debug "Device is event/js, using standard generators for type '$device_type'"
                        case "$device_type" in
                            "Keyboard passthrough"|"Makima Virtual Keyboard/Mouse")
                                db_content=$(generate_keyboard_db_content "$major" "$minor" "$device_type")
                                fake_udev_payload=$(generate_keyboard_payload "$devname" "$major" "$minor" "$devpath" "$device_type")
                                ;;
                            "Mouse passthrough")
                                db_content=$(generate_mouse_db_content "$major" "$minor" "$device_type")
                                fake_udev_payload=$(generate_mouse_payload "$devname" "$major" "$minor" "$devpath" "$device_type")
                                ;;
                             "Wolf mouse (abs) virtual device")
                                db_content=$(generate_mouse_abs_db_content "$major" "$minor" "$device_type")
                                fake_udev_payload=$(generate_mouse_abs_payload "$devname" "$major" "$minor" "$devpath" "$device_type")
                                ;;
                            "Touch passthrough")
                                db_content=$(generate_touch_db_content "$major" "$minor" "$device_type")
                                fake_udev_payload=$(generate_touch_payload "$devname" "$major" "$minor" "$devpath" "$device_type")
                                ;;
                            "Pen passthrough")
                                db_content=$(generate_pen_db_content "$major" "$minor" "$device_type")
                                fake_udev_payload=$(generate_pen_payload "$devname" "$major" "$minor" "$devpath" "$device_type")
                                ;;
                            "Sunshine Nintendo (virtual) pad"|"Sunshine X-Box One (virtual) pad")
                                db_content=$(generate_gamepad_db_content "$major" "$minor" "$device_type")
                                fake_udev_payload=$(generate_gamepad_payload "$devname" "$major" "$minor" "$devpath" "$device_type")
                                ;;
                            "Sunshine DualSense (virtual) pad"|"Sunshine PS5 (virtual) pad")
                                db_content=$(generate_ds5_gamepad_db_content "$major" "$minor" "$device_type" "$uniq")
                                fake_udev_payload=$(generate_ds5_gamepad_payload "$devname" "$major" "$minor" "$devpath" "$device_type" "$uniq")
                                ;;
                            "Sunshine DualSense (virtual) pad Motion Sensors"|"Sunshine PS5 (virtual) pad Motion Sensors")
                                db_content=$(generate_ds5_gyro_db_content "$major" "$minor" "$device_type" "$uniq")
                                fake_udev_payload=$(generate_ds5_gyro_payload "$devname" "$major" "$minor" "$devpath" "$device_type" "$uniq")
                                ;;
                            "Sunshine DualSense (virtual) pad Touchpad"|"Sunshine PS5 (virtual) pad Touchpad")
                                db_content=$(generate_ds5_touchpad_db_content "$major" "$minor" "$device_type" "$uniq")
                                fake_udev_payload=$(generate_ds5_touchpad_payload "$devname" "$major" "$minor" "$devpath" "$device_type" "$uniq")
                                ;;
                            *)
                                log_error "No generator function defined for device type: '$device_type'"
                                event_props=()
                                continue
                                ;;
                        esac
                    fi

                    if [[ -z "$db_content" || -z "$fake_udev_payload" ]]; then
                       log_error "Failed to generate DB content or Payload for '$device_type' node '$devname'"
                       event_props=()
                       continue
                    fi

                    log_debug "Generated DB Content:\n$db_content"
                    if ! echo "$fake_udev_payload" > /dev/null; then
                       log_error "Payload generation resulted in empty string for '$device_type' node '$devname'"
                       event_props=()
                       continue
                    fi
                    log_debug "Generated Payload (raw, nulls as N): $(echo "$fake_udev_payload" | tr '\0' 'N')"
                    fake_udev_payload_b64=$(echo -ne "$fake_udev_payload" | base64 -w0) # Use -w0 for no line wrap
                    log_debug "Generated Payload (b64): $fake_udev_payload_b64"

                    # 2. Create device node
                    if ! mknod "$internal_dev_node" c "$major" "$minor"; then
                       log_error "mknod failed for $internal_dev_node. Already exists?"
                       # Decide if this is fatal, maybe continue if it exists? For now, continue loop
                       continue
                    fi
                    log_debug "Created node $internal_dev_node"

                    # 3. Set permissions (adjust group if needed, e.g., 'input')
                    if ! chown root:input "$internal_dev_node"; then continue; fi
                    if ! chmod 660 "$internal_dev_node"; then continue; fi
                    log_debug "Set permissions on $internal_dev_node"

                    # 4. Create internal udev db file
                    db_content_escaped=$(echo "$db_content" | sed 's/"/\\"/g') # Basic escaping for shell
                    if ! echo "$db_content_escaped" > "$internal_db_file"; then continue; fi
                    log_debug "Created DB file $internal_db_file"

                    # 5. Send fake-udev event
                    # fake-udev needs to be executable, likely as root if script isn't already root
                    if ! echo "$fake_udev_payload_b64" | /usr/bin/fake-udev -m >/dev/null; then
                       log_error "fake-udev command failed for $devname"
                       continue
                    fi
                    log_debug "Sent fake-udev event for $devname"

                    # --- Start lisgd for Touch passthrough ---
                    if [[ "$device_type" == "Touch passthrough" ]]; then
                        log_info "Starting lisgd for $devname..."
                        sleep 0.05
                        # Start lisgd as appuser in the background, targeting the specific device
                        su appuser -c "lisgd -g '3,UD,*,*,R,kitty &' -g '3,DU,*,*,R,rofi-makima &' -d ${devname}" &
                        lisgd_pid=$!
                        if kill -0 "$lisgd_pid" 2>/dev/null; then
                            lisgd_pids["$devname"]=$lisgd_pid
                            log_info "Started lisgd (PID: $lisgd_pid) for $devname"
                        else
                            log_error "Failed to start lisgd for $devname"
                        fi
                    fi
                    # --- End lisgd start ---

                    log_info "Successfully processed ADD for $devname (Type: '$device_type')"

                elif [[ "$action" == "remove" ]]; then
                    log_debug "Action: REMOVE $devname (Type: '$device_type', Major: $major, Minor: $minor)"

                    # --- Kill lisgd for Touch passthrough ---
                    if [[ "$device_type" == "Touch passthrough" && -v lisgd_pids["$devname"] ]]; then
                        pid_to_kill="${lisgd_pids[$devname]}"
                        log_info "Stopping lisgd (PID: $pid_to_kill) for $devname..."
                        if kill "$pid_to_kill" 2>/dev/null; then
                            log_info "Successfully killed lisgd (PID: $pid_to_kill)"
                        else
                            log_debug "lisgd process (PID: $pid_to_kill) already stopped or failed to kill."
                        fi
                        unset lisgd_pids["$devname"] # Remove from tracking
                    elif [[ "$device_type" == "Touch passthrough" ]]; then
                         log_debug "No lisgd PID found to kill for $devname"
                    fi
                    # --- End lisgd kill ---

                    # 1. Generate fake-udev remove payload
                    remove_payload=$(echo "ACTION=remove\0DEVNAME=$devname\0NAME=$device_type\0MAJOR=$major\0MINOR=$minor\0SUBSYSTEM=${event_props["SUBSYSTEM"]}\0DEVPATH=$devpath\0SEQNUM=${seqnum_orig}\0")

                    if ! echo "$remove_payload" >/dev/null; then
                       log_error "Remove payload generation resulted in empty string for '$device_type' node '$devname'"
                       event_props=()
                       continue
                    fi
                    log_debug "Remove Payload (raw, nulls as N): $(echo "$remove_payload" | tr '\0' 'N')"
                    remove_payload_b64=$(echo -ne "$remove_payload" | base64 -w0)
                    log_debug "Remove Payload (b64): $remove_payload_b64"

                    # 2. Remove device node
                    rm -f "$internal_dev_node"

                    # 3. Remove internal udev db file
                    rm -f "$internal_db_file"

                    # 4. Send fake-udev remove event
                    if ! echo "$remove_payload_b64" | /usr/bin/fake-udev -m >/dev/null; then continue; fi

                    # 5. Clean up parent mapping (optional)
                    # unset parent_device_names["$parent_path"]

                    log_info "Successfully processed REMOVE for $devname (Type: '$device_type')"
                else
                    log_debug "Ignoring action '$action' for $devname"
                fi
            fi # End check for event* or js* node

            log_debug "--- End Event Block Processing ---"
        fi # End check if event_props has data

        # Clear properties for the next event block
        event_props=()

        # If the line marks the start of a new event, log it
        if [[ "$line" =~ ^KERNEL ]]; then
            log_debug "Event Block Start: $line"
        fi

    # If it's a property line, add it to the current event data
    elif [[ "$line" =~ = ]]; then
        key="${line%%=*}"
        value="${line#*=}"
        value="${value%\"}"
        value="${value#\"}"
        event_props["$key"]="$value"
    fi
done