#!/bin/bash

# Solicitar el nombre de la clave (Key Pair) utilizada en la creación
read -p "Ingrese el nombre de su Key Pair (por ejemplo: NombreApellido): " email

# Validar si el Key Pair existe antes de intentar eliminarlo
if aws ec2 describe-key-pairs --key-name "$email" > /dev/null 2>&1; then
  # Eliminar Key Pair
  aws ec2 delete-key-pair --key-name "$email"
  echo "✅ Key Pair '$email' eliminado."
else
  echo "❌ El Key Pair '$email' no existe."
fi

# Obtener los IDs de las instancias asociadas
instance_ids=$(aws ec2 describe-instances --filters "Name=key-name,Values=$email" --query "Reservations[*].Instances[*].InstanceId" --output text)

if [ -n "$instance_ids" ]; then
  # Terminar las instancias
  aws ec2 terminate-instances --instance-ids $instance_ids
  echo "✅ Instancias terminadas: $instance_ids"

  # Esperar hasta que las instancias se terminen
  aws ec2 wait instance-terminated --instance-ids $instance_ids
  echo "✅ Instancias terminadas completamente."
else
  echo "❌ No se encontraron instancias para terminar."
fi

# Eliminar Elastic IP asociada
allocation_id=$(aws ec2 describe-addresses --query "Addresses[?InstanceId=='$instance_ids'].AllocationId" --output text)

if [ -n "$allocation_id" ]; then
  aws ec2 release-address --allocation-id $allocation_id
  echo "✅ Elastic IP liberada."
else
  echo "❌ No se encontró ninguna Elastic IP asociada."
fi

# Obtener el ID del Security Group
sg_id=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${email}-sg" --query "SecurityGroups[0].GroupId" --output text)

if [ -n "$sg_id" ]; then
  # Eliminar Security Group
  aws ec2 delete-security-group --group-id $sg_id
  echo "✅ Security Group eliminado: $sg_id"
else
  echo "❌ No se encontró el Security Group '${email}-sg'."
fi

# Obtener los IDs del Internet Gateway y la VPC
vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$email" --query 'Vpcs[0].VpcId' --output text)
igw_id=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --query "InternetGateways[0].InternetGatewayId" --output text)

if [ -n "$igw_id" ] && [ -n "$vpc_id" ]; then
  # Desasociar y eliminar Internet Gateway
  aws ec2 detach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id
  aws ec2 delete-internet-gateway --internet-gateway-id $igw_id
  echo "✅ Internet Gateway eliminado: $igw_id"

  # Eliminar VPC
  aws ec2 delete-vpc --vpc-id $vpc_id
  echo "✅ VPC eliminada: $vpc_id"
else
  echo "❌ No se encontró la VPC o el Internet Gateway asociado."
fi

echo "✅ Todos los recursos asociados con '$email' han sido eliminados."
