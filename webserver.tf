#Selecting provider for Terraform 
provider "aws" {
  region = "ap-south-1"   # Replace with your desired AWS region
}

#Creating VPC to run the the webserver into it
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"        #Configure the VPC
  tags = {
    Name = "TerraformVPC"  # Set the name prefix for the VPC
  }
} 

#Creating specific subnet to attach the EC2 instance 
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"        #Configure Subnet within VPC
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true

   tags = {
    Name = "TSubnet"  # Set the name prefix for the subnet
  }
}

#Creating the security policy for the Subnet
resource "aws_security_group" "web_server_sg" {
  name_prefix = "web-server-sg-"
  description = "Security group for web servers"
  vpc_id = aws_vpc.main.id  #Apply security policy to VPC
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


#Creating the EC2 with the above configuration
resource "aws_instance" "web_server" {
  ami           = "ami-0ded8326293d3201b"  # Replace with the Image for your region
  instance_type = "t2.micro"
  key_name      = "vpn_srmist"  # Replace with the name of your key pair
  # private_ip = "10.0.1.12"
  vpc_security_group_ids = [aws_security_group.web_server_sg.id] #Attatch security groups with EC2
  subnet_id = aws_subnet.public.id

  tags = {
    Name = "Web Server Terraform"
  }
}

# Create the interface to attach
resource "aws_network_interface" "network_nic" {
  subnet_id   = aws_subnet.public.id
  private_ips = ["10.0.1.100"]

   attachment {
    instance     = aws_instance.web_server.id
    device_index = 1
  }

  tags = {
    Name = "TerraformInterface"
  }
}



# #Attach the interface with ec2
# resource "aws_network_interface_attachment" "ec2_attachment" {
#   instance_id          = aws_instance.web_server.id
#   network_interface_id = aws_network_interface.network_nic.id
#   device_index         = 1  # Specify the appropriate device index
#   # 0 means primary network interface
# }


resource "aws_internet_gateway" "aws_igw" {
  vpc_id = aws_vpc.main.id   #Need to setup elastic IP
}

#Allocate and assign an Elastic IP with the specified EC2 instance
resource "aws_eip" "web_server_eip" {
  domain   = "vpc"  # Use 'vpc' for a VPC Elastic IP
  #instance = aws_instance.web_server.id
  network_interface = aws_network_interface.network_nic.id
  associate_with_private_ip = "10.0.1.100"
  # Specify the network interface ID if you have multiple instances
}

#Outputs the Elastic IP that was assigned to the specified EC2 instance
output "public_ip" {
  value = aws_eip.web_server_eip.public_ip
}