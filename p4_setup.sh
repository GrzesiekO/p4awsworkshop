#!/bin/bash

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
EC2_DNS_PRIVATE=$(curl -s http://169.254.169.254/latest/meta-data/hostname)
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


#update the mkdirs.cfg so it has proper hostname a private DNS form EC2 otherwise adding replica is not possible due to wrong P4TARGET settings.

if [ ! -f "$SDP_Setup_Script_Config" ]; then
    echo "Error: Configuration file not found at $SDP_Setup_Script_Config."
    exit 1
fi


# Update P4MASTERHOST value in the configuration file
sed -i "s/^P4MASTERHOST=.*/P4MASTERHOST=$EC2_DNS_PRIVATE/" "$SDP_Setup_Script_Config"

echo "Updated P4MASTERHOST to $EC2_DNS_PRIVATE in $SDP_Setup_Script_Config."


# Execute mkdirs.sh from the extracted package
if [ -f "$SDP_Setup_Script" ]; then
  chmod +x "$SDP_Setup_Script"
  "$SDP_Setup_Script" 1
else
  echo "Setup script (mkdirs.sh) not found."
fi

# update cert config with ec2 DNS name
FILE_PATH="/p4/ssl/config.txt"

# Retrieve the EC2 instance DNS name
EC2_DNS_NAME=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)


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

