#!/bin/bash
set -e

source /opt/ros/jazzy/setup.bash
source ~/drone_ws/install/setup.bash
source ~/ros2_ws/install/setup.bash

echo "Starting MAVROS..."
ros2 launch mavros apm.launch &
PID1=$!
sleep 5

echo "Starting RPLIDAR..."
ros2 launch rplidar_ros rplidar_a1_launch.py &
PID2=$!
sleep 5

echo "Starting static TF..."
ros2 run tf2_ros static_transform_publisher \
  --x 0 --y 0 --z 0 \
  --roll 0 --pitch 0 --yaw 0 \
  --frame-id base_link \
  --child-frame-id laser &
PID3=$!
sleep 2

echo "Starting scan filter..."
ros2 run scan_filter scan_filter --ros-args \
  -p imu_topic:=/mavros/imu/data \
  -p scan_topic:=/scan \
  -p output_scan_topic:=/scan_filtered \
  -p max_roll_deg:=8.0 \
  -p max_pitch_deg:=8.0 \
  -p reopen_roll_deg:=6.0 \
  -p reopen_pitch_deg:=6.0 \
  -p stable_duration_sec:=0.1 \
  -p imu_timeout_sec:=0.3 \
  -p tilt_alpha:=0.4 &
PID4=$!
sleep 3

echo "Starting localization..."
ros2 run robot_localization ekf_node \
  --ros-args \
  --params-file ~/ros2_ws/src/my_robot/config/ekf.yaml &
PID5=$!
sleep 3

echo "Starting Cartographer..."
ros2 run cartographer_ros cartographer_node \
  -configuration_directory /home/$USER/cartographer_config \
  -configuration_basename rplidar.lua \
  --ros-args \
  -r imu:=/mavros/imu/data \
  -r odom:=/odometry/filtered \
  -r scan:=/scan_filtered &
PID6=$!
sleep 3

echo "Starting occupancy grid..."
ros2 run cartographer_ros cartographer_occupancy_grid_node \
  --resolution 0.05 \
  --publish_period_sec 0.2 &
PID7=$!

trap 'kill $PID7 $PID6 $PID5 $PID4 $PID3 $PID2 $PID1' SIGINT SIGTERM
echo "All nodes started. Press Ctrl+C to stop."
wait
