#!/bin/bash
###############################################################################
# Script: Crear VPC, Subred Pública, Subred Privada, IGW, Rutas e Instancias
#         (Kali con Internet / Metasploitable2 sin Internet),
#         Identificadas por EMAIL del estudiante.
#         Al final, se muestra la información de conexión (IP y credenciales).
#
# Adaptado por: [Dionisio Vega Estay - 01-01-2025]
#
# Uso:
#   ./script.sh alumno@estudiantes.iacc.cl
###############################################################################

##############################
# 1) Validar el parámetro EMAIL
##############################
if [ $# -le 0 ]; then
    echo "Debes introducir el correo electrónico institucional como parámetro."
    echo "Ejemplo: sh ./script.sh alumno@ejemplo.com"
    exit 1
fi

EMAIL="$1"

# Validación mínima para correo
if [[ "$EMAIL" != *"@"* ]]; then
  echo "Error: el parámetro no parece un correo electrónico válido (falta '@')."
  exit 1
fi

# Reemplazar caracteres conflictivos (@ y .) en las tags
NAME_TAG=$(echo "$EMAIL" | sed 's/@/-/g; s/\./-/g')

echo "Correo del alumno: $EMAIL"
echo "Tag para recursos: $NAME_TAG"

##############################
# 2) Variables de configuración
##############################
AWS_VPC_CIDR_BLOCK="10.24.0.0/16"
AWS_SubredPublica_CIDR_BLOCK="10.24.1.0/24"
AWS_SubredPrivada_CIDR_BLOCK="10.24.2.0/24"

# IPs privadas fijas
AWS_IP_KALI="10.24.1.100"
AWS_IP_METASPLOITABLE="10.24.2.200"

# Nombre de Proyecto (basado en el correo)
AWS_Proyecto="SRI24-${NAME_TAG}"

# Parámetros de AMI, usuario y key para Kali
AWS_AMI_KALI_ID="ami-005fc0f236362e99f"  # Ajustar a tu región/AMI de Kali
KALI_USER="kali"                        # Ajusta si tu AMI usa otro username (ej. "ec2-user" o "ubuntu")
SSH_KEY_NAME="vockey"                   # Clave que existe en tu cuenta
SSH_KEY_FILE="vockey.pem"               # Archivo .pem local (opcional para mostrar)

# Parámetros de AMI, usuario y pass para Metasploitable2
AWS_AMI_MS2_ID="ami-005fc0f236362e99f"  # Ajusta a tu AMI de Metasploitable2
METASPLOITABLE_USER="msfadmin"
METASPLOITABLE_PASS="msfadmin" # Contraseña por defecto

echo "====================================================================="
echo "Desplegando recursos para el alumno: $EMAIL"
echo "Proyecto (tag)        : $AWS_Proyecto"
echo "VPC CIDR              : $AWS_VPC_CIDR_BLOCK"
echo "Subred pública CIDR   : $AWS_SubredPublica_CIDR_BLOCK"
echo "Subred privada CIDR   : $AWS_SubredPrivada_CIDR_BLOCK"
echo "Kali (pública) IP     : $AWS_IP_KALI"
echo "Metasploitable (priv.) IP : $AWS_IP_METASPLOITABLE"
echo "====================================================================="

###############################################################################
# 3) Crear la VPC con soporte IPv6
###############################################################################
echo "[1/9] Creando VPC..."
AWS_ID_VPC=$(aws ec2 create-vpc \
  --cidr-block "$AWS_VPC_CIDR_BLOCK" \
  --amazon-provided-ipv6-cidr-block \
  --tag-specifications ResourceType=vpc,Tags=[{Key=Name,Value=$AWS_Proyecto-vpc}] \
  --query 'Vpc.VpcId' \
  --output text)

# Obtener rango IPv6
AWS_IPV6_CIDR_BLOCK=$(aws ec2 describe-vpcs \
  --vpc-ids "$AWS_ID_VPC" \
  --query 'Vpcs[0].Ipv6CidrBlockAssociationSet[0].Ipv6CidrBlock' \
  --output text)

# Dividimos para subredes /64 (ejemplo simplificado)
AWS_IPV6_PREFIX=$(echo "$AWS_IPV6_CIDR_BLOCK" | cut -d ":" -f 1-3)
AWS_SubredPublica_IPv6_CIDR="${AWS_IPV6_PREFIX}:0001::/64"
AWS_SubredPrivada_IPv6_CIDR="${AWS_IPV6_PREFIX}:0002::/64"

# Habilitar nombres DNS
aws ec2 modify-vpc-attribute \
  --vpc-id "$AWS_ID_VPC" \
  --enable-dns-hostnames '{"Value":true}'

###############################################################################
# 4) Crear subred pública y subred privada
###############################################################################
echo "[2/9] Creando Subred Pública..."
AWS_ID_SubredPublica=$(aws ec2 create-subnet \
  --vpc-id "$AWS_ID_VPC" \
  --cidr-block "$AWS_SubredPublica_CIDR_BLOCK" \
  --ipv6-cidr-block "$AWS_SubredPublica_IPv6_CIDR" \
  --availability-zone us-east-1a \
  --tag-specifications ResourceType=subnet,Tags=[{Key=Name,Value=$AWS_Proyecto-subred-publica}] \
  --query 'Subnet.SubnetId' \
  --output text)

aws ec2 modify-subnet-attribute \
  --subnet-id "$AWS_ID_SubredPublica" \
  --map-public-ip-on-launch

echo "[2.1/9] Creando Subred Privada..."
AWS_ID_SubredPrivada=$(aws ec2 create-subnet \
  --vpc-id "$AWS_ID_VPC" \
  --cidr-block "$AWS_SubredPrivada_CIDR_BLOCK" \
  --ipv6-cidr-block "$AWS_SubredPrivada_IPv6_CIDR" \
  --availability-zone us-east-1a \
  --tag-specifications ResourceType=subnet,Tags=[{Key=Name,Value=$AWS_Proyecto-subred-privada}] \
  --query 'Subnet.SubnetId' \
  --output text)

###############################################################################
# 5) Crear y adjuntar Internet Gateway
###############################################################################
echo "[3/9] Creando Internet Gateway..."
AWS_ID_IGW=$(aws ec2 create-internet-gateway \
  --tag-specifications ResourceType=internet-gateway,Tags=[{Key=Name,Value=$AWS_Proyecto-igw}] \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 attach-internet-gateway \
  --vpc-id "$AWS_ID_VPC" \
  --internet-gateway-id "$AWS_ID_IGW"

###############################################################################
# 6) Crear tablas de rutas (pública y privada)
###############################################################################
echo "[4/9] Creando tabla de rutas pública..."
AWS_ID_RTB_PUBLIC=$(aws ec2 create-route-table \
  --vpc-id "$AWS_ID_VPC" \
  --tag-specifications ResourceType=route-table,Tags=[{Key=Name,Value=$AWS_Proyecto-rtb-public}] \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-route \
  --route-table-id "$AWS_ID_RTB_PUBLIC" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$AWS_ID_IGW"

aws ec2 create-route \
  --route-table-id "$AWS_ID_RTB_PUBLIC" \
  --destination-ipv6-cidr-block ::/0 \
  --gateway-id "$AWS_ID_IGW"

aws ec2 associate-route-table \
  --subnet-id "$AWS_ID_SubredPublica" \
  --route-table-id "$AWS_ID_RTB_PUBLIC"

echo "[4.1/9] Creando tabla de rutas privada..."
AWS_ID_RTB_PRIV=$(aws ec2 create-route-table \
  --vpc-id "$AWS_ID_VPC" \
  --tag-specifications ResourceType=route-table,Tags=[{Key=Name,Value=$AWS_Proyecto-rtb-privada}] \
  --query 'RouteTable.RouteTableId' \
  --output text)

# Sin ruta a Internet para la subred privada
aws ec2 associate-route-table \
  --subnet-id "$AWS_ID_SubredPrivada" \
  --route-table-id "$AWS_ID_RTB_PRIV"

###############################################################################
# 7) SG para Kali (acceso SSH desde cualquier IP)
###############################################################################
echo "[5/9] Creando SG para Kali..."
AWS_ID_SG_KALI=$(aws ec2 create-security-group \
  --vpc-id "$AWS_ID_VPC" \
  --group-name "$AWS_Proyecto-kali-sg" \
  --description "$AWS_Proyecto-kali-sg" \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$AWS_ID_SG_KALI" \
  --ip-permissions '[
      {
        "IpProtocol": "tcp",
        "FromPort": 22,
        "ToPort": 22,
        "IpRanges": [
          {
            "CidrIp": "0.0.0.0/0",
            "Description": "Allow SSH IPv4"
          }
        ],
        "Ipv6Ranges": [
          {
            "CidrIpv6": "::/0",
            "Description": "Allow SSH IPv6"
          }
        ]
      }
    ]'

aws ec2 create-tags \
  --resources "$AWS_ID_SG_KALI" \
  --tags Key=Name,Value="$AWS_Proyecto-kali-sg"

###############################################################################
# 8) SG para Metasploitable2 (solo tráfico desde Kali)
###############################################################################
echo "[6/9] Creando SG para Metasploitable2..."
AWS_ID_SG_MS2=$(aws ec2 create-security-group \
  --vpc-id "$AWS_ID_VPC" \
  --group-name "$AWS_Proyecto-ms2-sg" \
  --description "$AWS_Proyecto-ms2-sg" \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$AWS_ID_SG_MS2" \
  --protocol all \
  --source-group "$AWS_ID_SG_KALI"

aws ec2 create-tags \
  --resources "$AWS_ID_SG_MS2" \
  --tags Key=Name,Value="$AWS_Proyecto-ms2-sg"

###############################################################################
# 9) Instancia Kali (pública) + IP elástica
###############################################################################
echo "[7/9] Creando instancia Kali..."
AWS_ID_EC2_KALI=$(aws ec2 run-instances \
  --image-id "$AWS_AMI_KALI_ID" \
  --instance-type t2.micro \
  --key-name "$SSH_KEY_NAME" \
  --security-group-ids "$AWS_ID_SG_KALI" \
  --subnet-id "$AWS_ID_SubredPublica" \
  --ipv6-address-count 1 \
  --private-ip-address "$AWS_IP_KALI" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$AWS_Proyecto-kali},{Key=Email,Value=$EMAIL}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Esperamos ~60s para asignar la IP elástica a Kali..."
sleep 60

echo "Creando y asociando IP elástica a Kali..."
AWS_EIPALLOC_KALI=$(aws ec2 allocate-address --query 'AllocationId' --output text)
aws ec2 associate-address \
  --instance-id "$AWS_ID_EC2_KALI" \
  --allocation-id "$AWS_EIPALLOC_KALI"

###############################################################################
# 10) Instancia Metasploitable2 (privada, sin internet)
###############################################################################
echo "[8/9] Creando instancia Metasploitable2..."
AWS_ID_EC2_MS2=$(aws ec2 run-instances \
  --image-id "$AWS_AMI_MS2_ID" \
  --instance-type t2.micro \
  --key-name "$SSH_KEY_NAME" \
  --security-group-ids "$AWS_ID_SG_MS2" \
  --subnet-id "$AWS_ID_SubredPrivada" \
  --ipv6-address-count 1 \
  --private-ip-address "$AWS_IP_METASPLOITABLE" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$AWS_Proyecto-ms2},{Key=Email,Value=$EMAIL}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

###############################################################################
# 11) Comprobar resultados & Mostrar datos de conexión
###############################################################################
echo "[9/9] Obteniendo información final de conexión..."

# 1) IP pública de Kali
KALI_PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$AWS_ID_EC2_KALI" \
  --query "Reservations[*].Instances[*].PublicIpAddress" \
  --output text)

# 2) IP privada de Metasploitable2
METASPLOITABLE_PRIVATE_IP=$(aws ec2 describe-instances \
  --instance-ids "$AWS_ID_EC2_MS2" \
  --query "Reservations[*].Instances[*].PrivateIpAddress" \
  --output text)

echo "====================================================================="
echo "¡Script completado!"
echo "====================================================================="
echo "Información de conexión:"
echo ""
echo ">>> Kali Linux (acceso desde Internet):"
echo " - Usuario:     $KALI_USER"
echo " - Key SSH:     $SSH_KEY_FILE (asegúrate de tenerlo localmente y permisos 400)"
echo " - IP pública:  $KALI_PUBLIC_IP"
echo " - Puerto SSH:  22"
echo ""
echo "Ejemplo de conexión SSH:"
echo "    ssh -i $SSH_KEY_FILE $KALI_USER@$KALI_PUBLIC_IP -p 22"
echo ""
echo ">>> Metasploitable2 (SIN acceso desde Internet, sólo desde Kali):"
echo " - Usuario:     $METASPLOITABLE_USER"
echo " - Contraseña:  $METASPLOITABLE_PASS"
echo " - IP privada:  $METASPLOITABLE_PRIVATE_IP"
echo ""
echo "Desde Kali podrás hacer algo como:"
echo "    ssh $METASPLOITABLE_USER@$METASPLOITABLE_PRIVATE_IP"
echo "    (Introduce la contraseña $METASPLOITABLE_PASS)"
echo ""
echo "====================================================================="
echo "Recuerda que Metasploitable2 no tiene ruta a Internet."
echo "Sólo es accesible internamente desde Kali."
echo "====================================================================="
