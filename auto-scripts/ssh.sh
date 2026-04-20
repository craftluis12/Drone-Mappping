#!/bin/bash

sed -i 's/\r$//' "$0"
# SSH setup
sudo apt install -y openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh

sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config

sudo sshd -t && sudo systemctl restart ssh
