#!/bin/bash

# Log file location
LOG_FILE="/var/log/p4_setup.log"

# Function to log messages
log_message() {
    echo "$(date) - $1" >> $LOG_FILE
}

# Known things to be fixed:  
# 1. Add function to validate dirs and files isnsted of calling it multiple times.
# 2. Fix variable names
# 3. Validate values passed to functions
# 4. Error handling (distro check) - this works for rhel based with dnf
# 5. Move hardcoded paths/names to a config file
# 6. Add a log
# 7. Split the script into two: one for p4 copy of necessary files and second to run mkdirs cfg to setup replica. make te second setup also a one timer that mounts basic dirs /hxlogs /hxmetadata /hxdepots


# Constants
ROOT_UID=0

# Check if script is run as root
if [ "$UID" -ne "$ROOT_UID" ]; then
  echo "Must be root to run this script."
  log_message "Function not run as a root."
  exit 1
fi

# Set local variables
SDP_Root=/hxdepots/sdp/helix_binaries
SDP=/hxdepots/sdp
PACKAGE="policycoreutils-python-utils" # Required in both

TOKEN=$(curl --request PUT "http://169.254.169.254/latest/api/token" --header "X-aws-ec2-metadata-token-ttl-seconds: 3600") # This is only for the metadata V2 need to check go and try the V1 with no token and see which one works. 
EC2_DNS_PRIVATE=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname --header "X-aws-ec2-metadata-token: $TOKEN") # same need to check for V2 vs V1
SDP_Setup_Script_Config=/hxdepots/sdp/Server/Unix/setup/mkdirs.cfg # Config to the new script needed for mkdirs.sh
# Check if SELinux is enabled, we need to relabel the service post installation otherwise it will not start p4d

SELINUX_STATUS=$(getenforce)




if [ "$SELINUX_STATUS" = "Enforcing" ] || [ "$SELINUX_STATUS" = "Permissive" ]; then
    log_message "SELinux is enabled."
    if ! dnf list installed "$PACKAGE" &> /dev/null; then
        log_message "Package $PACKAGE is not installed. Installing..."
        sudo dnf install -y "$PACKAGE"
        if [ $? -eq 0 ]; then
            log_message "$PACKAGE installed successfully."
        else
            log_message "Failed to install $PACKAGE."
        fi
    else
        log_message "Package $PACKAGE is already installed."
    fi
else
    log_message "SELinux is not enabled. Skipping package installation."
fi

# Function to check if a group exists
group_exists() {
  getent group $1 > /dev/null 2>&1
}

# Function to check if a user exists
user_exists() {
  id -u $1 > /dev/null 2>&1
}

# Function to check if a directory exists
directory_exists() {
  [ -d "$1" ]
}

# Function to wait for a service to start
wait_for_service() {
  local service_name=$1
  local max_attempts=10
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    log_message "Waiting for $service_name to start... Attempt $attempt of $max_attempts."
    systemctl is-active --quiet $service_name && break
    sleep 1
    ((attempt++))
  done

  if [ $attempt -gt $max_attempts ]; then
    log_message "Service $service_name did not start within the expected time."
    return 1
  fi

  log_message "Service $service_name started successfully."
  return 0
}

log_message "Installing Perforce"
# dnf update -y skipping this for now as it prolongs the AMI build and can be called post launch. 

# Check if group 'perforce' exists, if not, add it
if ! group_exists perforce; then
  groupadd perforce
fi

# Check if user 'perforce' exists, if not, add it
if ! user_exists perforce; then
  useradd -d /home/perforce -s /bin/bash -m perforce -g perforce
fi

# Set up sudoers for perforce user
if [ ! -f /etc/sudoers.d/perforce ]; then
  touch /etc/sudoers.d/perforce
  chmod 0600 /etc/sudoers.d/perforce
  echo "perforce ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/perforce
  chmod 0400 /etc/sudoers.d/perforce
fi

# Create directories if they don't exist
for dir in /hxdepots /hxlogs /hxmetadata; do
  if ! directory_exists $dir; then
    mkdir $dir
  fi
done

# Change ownership
chown -R perforce:perforce /hx*

# Download and extract SDP
cd /hxdepots
if [ ! -f sdp.Unix.tgz ]; then
  curl -L -O https://swarm.workshop.perforce.com/projects/perforce-software-sdp/download/downloads/sdp.Unix.tgz
  tar -xzf sdp.Unix.tgz
fi

chmod -R +w $SDP
cd $SDP_Root
# checking if required binaries are in the folder.
required_binaries=(p4 p4broker p4d p4p)
missing_binaries=0

# Check each binary
for binary in "${required_binaries[@]}"; do
    if [ ! -f "/hxdepots/sdp/helix_binaries/$binary" ]; then
        echo "Missing binary: $binary"
        missing_binaries=1
        break
    fi
done

# Download binaries if any are missing
if [ $missing_binaries -eq 1 ]; then
    echo "One or more Helix binaries are missing. Running get_helix_binaries.sh..."
    /hxdepots/sdp/helix_binaries/get_helix_binaries.sh
else
    echo "All Helix binaries are present."
fi
###### previously each run got the binaries by: /hxdepots/sdp/helix_binaries/get_helix_binaries.sh

chown -R perforce:perforce $SDP_Root

cd /hxdepots/sdp/Server/Unix/setup


#update the mkdirs.cfg so it has proper hostname a private DNS form EC2 otherwise adding replica is not possible due to wrong P4TARGET settings.

if [ ! -f "$SDP_Setup_Script_Config" ]; then
    log_message "Error: Configuration file not found at $SDP_Setup_Script_Config."
    exit 1
fi


# Update P4MASTERHOST value in the configuration file
sed -i "s/^P4MASTERHOST=.*/P4MASTERHOST=$EC2_DNS_PRIVATE/" "$SDP_Setup_Script_Config"

log_message "Updated P4MASTERHOST to $EC2_DNS_PRIVATE in $SDP_Setup_Script_Config."

