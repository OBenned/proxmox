#!/bin/bash

# Update package list and install keepalived
sudo apt-get update
sudo apt-get install -y keepalived

# Backup the original keepalived configuration file if it exists
if [ -f /etc/keepalived/keepalived.conf ]; then
    sudo cp /etc/keepalived/keepalived.conf /etc/keepalived/keepalived.conf.bak
fi

# Create a new keepalived configuration
sudo bash -c 'cat > /etc/keepalived/keepalived.conf <<EOF
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass randompassword
    }
    virtual_ipaddress {
        192.168.100.10
    }
}
EOF'

# Enable and start the keepalived service
sudo systemctl enable keepalived
sudo systemctl start keepalived

echo "Keepalived installation and configuration complete."
