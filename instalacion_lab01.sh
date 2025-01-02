#!/usr/bin/env bash
set -e

########################################
# 1. VARIABLES DE CONFIGURACIÓN
########################################
# AMIs (ajusta a tu región si cambia el ID)
UBUNTU_AMI="ami-005fc0f236362e99f"    # Ubuntu Server 22.04 LTS
WINDOWS_AMI="ami-0a9ddfd0e84a3031f"  # Microsoft Windows Server 2025 Core Base

# Tipo de instancia (ajusta a lo disponible en tu lab)
INSTANCE_TYPE="t2.micro"

# Nombres de recursos
SG_NAME="SG-Lab-Interno"
SG_DESC="SG para Ubuntu y Windows con puertos abiertos internos"
KEY_UBUNTU="MyKeyPairUbuntu"
KEY_WINDOWS="MyKeyPairWindows"

########################################
# 2. OBTENER LA VPC POR DEFECTO
########################################
echo "Obteniendo la VPC por defecto..."
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)

if [ "$DEFAULT_VPC_ID" = "None" ] || [ -z "$DEFAULT_VPC_ID" ]; then
  echo "No se encontró VPC por defecto. Asegúrate de tener una VPC o crea una manualmente."
  exit 1
fi
echo "VPC por defecto: $DEFAULT_VPC_ID"

########################################
# 3. CREAR EL SECURITY GROUP
########################################
echo "Creando Security Group: $SG_NAME..."
SG_ID=$(aws ec2 create-security-group \
  --group-name "$SG_NAME" \
  --description "$SG_DESC" \
  --vpc-id "$DEFAULT_VPC_ID" \
  --query 'GroupId' \
  --output text)

echo "Security Group creado con ID: $SG_ID"

# Reglas de entrada:
# SSH (22) abierto a todos (solo para lab; en prod usar IP específica).
echo "Agregando regla SSH (puerto 22) al SG..."
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# RDP (3389) abierto a todos (solo para lab; en prod usar IP específica).
echo "Agregando regla RDP (puerto 3389) al SG..."
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 3389 \
  --cidr 0.0.0.0/0

# Comunicación interna libre entre instancias que usen este SG (All traffic).
echo "Agregando regla de tráfico interno (todo) entre instancias del SG..."
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol -1 \
  --port all \
  --source-group "$SG_ID"

########################################
# 4. CREAR LAS KEY PAIRS PARA SSH Y WINDOWS
########################################
# (Sobrescribe si ya existen con el mismo nombre)
if [ -f "${KEY_UBUNTU}.pem" ]; then rm -f "${KEY_UBUNTU}.pem"; fi
if [ -f "${KEY_WINDOWS}.pem" ]; then rm -f "${KEY_WINDOWS}.pem"; fi

echo "Creando Key Pair para Ubuntu..."
aws ec2 create-key-pair \
  --key-name "$KEY_UBUNTU" \
  --query 'KeyMaterial' \
  --output text > "${KEY_UBUNTU}.pem"

chmod 400 "${KEY_UBUNTU}.pem"

echo "Creando Key Pair para Windows..."
aws ec2 create-key-pair \
  --key-name "$KEY_WINDOWS" \
  --query 'KeyMaterial' \
  --output text > "${KEY_WINDOWS}.pem"

chmod 400 "${KEY_WINDOWS}.pem"

########################################
# 5. OBTENER UN SUBNET PÚBLICO DENTRO DE LA VPC POR DEFECTO
########################################
# Tomamos el primer subnet asociado a la VPC por defecto (suele ser público).
echo "Obteniendo un subnet (público) de la VPC por defecto..."
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" \
  --query "Subnets[0].SubnetId" \
  --output text)

if [ "$SUBNET_ID" = "None" ] || [ -z "$SUBNET_ID" ]; then
  echo "No se encontró subnet en la VPC por defecto. Revisa tu configuración."
  exit 1
fi
echo "Subnet seleccionado: $SUBNET_ID"

########################################
# 6. CREAR INSTANCIA UBUNTU
########################################
echo "Lanzando instancia Ubuntu con AMI: $UBUNTU_AMI..."
UBUNTU_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$UBUNTU_AMI" \
  --count 1 \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_UBUNTU" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET_ID" \
  --associate-public-ip-address \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Esperando a que la instancia Ubuntu esté en estado 'running'..."
aws ec2 wait instance-running --instance-ids "$UBUNTU_INSTANCE_ID"
echo "Instancia Ubuntu (ID: $UBUNTU_INSTANCE_ID) lanzada y corriendo."

########################################
# 7. CREAR INSTANCIA WINDOWS
########################################
echo "Lanzando instancia Windows con AMI: $WINDOWS_AMI..."
WINDOWS_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$WINDOWS_AMI" \
  --count 1 \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_WINDOWS" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET_ID" \
  --associate-public-ip-address \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Esperando a que la instancia Windows esté en estado 'running'..."
aws ec2 wait instance-running --instance-ids "$WINDOWS_INSTANCE_ID"
echo "Instancia Windows (ID: $WINDOWS_INSTANCE_ID) lanzada y corriendo."

########################################
# 8. ASIGNAR UNA ELASTIC IP A UBUNTU
########################################
echo "Solicitando Elastic IP..."
EIP_ALLOC_ID=$(aws ec2 allocate-address --query 'AllocationId' --output text)

echo "Asociando Elastic IP a la instancia Ubuntu..."
aws ec2 associate-address \
  --instance-id "$UBUNTU_INSTANCE_ID" \
  --allocation-id "$EIP_ALLOC_ID"

EIP_PUBLIC_IP=$(aws ec2 describe-addresses \
  --allocation-ids "$EIP_ALLOC_ID" \
  --query 'Addresses[0].PublicIp' \
  --output text)

########################################
# 9. MOSTRAR INFORMACIÓN FINAL
########################################
echo "======================================================"
echo "Despliegue finalizado."
echo
echo "Ubuntu Instance ID:   $UBUNTU_INSTANCE_ID"
echo "Ubuntu Elastic IP:    $EIP_PUBLIC_IP"
echo "Key Pair Ubuntu:      ${KEY_UBUNTU}.pem"
echo
echo "Windows Instance ID:  $WINDOWS_INSTANCE_ID"
WINDOWS_PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$WINDOWS_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)
echo "Windows Public IP:    $WINDOWS_PUBLIC_IP (Ephemeral)"
echo "Key Pair Windows:     ${KEY_WINDOWS}.pem"
echo
echo "Para conectarte a Ubuntu por SSH:"
echo "ssh -i ${KEY_UBUNTU}.pem ubuntu@${EIP_PUBLIC_IP}"
echo
echo "Para conectarte a Windows por RDP (si no es Core) o configurar PowerShell Remoting (si es Core)."
echo "======================================================"
