#!/bin/bash
################################################################################
# Script for installing Odoo on Ubuntu 16.04, 18.04, 20.04 and 22.04 (could be used for other version too)
# Author: Yenthe Van Ginneken
# Modified by: [Your Name]
#-------------------------------------------------------------------------------
# This script will install Odoo on your Ubuntu server. It can install multiple Odoo instances
# in one Ubuntu because of the different xmlrpc_ports and separate virtual environments.
#-------------------------------------------------------------------------------

OE_USER="odoo"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
OE_VERSION="16.0"  # or "17.0" for Odoo 17 instance
OE_PORT="8069"  # Set different ports for each instance
OE_CONFIG="${OE_USER}-server"
OE_VENV_DIR="/$OE_USER/venv"  # Directory for virtual environments
OE_VENV_PATH="$OE_VENV_DIR/odoo${OE_VERSION}"  # Path to the virtual environment
INSTALL_WKHTMLTOPDF="True"
INSTALL_POSTGRESQL_FOURTEEN="True"
IS_ENTERPRISE="False"
INSTALL_NGINX="False"
GENERATE_RANDOM_PASSWORD="True"
OE_SUPERADMIN="admin"
LONGPOLLING_PORT="8072"
ENABLE_SSL="True"
ADMIN_EMAIL="odoo@example.com"
WEBSITE_NAME="_"

# Check if the operating system is Ubuntu 22.04
if [[ $(lsb_release -r -s) == "22.04" ]]; then
    WKHTMLTOX_X64="https://packages.ubuntu.com/jammy/wkhtmltopdf"
    WKHTMLTOX_X32="https://packages.ubuntu.com/jammy/wkhtmltopdf"
else
    WKHTMLTOX_X64="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.$(lsb_release -c -s)_amd64.deb"
    WKHTMLTOX_X32="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.$(lsb_release -c -s)_i386.deb"
fi

echo -e "\n---- Update Server ----"
sudo add-apt-repository universe
sudo add-apt-repository "deb http://mirrors.kernel.org/ubuntu/ xenial main"
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install libpq-dev

echo -e "\n---- Install PostgreSQL Server ----"
if [ $INSTALL_POSTGRESQL_FOURTEEN = "True" ]; then
    sudo curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
    sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    sudo apt-get update
    sudo apt-get install postgresql-14
else
    sudo apt-get install postgresql postgresql-server-dev-all -y
fi

echo -e "\n---- Creating the ODOO PostgreSQL User  ----"
sudo su - postgres -c "createuser -s $OE_USER" 2> /dev/null || true

echo -e "\n--- Installing Python 3 + pip3 --"
sudo apt-get install python3 python3-pip -y
sudo apt-get install git python3-cffi build-essential wget python3-dev python3-venv python3-wheel libxslt-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools node-less libpng-dev libjpeg-dev gdebi -y

echo -e "\n---- Create Virtual Environment Directory ----"
sudo mkdir -p $OE_VENV_DIR
sudo chown $OE_USER:$OE_USER $OE_VENV_DIR

echo -e "\n---- Create and Activate Virtual Environment ----"
sudo su - $OE_USER -c "python3 -m venv $OE_VENV_PATH"
source $OE_VENV_PATH/bin/activate

echo -e "\n---- Install python packages/requirements ----"
pip3 install -r https://github.com/odoo/odoo/raw/${OE_VERSION}/requirements.txt

echo -e "\n---- Installing nodeJS NPM and rtlcss for LTR support ----"
sudo apt-get install nodejs npm -y
sudo npm install -g rtlcss

if [ $INSTALL_WKHTMLTOPDF = "True" ]; then
    echo -e "\n---- Install wkhtml and place shortcuts on correct place for ODOO ----"
    if [ "`getconf LONG_BIT`" == "64" ]; then
        _url=$WKHTMLTOX_X64
    else
        _url=$WKHTMLTOX_X32
    fi
    sudo wget $_url

    if [[ $(lsb_release -r -s) == "22.04" ]]; then
        sudo apt install wkhtmltopdf -y
    else
        sudo gdebi --n `basename $_url`
    fi

    sudo ln -s /usr/local/bin/wkhtmltopdf /usr/bin
    sudo ln -s /usr/local/bin/wkhtmltoimage /usr/bin
else
    echo "Wkhtmltopdf isn't installed due to the choice of the user!"
fi

echo -e "\n---- Create ODOO system user ----"
sudo adduser --system --quiet --shell=/bin/bash --home=$OE_HOME --gecos 'ODOO' --group $OE_USER
sudo adduser $OE_USER sudo

echo -e "\n---- Create Log directory ----"
sudo mkdir /var/log/$OE_USER
sudo chown $OE_USER:$OE_USER /var/log/$OE_USER

echo -e "\n==== Installing ODOO Server ===="
sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/odoo $OE_HOME_EXT/

if [ $IS_ENTERPRISE = "True" ]; then
    pip3 install psycopg2-binary pdfminer.six
    sudo ln -s /usr/bin/nodejs /usr/bin/node
    sudo su $OE_USER -c "mkdir $OE_HOME/enterprise"
    sudo su $OE_USER -c "mkdir $OE_HOME/enterprise/addons"
    GITHUB_RESPONSE=$(sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/enterprise "$OE_HOME/enterprise/addons" 2>&1)
    while [[ $GITHUB_RESPONSE == *"Authentication"* ]]; do
        echo "Authentication with Github has failed! Please try again."
        GITHUB_RESPONSE=$(sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/enterprise "$OE_HOME/enterprise/addons" 2>&1)
    done
    echo -e "\n---- Added Enterprise code under $OE_HOME/enterprise/addons ----"
    echo -e "\n---- Installing Enterprise specific libraries ----"
    pip3 install num2words ofxparse dbfread ebaysdk firebase_admin pyOpenSSL
    sudo npm install -g less
    sudo npm install -g less-plugin-clean-css
fi

echo -e "\n---- Create custom module directory ----"
sudo su $OE_USER -c "mkdir $OE_HOME/custom"
sudo su $OE_USER -c "mkdir $OE_HOME/custom/addons"

echo -e "\n---- Setting permissions on home folder ----"
sudo chown -R $OE_USER:$OE_USER $OE_HOME/*

echo -e "* Create server config file"
sudo touch /etc/${OE_CONFIG}.conf
sudo su root -c "printf '[options] \n; This is the password that allows database operations:\n' >> /etc/${OE_CONFIG}.conf"
if [ $GENERATE_RANDOM_PASSWORD = "True" ]; then
    OE_SUPERADMIN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
fi
sudo su root -c "printf 'admin_passwd = ${OE_SUPERADMIN}\n' >> /etc/${OE_CONFIG}.conf"
if [ $OE_VERSION > "11.0" ]; then
    sudo su root -c "printf 'http_port = ${OE_PORT}\n' >> /etc/${OE_CONFIG}.conf"
else
    sudo su root -c "printf 'xmlrpc_port = ${OE_PORT}\n' >> /etc/${OE_CONFIG}.conf"
fi
sudo su root -c "printf 'logfile = /var/log/${OE_USER}/${OE_CONFIG}.log\n' >> /etc/${OE_CONFIG}.conf"
if [ $IS_ENTERPRISE = "True" ]; then
    sudo su root -c "printf 'addons_path=${OE_HOME}/enterprise/addons,
