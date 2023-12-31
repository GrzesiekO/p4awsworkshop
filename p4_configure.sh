#!/bin/bash


#Currently this needs proper EBS volume locations from /dev with proper nvme names $1 is a hxlogs $2 hxdepots $3 hxmetadata

# Log file location
LOG_FILE="/var/log/p4_configure.log"

# Ensure the script runs only once
FLAG_FILE="/var/run/p4_configure_ran.flag"

if [ -f "$FLAG_FILE" ]; then
    echo "Script has already run. Exiting."
    exit 0
fi

# Function to log messages
log_message() {
    echo "$(date) - $1" >> $LOG_FILE
}

# Function to check if path is an FSx mount point
is_fsx_mount() {
    echo "$1" | grep -qE 'fs-[0-9a-f]{17}\.fsx\.[a-z0-9-]+\.amazonaws\.com:/' #to be verified if catches all fsxes
    return $?
}

# Function to create and mount XFS on EBS
prepare_ebs_volume() {
    local ebs_volume=$1
    local mount_point=$2

    # Check if the EBS volume has a file system
    local fs_type=$(lsblk -no FSTYPE "$ebs_volume")

    if [ -z "$fs_type" ]; then
        log_message "Creating XFS file system on $ebs_volume."
        mkfs.xfs "$ebs_volume"
    fi

    log_message "Mounting $ebs_volume on $mount_point."
    mount "$ebs_volume" "$mount_point"
}

# Starting the script
log_message "Starting the p4 configure script."

# Check if the script received three arguments
if [ "$#" -ne 3 ]; then
    log_message "Incorrect usage. Expected 3 arguments, got $#."
    log_message "Usage: $0 <EBS path or FSx for hxlogs> <EBS path or FSx for hxmetadata> <EBS path or FSx for hxdepots>"
    exit 1
fi

# Assigning arguments to variables
EBS_LOGS=$1
EBS_METADATA=$2
EBS_DEPOTS=$3

echo $EBS_LOGS
echo $EBS_METADATA
echo $EBS_DEPOTS

# Function to perform operations
perform_operations() {
    log_message "Performing operations for mounting and syncing directories."

    # Check each mount type and mount accordingly
    mount_fs_or_ebs() {
        local mount_point=$1
        local dest_dir=$2
        if is_fsx_mount "$mount_point"; then
            # Mount as FSx
            mount -t nfs -o nconnect=16,rsize=1048576,wsize=1048576,timeo=600 "$mount_point" "$dest_dir"
        else
            # Mount as EBS the called function also creates XFS on EBS
            
            prepare_ebs_volume "$mount_point" "$dest_dir"
        fi
    }

    # Create temporary directories and mount
    mkdir -p /mnt/temp_hxlogs
    mkdir -p /mnt/temp_hxmetadata
    mkdir -p /mnt/temp_hxdepots

    mount_fs_or_ebs $EBS_LOGS /mnt/temp_hxlogs
    mount_fs_or_ebs $EBS_METADATA /mnt/temp_hxmetadata
    mount_fs_or_ebs $EBS_DEPOTS /mnt/temp_hxdepots

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

    # Mount EBS volumes or FSx to final destinations
    mount_fs_or_ebs $EBS_LOGS /hxlogs
    mount_fs_or_ebs $EBS_METADATA /hxmetadata
    mount_fs_or_ebs $EBS_DEPOTS /hxdepots

    log_message "Operation completed successfully."
}

# Check if EBS volumes or FSx mount points are provided for all required paths
if ( [ -e "$EBS_LOGS" ] || is_fsx_mount "$EBS_LOGS" ) && \
   ( [ -e "$EBS_METADATA" ] || is_fsx_mount "$EBS_METADATA" ) && \
   ( [ -e "$EBS_DEPOTS" ] || is_fsx_mount "$EBS_DEPOTS" ); then
    perform_operations
else
    log_message "One or more required paths are not valid EBS volumes or FSx mount points. No operations performed."
fi



SDP_Setup_Script=/hxdepots/sdp/Server/Unix/setup/mkdirs.sh # This to be moved to the other script
SDP_New_Server_Script=/p4/sdp/Server/setup/configure_new_server.sh # To be moved to second one this is part of configuration of a new master.
SDP_Live_Checkpoint=/p4/sdp/Server/Unix/p4/common/bin/live_checkpoint.sh # To be moved
SDP_Offline_Recreate=/p4/sdp/Server/Unix/p4/common/bin/recreate_offline_db.sh # To be moved
SDP_Client_Binary=/hxdepots/sdp/helix_binaries/p4 

# Execute mkdirs.sh from the extracted package
if [ -f "$SDP_Setup_Script" ]; then
  chmod +x "$SDP_Setup_Script"
  "$SDP_Setup_Script" 1
else
  log_message "Setup script (mkdirs.sh) not found."
fi

# update cert config with ec2 DNS name
FILE_PATH="/p4/ssl/config.txt"

# Retrieve the EC2 instance DNS name
EC2_DNS_NAME=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname --header "X-aws-ec2-metadata-token: $TOKEN")


# Check if the DNS name was successfully retrieved
if [ -z "$EC2_DNS_NAME" ]; then
  echo "Failed to retrieve EC2 instance DNS name."
  exit 1
fi

# Replace REPL_DNSNAME with the EC2 instance DNS name for ssl certificate generation
sed -i "s/REPL_DNSNAME/$EC2_DNS_NAME/" "$FILE_PATH"

echo "File updated successfully."

I=1
# generate certificate 

/p4/common/bin/p4master_run ${I} /p4/${I}/bin/p4d_${I} -Gc

# Configure systemd service to start p4d


cd /etc/systemd/system
sed -e "s:__INSTANCE__:$I:g" -e "s:__OSUSER__:perforce:g" $SDP/Server/Unix/p4/common/etc/systemd/system/p4d_N.service.t > p4d_${I}.service
chmod 644 p4d_${I}.service
systemctl daemon-reload


# update label for selinux
semanage fcontext -a -t bin_t /p4/1/bin/p4d_1_init
restorecon -vF /p4/1/bin/p4d_1_init

# start service
systemctl start p4d_1

# Wait for the p4d service to start before continuing
wait_for_service "p4d_1"

P4PORT=ssl:1666
P4USER=perforce

#probably need to copy p4 binary to the /usr/bin or add to the path variable to avoid running with a full path adding:
#permissions for lal users:


chmod +x /hxdepots/sdp/helix_binaries/p4
ln -s $SDP_Client_Binary /usr/bin/p4

# now can test:
p4 -p ssl:$HOSTNAME:1666 trust -y


# Execute new server setup from the extracted package
if [ -f "$SDP_New_Server_Script" ]; then
  chmod +x "$SDP_New_Server_Script"
  "$SDP_New_Server_Script" 1
else
  echo "Setup script (configure_new_server.sh) not found."
fi



# create a live checkpoint and restore offline db
# switching to user perforce


if [ -f "$SDP_Live_Checkpoint" ]; then
  chmod +x "$SDP_Live_Checkpoint"
  sudo -u perforce "$SDP_Live_Checkpoint" 1
else
  echo "Setup script (SDP_Live_Checkpoint) not found."
fi

if [ -f "$SDP_Offline_Recreate" ]; then
  chmod +x "$SDP_Offline_Recreate"
  sudo -u perforce "$SDP_Offline_Recreate" 1
else
  echo "Setup script (SDP_Offline_Recreate) not found."
fi

# initialize crontab for user perforce

sudo -u perforce crontab /p4/p4.crontab.1

# verify sdp installation should warn about missing license only:
/hxdepots/p4/common/bin/verify_sdp.sh 1





# Create the flag file to prevent re-run
touch "$FLAG_FILE"




# Ending the script
log_message "EC2 mount script finished."

