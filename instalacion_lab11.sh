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
aws ec2 create-route --route-table-id $route_table_id --destination-cidr-block 0.0.0.0/0 --gateway-id $igw_id > /dev/null 2>&1
echo "✅ Ruta a Internet creada en la tabla de rutas"

# Asociar Tabla de Rutas a la Subnet
aws ec2 associate-route-table --route-table-id $route_table_id --subnet-id $subnet_id > /dev/null 2>&1
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
instance_id1=$(aws ec2 run-instances --image-id $ami_id --instance-type t2.micro --key-name $email --security-group-ids $sg_id --subnet-id $subnet_id --query 'Instances[*].InstanceId' --output text)
instance_id2=$(aws ec2 run-instances --image-id $ami_id --instance-type t2.micro --key-name $email --security-group-ids $sg_id --subnet-id $subnet_id --query 'Instances[*].InstanceId' --output text)
echo "✅ Instancias lanzadas con los siguientes IDs: $instance_id1 - $instance_id2"

# Obtener el primer InstanceId
echo "📌 Primera instancia seleccionada para asignar Elastic IP: $instance_id1"
echo "⏳ Esperando a que la instancia $instance_id1 esté disponible para asociar la IP elastica..."
sleep 100

# Crear y asociar Elastic IP
eip_allocation_id=$(aws ec2 allocate-address --query 'AllocationId' --output text)
aws ec2 associate-address --instance-id $instance_id1 --allocation-id $eip_allocation_id > /dev/null 2>&1
echo "✅ Elastic IP asignada a la instancia: $instance_id1"

###### Instalación de paquetes en maquina 1

# Obtener la dirección IP pública de la instancia
public_ip=$(aws ec2 describe-instances --instance-ids $instance_id1 --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

echo "📡 Conectando a la instancia en $public_ip..."

# Esperar a que la instancia esté lista para SSH
#echo "⏳ Esperando que la instancia esté lista para SSH..."
#sleep 60

# Conectar por SSH y ejecutar comandos remotos
ssh -o StrictHostKeyChecking=no -i "${email}.pem" ubuntu@$public_ip << 'EOF'
  echo "✅ Conexión SSH establecida."
  
  # Actualizar el sistema
  sudo apt update -y
  sudo apt upgrade -y
  
  # Instalar Nmap
  sudo apt install nmap -y
  
  # Accediendo a la otra instancia 2
  private_ip_second_instance=$(aws ec2 describe-instances --instance-ids $instance_id2 --query "Reservations[*].Instances[*].PrivateIpAddress" --output text)
  ssh -o StrictHostKeyChecking=no -i "${email}.pem" ubuntu@$private_ip_second_instance << 'INNER_EOF'
    sudo apt update -y
    sudo apt upgrade -y
    sudo apt install mc -y
  INNER_EOF
EOF

echo "✅ Comandos remotos ejecutados en la instancia en $instance_id1 y $instance_id1"



# Verificar las instancias
aws ec2 describe-instances --instance-ids $instance_id1 $instance_id2 --query "Reservations[*].Instances[*].{ID:InstanceId,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress,State:State.Name}" --output table
cat "${email}.pem"


echo ""
echo "############################################################################################################################"
echo "✅✅✅ Proceso Finalizado: Su laboratorio ya se encuntra disponible, ahora! Es tu momento de Brillar!!!..."
echo "############################################################################################################################"
echo ""