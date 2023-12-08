# P4d hosting on AWS

This is a repository of a P4 hosting on AWS workshop. Check at your own risk.

## Creating an EC2 Instance

1. **Create a Key Pair**:  
   Create a key pair for SSH access to your EC2 instance. Replace `MyKeyPair` with your desired key pair name.

   ```bash
   aws ec2 create-key-pair --key-name MyKeyPair --query 'KeyMaterial' --output text > MyKeyPair.pem
   chmod 400 MyKeyPair.pem

### Create a Security Group

1. **Create a security group that allows SSH and TCP port 1666 for inbound connections. Replace MySecurityGroup with your desired security group name.**

```bash
aws ec2 create-security-group --group-name MySecurityGroup --description "Security group for Perforce server"
aws ec2 authorize-security-group-ingress --group-name MySecurityGroup --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-name MySecurityGroup --protocol tcp --port 1666 --cidr 0.0.0.0/0

```

1. **Launch an EC2 Instance:**
Launch an EC2 instance using the created key pair and security group. Replace ami-xxxxxxxxxxxxxx with the AMI ID of your choice.

```bash

aws ec2 run-instances --image-id ami-xxxxxxxxxxxxxx --count 1 --instance-type t2.micro --key-name MyKeyPair --security-groups MySecurityGroup
```

Note: Ensure the AMI ID (ami-xxxxxxxxxxxxxx) is compatible with your region and requirements.

### Perforce Helix Core Server Setup

This workshop guides you through the process of setting up a Perforce Helix Core server using the provided p4_setup.sh script. The script automates the installation and configuration of a Perforce server on a Linux environment, specifically tailored for an EC2 instance.

**Prerequisites**
A Linux-based EC2 instance (the script is tailored for Amazon Linux or RHEL based distros i.e. Rocky Linux or AL2023).
Root access to the instance.
Basic knowledge of Linux command line and Perforce.
Getting Started
Clone the Repository:
Clone this repository to your local machine or directly to your EC2 instance.

```bash
git clone https://github.com/GrzesiekO/p4awsworkshop.git
```

Navigate to the Script:

Change to the directory containing the p4_setup.sh script.

```bash

cd p4awsworkshop

```

### Script Overview

The p4_setup.sh script performs the following actions:

1. Verifies the script is run as root.
1. Installs necessary packages (mainly policy utils for SElinux, P4d has no package dependency) and sets up the environment.
1. Configures Perforce user and groups.
1. Downloads and sets up the Perforce Software Development Platform (SDP).
1. Configures Perforce server (p4d) as a systemd service.
1. Generates SSL certificates and configures SELinux policies.
1. Initializes Helix Core server and client settings.

### Execution

Run the Script:
Execute the script as root or using sudo.

```bash

sudo bash p4_setup.sh

```

**Follow the Script Execution:**
The script will output progress logs. Monitor these to understand what the script is doing at each step.

**Post-Setup**
After the script completes, your Perforce Helix Core server should be up and running. Here are some post-setup steps:

**Trust the SSL Certificate:**
Run the following command to trust the SSL certificate for Perforce.

```bash

p4 -p ssl:$HOSTNAME:1666 trust -y
```

Verify the Installation:
You can verify the SDP installation using:

```bash

/hxdepots/p4/common/bin/verify_sdp.sh 1
```

> Where "1" is the instance id of the perforce server


This should warn about a missing license, which is expected.

**Troubleshooting**
If you encounter any issues during the setup, review the console output for errors.
Ensure that you have the necessary permissions and that SELinux is correctly configured.
Contributing
Feel free to contribute to this script by submitting pull requests or filing issues in the GitHub repository.

### Creating a Forwarding Replica with SDP

Perforce SDP (Server Deployment Package) concists of a shell script called "mkrep.sh" that simplifies setup of any of the Helix Core server types (Edge/Standby Replica/Forwarding Replica or Proxy).

During this workshop you will setup a Forwarding Replica **Unfiltered** that is a valid target for a P4 failover.

To create a forwarding replica of your Perforce Helix Core server, follow these steps:

1. Create a replica host. (This might be a later step however mkrep.sh script requires a valid DNS name for a replica server - Amazon Route53 Private Hosted Zone can solve this challange but it adds complexity and it is not main focus of this workshop).
Route53 Private Hosted Zone information can be found here: <https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zone-private-creating.html>

2. Copy SiteTags.cfg.sample template to /hxdepots/p4/common/config directory (SiteTags are necessery parameter for a mkrep.sh script).

3. Create a new site tag for AWS Region/Subnet that you will use for a replica host.

4. Run the mkrep.sh script on a P4 Commit server first.

5. Install a P4 on a replica host (use basic setup of a mkdirs.sh - remember about the -t option with p4d_replica parameter) **Replica differs from commit in configuration binary is the same, replica issues p4 pull command to pull journal sequence and archived files.**

6. Make a seed checkpoint from P4 Commit

7. Copy a seed checkpoint to a Replica host **Multiple ways of copying files between EC2 instances exists - we can use Shared FSx/S3 bucket or tools like: rsync or scp, which depending on the region/network configuration may require additional VPC Peering/Transit Gateway operations. Perforce suggest using rsync for copying archived files.
Use: <https://docs.aws.amazon.com/fsx/latest/OpenZFSGuide/creating-file-systems.html> for reference.

8. Restore a seed checpoint on a replica host.

9. Login service user and p4 admin from replica to master

10. Check the replication status p4 pull -lj p4 servers -J or p4 pull -ls run from a replica host.

### Detailed Steps

Setting Up the Environment
Create a Second EC2 Instance:
Launch a second EC2 instance using the same security group as your commit Perforce server to ensure network connectivity and proper security settings.

Set Up the SDP Environment:
Install and configure the SDP environment on the new instance as you did for the commit server. Follow the initial setup steps from the commit server installation.

Configuring Site Tags
Copy the SiteTags Template:

```bash

cp /hxdepots/sdp/Server/Unix/p4/common/config/SiteTags.cfg.sample /hxdepots/p4/common/config/SiteTags.cfg

```

Edit SiteTags.cfg:

Add the AWS region as a new site entry, for example, awseuwest2 for the eu-west-2 region.

Use mkrep.sh to Create the Replica (on a commit server first)
Run mkrep.sh:
Execute the mkrep.sh script to create the forwarding replica configuration. Replace [parameters] with the necessary arguments for your setup.

```bash

/path/to/mkrep.sh [parameters]

```

Manual Steps for Phase 2:
After running mkrep.sh, complete the manual steps required for Phase 2 of the setup. [Here, include specific instructions or refer to the appropriate section of the SDP guide that outlines these steps.]
