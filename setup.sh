#!/bin/bash
set -e

echo "===== ROS 2 Jazzy Drone Mapping Setup ====="




# -------------------------------
# Step 0: Installing Jazzy
# -------------------------------
locale  # check for UTF-8

sudo apt update && sudo apt install locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8

locale  # verify settings

sudo apt install software-properties-common
sudo add-apt-repository universe

sudo apt update && sudo apt install curl -y
export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F'"' '{print $4}')
curl -L -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb"
sudo dpkg -i /tmp/ros2-apt-source.deb

sudo apt update
sudo apt upgrade

sudo apt install ros-jazzy-ros-base
# DONE----------------------------------

# -------------------------------
# Installing Prerequisites
# -------------------------------
sudo apt update
sudo apt install -y curl gnupg lsb-release python3-rosdep python3-colcon-common-extensions
sudo rosdep init || true
rosdep update
# DONE----------------------------------

# -------------------------------
# Adding Sources
# -------------------------------
echo "source /opt/ros/jazzy/setup.bash" >> ~/.bashrc
echo "export ROS_DOMAIN_ID=7" >> ~/.bashrc
echo "export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET" >> ~/.bashrc
source ~/.bashrc
# DONE----------------------------------

# -------------------------------
# Tools and Packages
# -------------------------------
sudo apt update
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
sudo apt update
sudo /opt/ros/jazzy/lib/mavros/install_geographiclib_datasets.sh
# DONE----------------------------------


# -------------------------------
# Step 3: Install ROS 2 Jazzy
# -------------------------------
mkdir -p ~/cartographer_config
cd ~/cartographer_config


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
