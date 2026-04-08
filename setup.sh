#!/bin/bash
set -e

echo "===== ROS 2 Jazzy Drone Mapping Setup ====="

# -------------------------------
# Step 1: System update + prereqs
# -------------------------------
sudo apt update
sudo apt install -y \
    curl \
    gnupg \
    lsb-release \
    python3-rosdep \
    python3-colcon-common-extensions \
    software-properties-common

# -------------------------------
# Step 2: Add ROS 2 Jazzy source
# -------------------------------
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | \
sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null

sudo apt update

# -------------------------------
# Step 3: Install ROS 2 Jazzy
# -------------------------------
sudo apt install -y ros-jazzy-ros-base

# -------------------------------
# Step 4: rosdep init/update
# -------------------------------
sudo rosdep init || true
rosdep update

# -------------------------------
# Step 5: Add environment to bashrc
# -------------------------------
grep -qxF 'source /opt/ros/jazzy/setup.bash' ~/.bashrc || echo 'source /opt/ros/jazzy/setup.bash' >> ~/.bashrc
grep -qxF 'export ROS_DOMAIN_ID=7' ~/.bashrc || echo 'export ROS_DOMAIN_ID=7' >> ~/.bashrc
grep -qxF 'export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET' ~/.bashrc || echo 'export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET' >> ~/.bashrc

source /opt/ros/jazzy/setup.bash

# -------------------------------
# Step 6: Add user to dialout
# -------------------------------
sudo usermod -a -G dialout "$USER"

# -------------------------------
# Step 7: Install mapping packages
# -------------------------------
sudo apt install -y \
    ros-jazzy-rplidar-ros \
    ros-jazzy-slam-toolbox \
    ros-jazzy-cartographer \
    ros-jazzy-cartographer-ros \
    ros-jazzy-mavros \
    ros-jazzy-mavros-extras \
    ros-jazzy-robot-localization \
    ros-jazzy-nav2-map-server \
    geographiclib-tools

# GeographicLib dataset for MAVROS
if [ -f /opt/ros/jazzy/lib/mavros/install_geographiclib_datasets.sh ]; then
    sudo /opt/ros/jazzy/lib/mavros/install_geographiclib_datasets.sh
elif [ -f /opt/ros/jazzy/lib/mavros/install_geographiclib_dataset.sh ]; then
    sudo /opt/ros/jazzy/lib/mavros/install_geographiclib_dataset.sh
else
    echo "GeographicLib install script not found, skipping..."
fi

# -------------------------------
# Step 8: Create folders
# -------------------------------
mkdir -p ~/cartographer_config
mkdir -p ~/ros2_ws/src/my_robot/config
mkdir -p ~/drone_ws/src

# -------------------------------
# Step 9: Build empty workspaces
# -------------------------------
cd ~/ros2_ws
colcon build || true

cd ~/drone_ws
colcon build || true

# -------------------------------
# Step 10: Create scan_filter pkg
# -------------------------------
cd ~/drone_ws/src
if [ ! -d scan_filter ]; then
    ros2 pkg create --build-type ament_python scan_filter
fi

mkdir -p ~/drone_ws/src/scan_filter/scan_filter
touch ~/drone_ws/src/scan_filter/scan_filter/__init__.py

# -------------------------------
# Step 11: SSH setup
# -------------------------------
sudo apt install -y openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh

sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config

sudo sshd -t && sudo systemctl restart ssh

# -------------------------------
# Step 12: Final message
# -------------------------------
echo
echo "===== Setup Complete ====="
echo "Now do these next:"
echo "1. Put rplidar.lua into ~/cartographer_config"
echo "2. Put ekf.yaml into ~/ros2_ws/src/my_robot/config"
echo "3. Put scan_stability_filter.py into ~/drone_ws/src/scan_filter/scan_filter"
echo "4. Edit ~/drone_ws/src/scan_filter/setup.py to add the console_scripts entry"
echo "5. Rebuild:"
echo "   cd ~/drone_ws && colcon build"
echo "   cd ~/ros2_ws && colcon build"
echo
echo "Then either reboot or run:"
echo "source ~/.bashrc"