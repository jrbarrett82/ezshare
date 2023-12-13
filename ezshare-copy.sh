#!/bin/bash

# Script configuration
EZSHARE_WIFI="ezShare"
HOME_WIFI="jrb-access"
ezshare_local="/mnt/resmed"
TODAYS_DATE=$(date +%Y%m%d)
ZIP_FILE="${ezshare_local}/sleephq-${TODAYS_DATE}.zip"
LOG_FILE="/var/log/ezshare_sync.log"
TELEGRAM_BOT_TOKEN="6410099964:AAE2iXJ-1O6JlHEwupHiiHyfC8M2TWxfCi0"
TELEGRAM_CHAT_ID="591095911"
DROPBOX_DIR="dropbox:resmed"

# Function to check and install missing prerequisites
install_prerequisites() {
    local packages=("network-manager" "zip" "python3" "python3-pip" "curl")
    for pkg in "${packages[@]}"; do
        if ! dpkg -s "$pkg" &> /dev/null; then
            echo "Installing missing package: $pkg"
            sudo apt-get install -y "$pkg"
        fi
    done

    if ! pip3 list | grep -q "ezshare"; then
        echo "Installing ezshare-cli"
        pip3 install ezshare
    fi

    if ! command -v rclone &> /dev/null; then
        echo "Installing rclone"
        sudo apt-get install -y rclone
    fi
}

# Function to log messages
log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# Function to send a message to Telegram
send_telegram_message() {
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id="${TELEGRAM_CHAT_ID}" -d text="$1"
}

# Function to add files to zip if they were modified today
zip_today_modified() {
    local path=$1
    find "$path" -type f -newermt "$TODAYS_DATE 00:00" ! -newermt "$TODAYS_DATE 23:59" -exec zip -q "$ZIP_FILE" '{}' +
}

# Run the prerequisite check
install_prerequisites

# Connect to EZShare WiFi
if nmcli con up "$EZSHARE_WIFI"; then
    log_message "Connected to EZShare WiFi."
else
    log_message "Failed to connect to EZShare WiFi."
fi

# Sync data from EZShare SD card
if sudo ezshare-cli -w -r -d / -t "$ezshare_local"; then
    log_message "Data synced from EZShare SD card."
else
    log_message "Failed to sync data from EZShare SD card."
fi

# Disconnect from EZShare WiFi and connect to Home WiFi
nmcli con down "$EZSHARE_WIFI"
if nmcli con up "$HOME_WIFI"; then
    log_message "Switched to Home WiFi."
else
    log_message "Failed to switch to Home WiFi."
fi

# Function to add specific files and folders to the zip
add_to_zip() {
    local path=$1
    if [ -e "$path" ]; then  # Check if the path exists
        zip -q "$ZIP_FILE" "$path"
    fi
}

# Function to add the latest three date-named subfolders from DATALOG, including their contents
add_latest_datalog_folders() {
    local datalog_dir="${ezshare_local}/DATALOG"
    if [ -d "$datalog_dir" ]; then
        # Get the latest three subdirectories based on naming convention (YYYYMMDD)
        local latest_folders=$(ls -1 "$datalog_dir" | sort -r | head -n 3)
        for folder in $latest_folders; do
            # Add the folder and its contents to the zip
            zip -rq "$ZIP_FILE" "${datalog_dir}/${folder}"
        done
    fi
}

# Add the latest version of each specified file and folder to the zip
add_to_zip "${ezshare_local}/STR.edf"
add_to_zip "${ezshare_local}/Identification.crc"
add_to_zip "${ezshare_local}/Identification.tgt"
add_to_zip "${ezshare_local}/SETTINGS"

# Add the latest three date-named subfolders from DATALOG
add_latest_datalog_folders

if [ -f "$ZIP_FILE" ] && [ -s "$ZIP_FILE" ]; then
    log_message "Zip file created successfully."
else
    log_message "No files to zip."
fi

# Upload to Dropbox using rclone
if rclone copy "$ZIP_FILE" "$DROPBOX_DIR"; then
    log_message "Uploaded zip file to Dropbox."
else
    log_message "Failed to upload zip file to Dropbox."
fi

# Send completion message to Telegram
send_telegram_message "Data sync and upload complete."
log_message "Sent Telegram notification."

# Script completion
echo "Script execution complete. Check log for details."
