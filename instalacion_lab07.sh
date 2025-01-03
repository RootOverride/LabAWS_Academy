#!/bin/bash

# Solicitar nombre y apellido
read -p "Ingrese su nombre y apellido juntos (ejemplo: NombreApellido): " email

# Crear VPC
vpc_id=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
if [ $? -ne 0 ]; then
  echo "❌ Error al crear la VPC. Abortando."
  exit 1
fi
echo "✅ VPC creada con ID: $vpc_id"

# Asignar nombre a la VPC
aws ec2 create-tags --resources $vpc_id --tags Key=Name,Value="$email"
echo "✅ VPC etiquetada con el nombre: $email"

# Crear Subnet
subnet_id=$(aws ec2 create-subnet --vpc-id $vpc_id --cidr-block 10.0.1.0/24 --query 'Subnet.SubnetId' --output text)
echo "✅ Subnet creada con ID: $subnet_id"

# Crear Internet Gateway
igw_id=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
echo "✅ Internet Gateway creada con ID: $igw_id"

# Asociar Internet Gateway a la VPC
aws ec2 attach-internet-gateway --vpc-id $vpc_id --internet-gateway-id $igw_id
echo "✅ Internet Gateway asociada a la VPC"

# Crear Tabla de Rutas
route_table_id=$(aws ec2 create-route-table --vpc-id $vpc_id --query 'RouteTable.RouteTableId' --output text)
echo "✅ Tabla de rutas creada con ID: $route_table_id"

# Crear Ruta para permitir tráfico a Internet
aws ec2 create-route --route-table-id $route_table_id --destination-cidr-block 0.0.0.0/0 --gateway-id $igw_id
echo "✅ Ruta a Internet creada en la tabla de rutas"

# Asociar Tabla de Rutas a la Subnet
aws ec2 associate-route-table --route-table-id $route_table_id --subnet-id $subnet_id
echo "✅ Tabla de rutas asociada a la Subnet"

# Crear Security Group
sg_id=$(aws ec2 create-security-group --group-name "$email-sg" --description "Security Group para $email" --vpc-id $vpc_id --query 'GroupId' --output text)
echo "✅ Security Group creado con ID: $sg_id"

# Permitir tráfico SSH
aws ec2 authorize-security-group-ingress --group-id $sg_id --protocol tcp --port 22 --cidr 0.0.0.0/0
echo "✅ Se habilita el puerto 22 (SSH)"

# Permitir todo el tráfico interno
aws ec2 authorize-security-group-ingress --group-id $sg_id --protocol -1 --port -1 --cidr 10.0.0.0/16
echo "✅ Tráfico interno permitido"

# Crear Key Pair
aws ec2 create-key-pair --key-name "$email" --query 'KeyMaterial' --output text > "${email}.pem"
chmod 400 "${email}.pem"
echo "✅ Par de llaves creadas: ${email}.pem"

# Lanzar dos instancias Ubuntu
ami_id=$(aws ec2 describe-images --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*" --query 'Images[0].ImageId' --output text)
instance_ids=$(aws ec2 run-instances --image-id $ami_id --count 2 --instance-type t2.micro --key-name $email --security-group-ids $sg_id --subnet-id $subnet_id --query 'Instances[*].InstanceId' --output text)

echo "✅ Instancias lanzadas con los siguientes IDs: $instance_ids"

# Obtener el primer InstanceId
first_instance_id=$(echo $instance_ids | awk '{print $1}')
echo "📌 Primera instancia seleccionada para asignar Elastic IP: $first_instance_id"

# Crear y asociar Elastic IP
eip_allocation_id=$(aws ec2 allocate-address --query 'AllocationId' --output text)
aws ec2 associate-address --instance-id $first_instance_id --allocation-id $eip_allocation_id
echo "✅ Elastic IP asignada a la instancia: $first_instance_id"

# Verificar las instancias
aws ec2 describe-instances --instance-ids $instance_ids --query "Reservations[*].Instances[*].{ID:InstanceId,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress,State:State.Name}" --output table
