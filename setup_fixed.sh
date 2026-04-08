#!/bin/bash
set -e

echo "===== ROS 2 Jazzy Drone Mapping Setup ====="

# -------------------------------
# Step 0: Installing Jazzy
# -------------------------------
locale

sudo apt update
sudo apt install -y locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8

locale

sudo apt install -y software-properties-common
sudo add-apt-repository -y universe

sudo apt update
sudo apt install -y curl

export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F'"' '{print $4}')
curl -L -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb"
sudo dpkg -i /tmp/ros2-apt-source.deb

sudo apt update
sudo apt upgrade -y
sudo apt install -y ros-jazzy-ros-base

# -------------------------------
# Installing Prerequisites
# -------------------------------
sudo apt update
sudo apt install -y curl gnupg lsb-release python3-rosdep python3-colcon-common-extensions
sudo rosdep init || true
rosdep update

# -------------------------------
# Adding Sources
# -------------------------------
grep -qxF 'source /opt/ros/jazzy/setup.bash' ~/.bashrc || echo 'source /opt/ros/jazzy/setup.bash' >> ~/.bashrc
grep -qxF 'export ROS_DOMAIN_ID=7' ~/.bashrc || echo 'export ROS_DOMAIN_ID=7' >> ~/.bashrc
grep -qxF 'export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET' ~/.bashrc || echo 'export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET' >> ~/.bashrc

source /opt/ros/jazzy/setup.bash

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

if [ -f /opt/ros/jazzy/lib/mavros/install_geographiclib_datasets.sh ]; then
  sudo /opt/ros/jazzy/lib/mavros/install_geographiclib_datasets.sh
elif [ -f /opt/ros/jazzy/lib/mavros/install_geographiclib_dataset.sh ]; then
  sudo /opt/ros/jazzy/lib/mavros/install_geographiclib_dataset.sh
else
  echo "GeographicLib install script not found, skipping..."
fi

# -------------------------------
# SSH setup
# -------------------------------
sudo apt install -y openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh

sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config

sudo sshd -t && sudo systemctl restart ssh

# -------------------------------
# Create folders
# -------------------------------
mkdir -p ~/cartographer_config
mkdir -p ~/ros2_ws/src/my_robot/config
mkdir -p ~/drone_ws/src

# -------------------------------
# Cartographer
# -------------------------------
cat > ~/cartographer_config/rplidar.lua <<'EOF'
include "map_builder.lua"
include "trajectory_builder.lua"

options = {
  map_builder = MAP_BUILDER,
  trajectory_builder = TRAJECTORY_BUILDER,
  map_frame = "map",
  tracking_frame = "base_link",
  published_frame = "odom",
  odom_frame = "odom",
  provide_odom_frame = false,
  publish_frame_projected_to_2d = true,
  use_odometry = true,
  use_nav_sat = false,
  use_landmarks = false,
  num_laser_scans = 1,
  num_multi_echo_laser_scans = 0,
  num_subdivisions_per_laser_scan = 1,
  num_point_clouds = 0,
  lookup_transform_timeout_sec = 0.2,
  submap_publish_period_sec = 0.08,
  pose_publish_period_sec = 0.01,
  trajectory_publish_period_sec = 0.02,
  rangefinder_sampling_ratio = 1.0,
  odometry_sampling_ratio = 1.0,
  fixed_frame_pose_sampling_ratio = 1.0,
  imu_sampling_ratio = 1.0,
  landmarks_sampling_ratio = 1.0,
}

MAP_BUILDER.use_trajectory_builder_2d = true
TRAJECTORY_BUILDER_2D.use_imu_data = true
TRAJECTORY_BUILDER_2D.min_range = 0.25
TRAJECTORY_BUILDER_2D.max_range = 7.0
TRAJECTORY_BUILDER_2D.missing_data_ray_length = 8.0
TRAJECTORY_BUILDER_2D.num_accumulated_range_data = 1
TRAJECTORY_BUILDER_2D.ceres_scan_matcher.translation_weight = 20
TRAJECTORY_BUILDER_2D.ceres_scan_matcher.rotation_weight = 100
TRAJECTORY_BUILDER_2D.motion_filter.max_angle_radians = 0.08
TRAJECTORY_BUILDER_2D.motion_filter.max_distance_meters = 0.04
TRAJECTORY_BUILDER_2D.submaps.num_range_data = 20
TRAJECTORY_BUILDER_2D.use_online_correlative_scan_matching = true
POSE_GRAPH.optimize_every_n_nodes = 30

return options
EOF

# -------------------------------
# EKF config
# -------------------------------
cat > ~/ros2_ws/src/my_robot/config/ekf.yaml <<'EOF'
ekf_filter_node:
  ros__parameters:
    frequency: 30.0
    sensor_timeout: 0.1
    two_d_mode: true
    publish_tf: true
    map_frame: map
    odom_frame: odom
    base_link_frame: base_link
    world_frame: odom

    odom0: /mavros/local_position/odom
    odom0_config: [true, true, false,
                   false, false, true,
                   true, true, false,
                   false, false, true,
                   false, false, false]
    odom0_differential: false
    odom0_relative: false
    odom0_queue_size: 10

    imu0: /mavros/imu/data
    imu0_config: [false, false, false,
                  false, false, true,
                  false, false, false,
                  false, false, true,
                  false, false, false]
    imu0_differential: false
    imu0_relative: false
    imu0_queue_size: 20
    imu0_remove_gravitational_acceleration: true
EOF

# -------------------------------
# Scan Drop-Filtered package
# -------------------------------
cd ~/drone_ws/src

if [ ! -d scan_filter ]; then
  ros2 pkg create --build-type ament_python scan_filter
fi

mkdir -p ~/drone_ws/src/scan_filter/scan_filter
touch ~/drone_ws/src/scan_filter/scan_filter/__init__.py

cat > ~/drone_ws/src/scan_filter/scan_filter/scan_stability_filter.py <<'EOF'
#!/usr/bin/env python3
import math
from typing import Optional

import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import Imu, LaserScan


class ScanStabilityFilter(Node):
    def __init__(self) -> None:
        super().__init__('scan_stability_filter')

        self.declare_parameter('scan_topic', '/scan')
        self.declare_parameter('imu_topic', '/mavros/imu/data')
        self.declare_parameter('output_scan_topic', '/scan_filtered')

        self.declare_parameter('max_roll_deg', 8.0)
        self.declare_parameter('max_pitch_deg', 8.0)

        self.declare_parameter('reopen_roll_deg', 6.0)
        self.declare_parameter('reopen_pitch_deg', 6.0)

        self.declare_parameter('stable_duration_sec', 0.1)
        self.declare_parameter('imu_timeout_sec', 0.30)
        self.declare_parameter('tilt_alpha', 0.4)

        self.declare_parameter('log_rejections', True)
        self.declare_parameter('log_interval_sec', 1.0)

        self.scan_topic = self.get_parameter('scan_topic').value
        self.imu_topic = self.get_parameter('imu_topic').value
        self.output_scan_topic = self.get_parameter('output_scan_topic').value

        self.max_roll_deg = float(self.get_parameter('max_roll_deg').value)
        self.max_pitch_deg = float(self.get_parameter('max_pitch_deg').value)
        self.reopen_roll_deg = float(self.get_parameter('reopen_roll_deg').value)
        self.reopen_pitch_deg = float(self.get_parameter('reopen_pitch_deg').value)
        self.stable_duration_sec = float(self.get_parameter('stable_duration_sec').value)
        self.imu_timeout_sec = float(self.get_parameter('imu_timeout_sec').value)
        self.tilt_alpha = float(self.get_parameter('tilt_alpha').value)
        self.log_rejections = bool(self.get_parameter('log_rejections').value)
        self.log_interval_sec = float(self.get_parameter('log_interval_sec').value)

        self.raw_roll_deg: Optional[float] = None
        self.raw_pitch_deg: Optional[float] = None
        self.roll_deg: Optional[float] = None
        self.pitch_deg: Optional[float] = None
        self.last_imu_time_sec: Optional[float] = None
        self.stable_since_sec: Optional[float] = None
        self.gate_open = False

        self.passed_scans = 0
        self.dropped_scans = 0
        self.last_log_time_sec = 0.0

        self.imu_sub = self.create_subscription(
            Imu,
            self.imu_topic,
            self.imu_callback,
            qos_profile_sensor_data
        )

        self.scan_sub = self.create_subscription(
            LaserScan,
            self.scan_topic,
            self.scan_callback,
            qos_profile_sensor_data
        )

        self.scan_pub = self.create_publisher(
            LaserScan,
            self.output_scan_topic,
            qos_profile_sensor_data
        )

        self.get_logger().info(
            f'Started scan_stability_filter\n'
            f' imu_topic={self.imu_topic}\n'
            f' scan_topic={self.scan_topic}\n'
            f' output_scan_topic={self.output_scan_topic}\n'
            f' max_roll_deg={self.max_roll_deg}\n'
            f' max_pitch_deg={self.max_pitch_deg}\n'
            f' reopen_roll_deg={self.reopen_roll_deg}\n'
            f' reopen_pitch_deg={self.reopen_pitch_deg}\n'
            f' stable_duration_sec={self.stable_duration_sec}\n'
            f' imu_timeout_sec={self.imu_timeout_sec}\n'
            f' tilt_alpha={self.tilt_alpha}'
        )

    def imu_callback(self, msg: Imu) -> None:
        q = msg.orientation

        if q.x == 0.0 and q.y == 0.0 and q.z == 0.0 and q.w == 0.0:
            return

        roll_rad, pitch_rad, _ = self.quaternion_to_euler(q.x, q.y, q.z, q.w)
        raw_roll_deg = math.degrees(roll_rad)
        raw_pitch_deg = math.degrees(pitch_rad)

        self.raw_roll_deg = raw_roll_deg
        self.raw_pitch_deg = raw_pitch_deg

        if self.roll_deg is None or self.pitch_deg is None:
            self.roll_deg = raw_roll_deg
            self.pitch_deg = raw_pitch_deg
        else:
            a = self.tilt_alpha
            self.roll_deg = a * raw_roll_deg + (1.0 - a) * self.roll_deg
            self.pitch_deg = a * raw_pitch_deg + (1.0 - a) * self.pitch_deg

        self.last_imu_time_sec = self.now_sec()
        self.update_gate_state()

    def scan_callback(self, msg: LaserScan) -> None:
        if not self.imu_is_fresh():
            self.dropped_scans += 1
            self.gate_open = False
            self.stable_since_sec = None
            self.maybe_log('Dropping scan: IMU data missing or stale')
            return

        self.update_gate_state()

        if not self.gate_open:
            self.dropped_scans += 1
            self.maybe_log(
                f'Dropping scan: roll={self.roll_deg:.2f} deg, '
                f'pitch={self.pitch_deg:.2f} deg'
            )
            return

        self.scan_pub.publish(msg)
        self.passed_scans += 1

    def imu_is_fresh(self) -> bool:
        if self.last_imu_time_sec is None:
            return False
        return (self.now_sec() - self.last_imu_time_sec) <= self.imu_timeout_sec

    def update_gate_state(self) -> None:
        if self.roll_deg is None or self.pitch_deg is None:
            self.gate_open = False
            self.stable_since_sec = None
            return

        abs_roll = abs(self.roll_deg)
        abs_pitch = abs(self.pitch_deg)
        now = self.now_sec()

        if not self.gate_open:
            level_enough = (
                abs_roll <= self.reopen_roll_deg and
                abs_pitch <= self.reopen_pitch_deg
            )

            if level_enough:
                if self.stable_since_sec is None:
                    self.stable_since_sec = now
                elif (now - self.stable_since_sec) >= self.stable_duration_sec:
                    self.gate_open = True
            else:
                self.stable_since_sec = None
            return

        too_tilted = (
            abs_roll > self.max_roll_deg or
            abs_pitch > self.max_pitch_deg
        )

        if too_tilted:
            self.gate_open = False
            self.stable_since_sec = None

    def maybe_log(self, message: str) -> None:
        if not self.log_rejections:
            return

        now = self.now_sec()
        if (now - self.last_log_time_sec) >= self.log_interval_sec:
            self.get_logger().warn(
                f'{message} | passed={self.passed_scans}, dropped={self.dropped_scans}'
            )
            self.last_log_time_sec = now

    def now_sec(self) -> float:
        return self.get_clock().now().nanoseconds / 1e9

    @staticmethod
    def quaternion_to_euler(x: float, y: float, z: float, w: float):
        sinr_cosp = 2.0 * (w * x + y * z)
        cosr_cosp = 1.0 - 2.0 * (x * x + y * y)
        roll = math.atan2(sinr_cosp, cosr_cosp)

        sinp = 2.0 * (w * y - z * x)
        if abs(sinp) >= 1.0:
            pitch = math.copysign(math.pi / 2.0, sinp)
        else:
            pitch = math.asin(sinp)

        siny_cosp = 2.0 * (w * z + x * y)
        cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
        yaw = math.atan2(siny_cosp, cosy_cosp)

        return roll, pitch, yaw


def main(args=None) -> None:
    rclpy.init(args=args)
    node = ScanStabilityFilter()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.get_logger().info(
            f'Shutting down. Final counts: passed={node.passed_scans}, dropped={node.dropped_scans}'
        )
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
EOF

chmod +x ~/drone_ws/src/scan_filter/scan_filter/scan_stability_filter.py

cat > ~/drone_ws/src/scan_filter/setup.py <<'EOF'
from setuptools import find_packages, setup

package_name = 'scan_filter'

setup(
    name=package_name,
    version='0.0.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='ubuntu',
    maintainer_email='ubuntu@todo.todo',
    description='Scan stability filter for tilted drone lidar scans',
    license='TODO',
    tests_require=['pytest'],
    entry_points={
        'console_scripts': [
            'scan_filter = scan_filter.scan_stability_filter:main',
        ],
    },
)
EOF

mkdir -p ~/drone_ws/src/scan_filter/resource
touch ~/drone_ws/src/scan_filter/resource/scan_filter

# -------------------------------
# Permissions
# -------------------------------
sudo usermod -a -G dialout "$USER"

# -------------------------------
# Build workspaces
# -------------------------------
cd ~/ros2_ws
source /opt/ros/jazzy/setup.bash
colcon build || true

cd ~/drone_ws
source /opt/ros/jazzy/setup.bash
colcon build || true

echo
echo "===== Setup Complete ====="
echo "Open a new terminal or run:"
echo "  source ~/.bashrc"
echo "  source ~/ros2_ws/install/setup.bash"
echo "  source ~/drone_ws/install/setup.bash"
