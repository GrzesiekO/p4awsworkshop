#!/bin/bash

# Log file location
LOG_FILE="/var/log/p4_configure.log"

# Function to log messages
log_message() {
    echo "$(date) - $1" >> $LOG_FILE
}

# Starting the script
log_message "Starting the p4 configure script."

# Check if the script received three arguments
if [ "$#" -ne 3 ]; then
    log_message "Incorrect usage. Expected 3 arguments, got $#."
    log_message "Usage: $0 <EBS path for hxlogs> <EBS path for hxmetadata> <EBS path for hxdepots>"
    exit 1
fi

# Assigning arguments to variables
EBS_LOGS=$1
EBS_METADATA=$2
EBS_DEPOTS=$3

# Function to perform operations
perform_operations() {
    log_message "Performing operations for mounting and syncing directories."

    # Create temporary directories
    mkdir -p /mnt/temp_hxlogs
    mkdir -p /mnt/temp_hxmetadata
    mkdir -p /mnt/temp_hxdepots

    # Mount EBS volumes to temporary directories
    mount $EBS_LOGS /mnt/temp_hxlogs
    mount $EBS_METADATA /mnt/temp_hxmetadata
    mount $EBS_DEPOTS /mnt/temp_hxdepots

    # Syncing directories
    rsync -av /hxlogs/ /mnt/temp_hxlogs/
    rsync -av /hxmetadata/ /mnt/temp_hxmetadata/
    rsync -av /hxdepots/ /mnt/temp_hxdepots/

    # Unmount temporary mounts
    umount /mnt/temp_hxlogs
    umount /mnt/temp_hxmetadata
    umount /mnt/temp_hxdepots

    # Clear destination directories
    rm -rf /hxlogs/*
    rm -rf /hxmetadata/*
    rm -rf /hxdepots/*

    # Mount EBS volumes to final destinations
    mount $EBS_LOGS /hxlogs
    mount $EBS_METADATA /hxmetadata
    mount $EBS_DEPOTS /hxdepots

    log_message "Operation completed successfully."
}

# Check if EBS volumes exist
if [ -e "$EBS_LOGS" ] && [ -e "$EBS_METADATA" ] && [ -e "$EBS_DEPOTS" ]; then
    perform_operations
else
    log_message "One or more EBS volumes do not exist. No operations performed."
fi

# Ending the script
log_message "EC2 mount script finished."
