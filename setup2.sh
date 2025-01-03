#!/bin/bash

# Actualizar el sistema
sudo apt update -y
sudo apt upgrade -y

# Instalar Nmap
sudo apt install nmap -y


# Crear un archivo de prueba
echo "Instalación completada en $(date)" > /home/ubuntu/instalacion_completada.txt
