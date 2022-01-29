#!/bin/bash



#describing availability zones.
current_region=us-east-2
az_a="${current_region}a"
az_b="${current_region}b"

#creating vpc and storing the vpc id in vpc_id
aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
    --tag-specifications ResourceType=vpc,Tags='[{Key=Name,Value="Opstree"}]'

vpc_id=$(aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text)

#creating an internet gateway and associate it to VPC.
aws ec2 create-internet-gateway
igw=$(aws ec2 describe-internet-gateways --query 'InternetGateways[0].InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id $vpc_id --internet-gateway-id $igw

#Creating 2 Public Subnets in AZa and AZb
aws ec2 create-subnet --vpc-id $vpc_id --cidr-block 10.0.1.0/24 --availability-zone $az_a \
    --tag-specifications ResourceType=subnet,Tags='[{Key=Name,Value=Opstree-pub-1}]'

pub_sub_id_a=$(aws ec2 describe-subnets --filters "Name=cidr-block,Values=10.0.1.0/24" --query 'Subnets[0].SubnetId' --output text)


aws ec2 create-subnet --vpc-id $vpc_id --cidr-block 10.0.2.0/24 --availability-zone $az_b \
    --tag-specifications ResourceType=subnet,Tags='[{Key=Name,Value=Opstree-pub-2}]'

pub_sub_id_b=$(aws ec2 describe-subnets --filters "Name=cidr-block,Values=10.0.2.0/24" --query 'Subnets[0].SubnetId' --output text)

#Creating 2 Private Subnets in AZa and AZb
aws ec2 create-subnet --vpc-id $vpc_id --cidr-block 10.0.3.0/24 --availability-zone $az_a \
    --tag-specifications ResourceType=subnet,Tags='[{Key=Name,Value=Opstree-pvt-1}]'

pvt_sub_id_a=$(aws ec2 describe-subnets --filters "Name=cidr-block,Values=10.0.3.0/24" --query 'Subnets[0].SubnetId' --output text)

aws ec2 create-subnet --vpc-id $vpc_id --cidr-block 10.0.4.0/24 --availability-zone $az_b \
    --tag-specifications ResourceType=subnet,Tags='[{Key=Name,Value=Opstree-pvt-2}]'

pvt_sub_id_b=$(aws ec2 describe-subnets --filters "Name=cidr-block,Values=10.0.4.0/24" --query 'Subnets[0].SubnetId' --output text)

# Create two Route Table.
aws ec2 create-route-table --vpc-id $vpc_id \
    --tag-specifications ResourceType=route-table,Tags='[{Key=Name,Value="public-route"}]'

pub_rt=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=public-route" --query 'RouteTables[0].RouteTableId' --output text)

aws ec2 create-route-table --vpc-id $vpc_id \
    --tag-specifications ResourceType=route-table,Tags='[{Key=Name,Value="private-route"}]'

pvt_rt=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=private-route" --query 'RouteTables[0].RouteTableId' --output text)

#Alocate Elastic IP and store it in a variable
aws ec2 allocate-address
elastic_ip=$(aws ec2 describe-addresses --query "Addresses[0].AllocationId" --output text)

# Create NAT Gateway in Public Subnet $pub_sub_id_a.

aws ec2 create-nat-gateway \
    --subnet-id $pub_sub_id_a \
    --allocation-id $elastic_ip

nat_gw=$(aws ec2 describe-nat-gateways --query 'NatGateways[0].NatGatewayId' --output text)

# Create Route to public routetable for internet connectivity.

aws ec2 create-route --route-table-id $pub_rt \
    --destination-cidr-block 0.0.0.0/0 --gateway-id $igw

# Create Route to private routetable for NAT Gateway

aws ec2 create-route --route-table-id $pvt_rt \
    --destination-cidr-block 0.0.0.0/0 --gateway-id $nat_gw

#Associate Public Subnet in AZa with Public Route Table.
aws ec2 associate-route-table --route-table-id $pub_rt --subnet-id $pub_sub_id_a

#Associate Public Subnet in AZb with Public Route Table.
aws ec2 associate-route-table --route-table-id $pub_rt --subnet-id $pub_sub_id_b

#Associate Private Subnet in Aza with Private Route Table.
aws ec2 associate-route-table --route-table-id $pvt_rt --subnet-id $pvt_sub_id_a

#Associate Private Subnet 2 with Private Route Table.
aws ec2 associate-route-table --route-table-id $pvt_rt --subnet-id $pvt_sub_id_b

# Create Security Group in $vpc_id for Bastian and store it in a variable $sg_id_bastian
aws ec2 create-security-group --group-name Bastian_Server_SG \
    --description "My security group for Bastian Server" --vpc-id $vpc_id

sg_id_bastian=$(aws ec2 describe-security-groups --filters "Name=description,Values=My security group for Bastian Server" --query 'SecurityGroups[0].GroupId' --output text)

# create rules in security group for Bastian and open it for SSH Port 22 from anywhere.
aws ec2 authorize-security-group-ingress \
    --group-id $sg_id_bastian \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0



#Create Security Group in $vpc_id for Webserver and store it in a variable $sg_id_bastian
aws ec2 create-security-group --group-name Web_Server_SG \
    --description "My security group for Webserver Server" --vpc-id $vpc_id

sg_id_webserver=$(aws ec2 describe-security-groups --filters "Name=description,Values=My security group for Webserver Server" --query 'SecurityGroups[0].GroupId' --output text)

#Install Bastian Host and store its private IP $private_ip_bastian


aws ec2 run-instances \
    --image-id 'ami-03a0c45ebc70f98ea' \
    --instance-type 't2.micro' \
    --subnet-id $pub_sub_id_a \
    --security-group-ids $sg_id_bastian \
    --associate-public-ip-address \
    --key-name 'Ohio'


private_ip_bastian=$(aws ec2 describe-instances --filter "Name=image-id,Values=ami-03a0c45ebc70f98ea" --query "Reservations[].Instances[0].PrivateIpAddress" --output text)

# create rules in security group for WebServer and open it for SSH Port 22 from $private_ip_bastian
aws ec2 authorize-security-group-ingress \
    --group-id $sg_id_webserver \
    --protocol tcp \
    --port 22 \
    --cidr ${private_ip_bastian}/32

#Open port 80 for anywhere
aws ec2 authorize-security-group-ingress \
    --group-id $sg_id_webserver \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0


#Install Webserver_A in $pri_sub_id_a

aws ec2 run-instances \
    --image-id 'ami-03a0c45ebc70f98ea' \
    --instance-type 't2.micro' \
    --subnet-id $pub_sub_id_a \
    --security-group-ids $sg_id_webserver \
    --key-name 'Ohio'

#Install Webserver_A in $pri_sub_id_b

aws ec2 run-instances \
    --image-id 'ami-03a0c45ebc70f98ea' \
    --instance-type 't2.micro' \
    --subnet-id $pub_sub_id_b \
    --security-group-ids $sg_id_webserver \
    --key-name 'Ohio'