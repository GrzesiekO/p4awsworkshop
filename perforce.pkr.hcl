packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.2"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "rocky" {
  ami_name      = "P4_Base_Rocky9.2_raw"
  instance_type = "t3.medium"
  region        = "eu-west-2"
  source_ami_filter {
    filters = {
      name                = "Rocky-9-EC2-Base-9.2-20230513.0.x86_64*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["679593333241"]
  }
  ssh_username = "rocky"
}

build {
  name = "P4_SDP_AWS"
  sources = [
    "source.amazon-ebs.rocky"
  ]


   provisioner "shell" {
	
      script = "p4_setup.sh"
      execute_command = "sudo sh {{.Path}}"

}


}
