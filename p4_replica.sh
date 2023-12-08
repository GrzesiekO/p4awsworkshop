#!/bin/bash


# Known things to be fixed:  
# 1. Add function to validate dirs and files isnsted of calling it multiple times.
# 2. Fix variable names
# 3. Validate values passed to functions
# 4. Error handling (distro check) - this works for rhel based with dnf
# 5. Move hardcoded paths/names to a config file
# 6. Add a log

# Constants
ROOT_UID=0

# Check if script is run as root
if [ "$UID" -ne "$ROOT_UID" ]; then
  echo "Must be root to run this script."
  exit 1
fi

# Set local variables
SDP_Root=/hxdepots/sdp/helix_binaries
SDP=/hxdepots/sdp
SDP_Setup_Script=/hxdepots/sdp/Server/Unix/setup/mkdirs.sh
SDP_New_Server_Script=/p4/sdp/Server/setup/configure_new_server.sh
SDP_Live_Checkpoint=/p4/sdp/Server/Unix/p4/common/bin/live_checkpoint.sh
SDP_Offline_Recreate=/p4/sdp/Server/Unix/p4/common/bin/recreate_offline_db.sh
PACKAGE="policycoreutils-python-utils"
SDP_Client_Binary=/hxdepots/sdp/helix_binaries/p4
TOKEN=$(curl --request PUT "http://169.254.169.254/latest/api/token" --header "X-aws-ec2-metadata-token-ttl-seconds: 3600")
EC2_DNS_PRIVATE=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname --header "X-aws-ec2-metadata-token: $TOKEN")
SDP_Setup_Script_Config=/hxdepots/sdp/Server/Unix/setup/mkdirs.cfg
# Check if SELinux is enabled, we need to relabel the service post installation otherwise it will not start p4d





SELINUX_STATUS=$(getenforce)

if [ "$SELINUX_STATUS" = "Enforcing" ] || [ "$SELINUX_STATUS" = "Permissive" ]; then
    echo "SELinux is enabled."
    if ! dnf list installed "$PACKAGE" &> /dev/null; then
        echo "Package $PACKAGE is not installed. Installing..."
        sudo dnf install -y "$PACKAGE"
        if [ $? -eq 0 ]; then
            echo "$PACKAGE installed successfully."
        else
            echo "Failed to install $PACKAGE."
        fi
    else
        echo "Package $PACKAGE is already installed."
    fi
else
    echo "SELinux is not enabled. Skipping package installation."
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
    echo "Waiting for $service_name to start... Attempt $attempt of $max_attempts."
    systemctl is-active --quiet $service_name && break
    sleep 1
    ((attempt++))
  done

  if [ $attempt -gt $max_attempts ]; then
    echo "Service $service_name did not start within the expected time."
    return 1
  fi

  echo "Service $service_name started successfully."
  return 0
}

echo "Installing Perforce"
dnf update -y

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
for dir in /hxdepots /hxlogs; do
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
