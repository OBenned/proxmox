#!/bin/bash

# Function to list available templates
list_templates() {
    qm list | grep template | awk '{print $1 " " $2}'
}

# Function to check if any templates are available
templates_available() {
    qm list | grep -q template
}

# Function to get the next available VM ID
get_next_vm_id() {
    for ((i=100; i<=1000; i++)); do
        if ! qm status $i &> /dev/null; then
            echo $i
            return
        fi
    done
}

# Ensure whiptail is installed
if ! command -v whiptail &> /dev/null; then
    echo "whiptail is not installed. Install now? (y/n)"
    read response
    if [[ "$response" == "y" ]]; then
        sudo apt-get update
        sudo apt-get install whiptail
    else
        echo "whiptail is required for this script. Exiting."
        exit 1
    fi
fi

while true; do
    # Prompt for the number of VMs to deploy
    vm_count=$(whiptail --title "VM Deployment" --inputbox "How many machines do you want to deploy?" 10 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$vm_count" ]; then
        exit 1 # Exit if user pressed Cancel or input is empty
    fi

    # Check if there are any templates available
    if templates_available; then
        template_list=($(list_templates))
        template_id=$(whiptail --title "VM Deployment" --menu "Choose a template" 20 60 10 "${template_list[@]}" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            exit 1 # Exit if user pressed Cancel
        fi
    else
        whiptail --title "Error" --msgbox "No templates found. Please create a template before running this script." 10 60
        exit 1
    fi

    # Prompt for VM name prefix
    vm_name_prefix=$(whiptail --title "VM Deployment" --inputbox "Enter the VM name prefix:" 10 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$vm_name_prefix" ]; then
        exit 1 # Exit if user pressed Cancel or input is empty
    fi

    # Optional CPU Configuration
    if whiptail --title "Configure CPU?" --yesno "Would you like to configure CPU cores for the VMs?" 10 60; then
        cpu_cores=$(whiptail --title "CPU Configuration" --inputbox "Enter the number of CPU cores for the VMs:" 10 60 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            continue # Skip if user pressed Cancel
        fi
    fi

    # Optional Memory Configuration
    if whiptail --title "Configure Memory?" --yesno "Would you like to configure memory for the VMs?" 10 60; then
        memory=$(whiptail --title "Memory Configuration" --inputbox "Enter the amount of memory (in MB) for the VMs:" 10 60 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            continue # Skip if user pressed Cancel
        fi
    fi

    # Optional Network Configuration
    if whiptail --title "Configure Network?" --yesno "Would you like to set up network configuration?" 10 60; then
        network_type=$(whiptail --title "Network Configuration" --menu "Choose network configuration" 20 60 10 \
            "dhcp" "DHCP" \
            "static" "Static IP" 3>&1 1>&2 2>&3)
        if [ "$network_type" == "static" ]; then
            start_ip=$(whiptail --title "Static IP Configuration" --inputbox "Enter the starting static IP address with CIDR (e.g., 192.168.1.99/24):" 10 60 3>&1 1>&2 2>&3)
            gateway_ip=$(whiptail --title "Gateway IP" --inputbox "Enter the gateway IP address:" 10 60 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then
                continue # Skip if user pressed Cancel
            fi
            # Extract CIDR
            cidr=$(echo $start_ip | cut -d '/' -f2)
            # Extract base IP
            base_ip=$(echo $start_ip | cut -d '/' -f1)
        fi
        # Ask user to set DNS server after network configuration
        if whiptail --title "Configure DNS?" --yesno "Would you like to set a DNS server for the VMs?" 10 60; then
            nameserver=$(whiptail --title "DNS Configuration" --inputbox "Enter the DNS server address:" 10 60 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then
                continue # Skip if user pressed Cancel
            fi
        fi
    fi

    # Optional Username and Password Configuration
    if whiptail --title "Configure Credentials?" --yesno "Would you like to set a username and password?" 10 60; then
        username=$(whiptail --title "Username Setup" --inputbox "Enter the username for the VMs:" 10 60 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            continue # Skip if user pressed Cancel
        fi
        password=$(whiptail --title "Password Setup" --passwordbox "Enter the password for the VMs:" 10 60 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            continue # Skip if user pressed Cancel
        fi
    fi

    # Deploy VMs
    for ((i=1; i<=vm_count; i++)); do
        vm_id=$(get_next_vm_id)
        vm_name="${vm_name_prefix}-$(printf "%02d" $i)"
        qm clone $template_id $vm_id --name $vm_name --full true

        if [[ $cpu_cores ]]; then
            qm set $vm_id --cores $cpu_cores
        fi
        if [[ $memory ]]; then
            qm set $vm_id --memory $memory
        fi
        if [[ $network_type == "static" ]]; then
            # Calculate new IP address
            IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$base_ip"
            new_ip4=$((ip4 + i - 1)) # Increment the last octet
            new_ip="$ip1.$ip2.$ip3.$new_ip4"
            qm set $vm_id --ipconfig0 "ip=$new_ip/$cidr,gw=$gateway_ip"
        elif [[ $network_type == "dhcp" ]]; then
            qm set $vm_id --ipconfig0 ip=dhcp
        fi
        if [[ $nameserver ]]; then
            qm set $vm_id --nameserver $nameserver
        fi
        if [[ $username ]]; then
            qm set $vm_id --ciuser $username
            qm set $vm_id --cipassword $password
        fi

        # Regenerate cloud-init configuration
        qm cloudinit update $vm_id
    done

    whiptail --title "VM Deployment" --msgbox "VM deployment completed. VMs are not started." 10 60
    exit 0 # Exit after successful completion
done