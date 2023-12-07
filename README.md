# p4awsworkshop
This is a repository of a P4 hosting on AWS workshop. Check at your own risk. 

### Creating an EC2 Instance

1. **Create a Key Pair**:  
   Create a key pair for SSH access to your EC2 instance. Replace `MyKeyPair` with your desired key pair name.

   ```bash
   aws ec2 create-key-pair --key-name MyKeyPair --query 'KeyMaterial' --output text > MyKeyPair.pem
   chmod 400 MyKeyPair.pem


Create a Security Group:
Create a security group that allows SSH and TCP port 1666 for inbound connections. Replace MySecurityGroup with your desired security group name.

bash
Copy code
aws ec2 create-security-group --group-name MySecurityGroup --description "Security group for Perforce server"
aws ec2 authorize-security-group-ingress --group-name MySecurityGroup --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-name MySecurityGroup --protocol tcp --port 1666 --cidr 0.0.0.0/0
Launch an EC2 Instance:
Launch an EC2 instance using the created key pair and security group. Replace ami-xxxxxxxxxxxxxx with the AMI ID of your choice.

bash
Copy code
aws ec2 run-instances --image-id ami-xxxxxxxxxxxxxx --count 1 --instance-type t2.micro --key-name MyKeyPair --security-groups MySecurityGroup
Note: Ensure the AMI ID (ami-xxxxxxxxxxxxxx) is compatible with your region and requirements.

Perforce Helix Core Server Setup
This workshop guides you through the process of setting up a Perforce Helix Core server using the provided p4_setup.sh script. The script automates the installation and configuration of a Perforce server on a Linux environment, specifically tailored for an EC2 instance.

Prerequisites
A Linux-based EC2 instance (the script is tailored for Amazon Linux).
Root access to the instance.
Basic knowledge of Linux command line and Perforce.
Getting Started
Clone the Repository:
Clone this repository to your local machine or directly to your EC2 instance.

bash
Copy code
git clone [REPO_URL]
Navigate to the Script:
Change to the directory containing the p4_setup.sh script.

bash
Copy code
cd [REPO_DIRECTORY]
Script Overview
The p4_setup.sh script performs the following actions:

Verifies the script is run as root.
Installs necessary packages and sets up the environment.
Configures Perforce user and groups.
Downloads and sets up the Perforce Software Development Platform (SDP).
Configures Perforce server (p4d) as a systemd service.
Generates SSL certificates and configures SELinux policies.
Initializes Perforce server and client settings.
Execution
Run the Script:
Execute the script as root or using sudo.

bash
Copy code
sudo bash p4_setup.sh
Follow the Script Execution:
The script will output progress logs. Monitor these to understand what the script is doing at each step.

Post-Setup
After the script completes, your Perforce Helix Core server should be up and running. Here are some post-setup steps:

Trust the SSL Certificate:
Run the following command to trust the SSL certificate for Perforce.

bash
Copy code
p4 -p ssl:$HOSTNAME:1666 trust -y
Verify the Installation:
You can verify the SDP installation using:

bash
Copy code
/hxdepots/p4/common/bin/verify_sdp.sh 1
This should warn about a missing license, which is expected.

Troubleshooting
If you encounter any issues during the setup, review the console output for errors.
Ensure that you have the necessary permissions and that SELinux is correctly configured.
Contributing
Feel free to contribute to this script by submitting pull requests or filing issues in the GitHub repository.

Creating a Forwarding Replica with SDP
To create a forwarding replica of your Perforce Helix Core server, follow these steps:

Setting Up the Environment
Create a Second EC2 Instance:
Launch a second EC2 instance using the same security group as your primary Perforce server to ensure network connectivity and proper security settings.

Set Up the SDP Environment:
Install and configure the SDP environment on the new instance as you did for the primary server. Follow the initial setup steps from the primary server installation.

Configuring Site Tags
Copy the SiteTags Template:
Copy the SiteTags.cfg.sample to SiteTags.cfg.

bash
Copy code
cp /hxdepots/sdp/Server/Unix/p4/common/config/SiteTags.cfg.sample /hxdepots/p4/common/config/SiteTags.cfg
Edit SiteTags.cfg:
Add the AWS region as a new site entry, for example, awseuwest2 for the eu-west-2 region.

Using mkrep.sh to Create the Replica
Run mkrep.sh:
Execute the mkrep.sh script to create the forwarding replica configuration. Replace [parameters] with the necessary arguments for your setup.

bash
Copy code
/path/to/mkrep.sh [parameters]
Manual Steps for Phase 2:
After running mkrep.sh, complete the manual steps required for Phase 2 of the setup. [Here, include specific instructions or refer to the appropriate section of the SDP guide that outlines these steps.]