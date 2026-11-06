# MMK2 Supermarket Sorting Demo

English | [简体中文](README.zh-CN.md)

A ROS 2 supermarket simulation for MMK2 mobile manipulation, using MuJoCo physics, 3D Gaussian Splatting rendering, RGB-D cameras and lidar. The included baseline navigates to a shelf, detects and grasps a cola can, lifts it, and retreats while retaining the grasp. It does not perform delivery-table placement. Randomized multi-item delivery requires an additional control and obstacle-avoidance policy; the server has no referee or scoring module.

## Contents

- [Requirements](#requirements)
- [Download](#download)
- [Fixed grasp demo](#fixed-grasp-demo)
- [Randomized simulation](#randomized-simulation)
- [ROS 2 interfaces](#ros-2-interfaces)
- [Configuration](#configuration)
- [Source build and offline deployment](#source-build-and-offline-deployment)
- [Checks and troubleshooting](#checks-and-troubleshooting)
- [Files and licenses](#files-and-licenses)

## Requirements

- Ubuntu 22.04, Docker, NVIDIA Container Toolkit and NVIDIA driver ≥ 570.26.
- NVIDIA Turing or newer GPU (RTX 20/30/40/50 series). The current CUDA wheels do not support GPU inference on Pascal/GTX 10 or Volta. A CPU detector fallback does not make the 3DGS server CPU-compatible.
- Runtime: ROS 2 Humble, CUDA 12.8, PyTorch 2.7.1+cu128, torchvision 0.22.1+cu128.
- X11 display for the windowed demo, or EGL for headless rendering. Server/client compressed image downloads total about 17 GB; allow additional disk space for extraction and Docker build/cache.

## Download

Clone the code and download the scene resources and detector weights (approximately 248 MB compressed). The script verifies SHA-256 before extraction. No Git LFS setup is required.

```bash
git clone https://github.com/DISCOVER-Robotics/MMK2-Supermarket-Sorting-Demo.git
cd MMK2-Supermarket-Sorting-Demo
bash scripts/download_assets.sh
```

Download both runtime images and give them local names:

```bash
registry=crpi-1pzq998p9m7w0auy.cn-hangzhou.personal.cr.aliyuncs.com/challengecup/supermarket_sorting_final
docker pull "$registry:server"
docker pull "$registry:client"
docker tag "$registry:server" supermarket_sorting:server
docker tag "$registry:client" supermarket_sorting:client
```

Verify GPU access before starting the server. This command must show the GPU:

```bash
docker run --rm --gpus all --entrypoint nvidia-smi supermarket_sorting:server
```

## Fixed grasp demo

### 1. Start the simulation server

Run from this repository root in terminal 1:

```bash
xhost +local:docker
docker volume create supermarket_sorting_cache
bash scripts/start_server.sh fixed
```

The launcher mounts this checkout into the container read-only, uses the fixed `product_032` target and disables product/obstacle randomization. Keep the server running. First-time 3DGS CUDA compilation can take several minutes; wait for initialization and camera publication before proceeding.

### 2. Start the client and baseline

In terminal 2, change to the same repository root, then run:

```bash
docker run --rm -dit --gpus all --network host --ipc host \
  --name supermarket_sorting_client \
  -e ROS_DOMAIN_ID=99 -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -v "$PWD/baseline":/workspace/baseline:ro \
  supermarket_sorting:client

docker exec -it supermarket_sorting_client \
  bash -lc 'cd /workspace/baseline && bash scripts/run_baseline.sh'
```

The included `baseline/` contains the controller, detector, kinematics model and downloaded weights. No additional baseline clone is needed. Server and client must use the same ROS domain (99 here).

The sequence is shelf approach → visual localization → grasp → lift → retreat. The controller prints `retreat done; task-one baseline complete with grasp retained` at the end and remains active in its done phase. Confirm the physical grasp and retreat in the simulator; the log alone is not a success score.

### 3. Inspect and stop

In terminal 3, inspect the current task:

```bash
docker exec supermarket_sorting_client bash -lc \
  'source /opt/ros/humble/setup.bash && ros2 topic echo --once --qos-durability transient_local /supermarket_sorting/task'
```

Press Ctrl+C in terminal 2 to stop the baseline, then stop the containers:

```bash
docker stop supermarket_sorting_client supermarket_sorting_server
xhost -local:docker
```

For headless operation, replace the server launch with the following. RGB-D rendering remains enabled; a GPU is still required.

```bash
SUPERMARKET_HEADLESS=1 bash scripts/start_server.sh fixed
```

## Randomized simulation

Stop the fixed server before starting another server with the same container name:

```bash
bash scripts/start_server.sh random
```

This launches 45 randomized products and five corridor obstacles. Layouts use a swept-base clearance plus 0.05 m margin and a 0.05 m A* grid; connected routes must add at least 0.30 m detour. Obstacles occupy five longitudinal bands with at least 0.40 m lateral/longitudinal separation between adjacent bands. Startup logs show generation attempts, path length and detour.

Set `SUPERMARKET_SEED=42 bash scripts/start_server.sh random` to choose a layout seed. Anonymous target IDs and run prefixes change each server launch even with the same layout seed. Task JSON includes `schema_version`, `run_prefix`, `count` and `targets` containing `{id, kind}` entries. IDs do not encode shelf positions. Filter targets by product kind or neutral IDs through `SUPERMARKET_TASKS` when adapting the launcher.

The fixed baseline is for the fixed grasp scene. Its waypoints do not solve randomized navigation or delivery. Implement planning and obstacle avoidance using `/slamware_ros_sdk_server_node/scan` and extend manipulation control for multi-item placement.

## ROS 2 interfaces

### Server publications

| Topic | Type | Description |
| --- | --- | --- |
| `/slamware_ros_sdk_server_node/odom` | `nav_msgs/msg/Odometry` | Base pose and velocity |
| `/tf` | `tf2_msgs/msg/TFMessage` | Dynamic transforms, including odom → base_link |
| `/slamware_ros_sdk_server_node/scan` | `sensor_msgs/msg/LaserScan` | 360-point lidar, 12 Hz, frame laser |
| `/joint_states` | `sensor_msgs/msg/JointState` | Spine, head, arms and grippers |
| `/head_camera/color/image_raw` | `sensor_msgs/msg/Image` | Head RGB, 640 × 480 |
| `/head_camera/color/camera_info` | `sensor_msgs/msg/CameraInfo` | Head RGB intrinsics |
| `/head_camera/aligned_depth_to_color/image_raw` | `sensor_msgs/msg/Image` | Head depth, mono16, millimetres |
| `/head_camera/aligned_depth_to_color/camera_info` | `sensor_msgs/msg/CameraInfo` | Head depth intrinsics |
| `/left_camera/color/image_raw`, `/right_camera/color/image_raw` | `sensor_msgs/msg/Image` | Wrist RGB |
| `/left_camera/color/camera_info`, `/right_camera/color/camera_info` | `sensor_msgs/msg/CameraInfo` | Wrist intrinsics |
| `/supermarket_sorting/task` | `std_msgs/msg/String` | Reliable, transient-local JSON task list |

### Server subscriptions

| Topic | Type | Format |
| --- | --- | --- |
| `/cmd_vel` | `geometry_msgs/msg/Twist` | linear.x: forward velocity; angular.z: yaw rate |
| `/spine_forward_position_controller/commands` | `std_msgs/msg/Float64MultiArray` | [slide_joint] |
| `/head_forward_position_controller/commands` | `std_msgs/msg/Float64MultiArray` | [head_yaw_joint, head_pitch_joint] |
| `/left_arm_forward_position_controller/commands`, `/right_arm_forward_position_controller/commands` | `std_msgs/msg/Float64MultiArray` | [joint1, joint2, joint3, joint4, joint5, joint6, gripper] |

### Perception publications

| Topic | Type | Description |
| --- | --- | --- |
| `/kele/detections` | `vision_msgs/msg/Detection3DArray` | Cola detections in world coordinates |
| `/kele/result_image` | `sensor_msgs/msg/Image` | Detector visualization |
| `/aruco/<camera>/ids` | `std_msgs/msg/Int32MultiArray` | Sorted marker IDs |
| `/aruco/<camera>/poses` | `geometry_msgs/msg/PoseArray` | Marker poses in camera coordinates |
| `/aruco/<camera>/detections` | `std_msgs/msg/String` | IDs, translations and quaternions as JSON |
| `/aruco/<camera>/result_image` | `sensor_msgs/msg/Image` | Marker visualization |

`<camera>` is `head`, `left` or `right`. Marker IDs and poses share array order; the ArUco node also publishes `aruco_<camera>_<id>` TF frames. ArUco detection is a separate optional node, not part of the default baseline launch.

Joint state order: spine slide, head yaw/pitch, left arm joints 1–6 and gripper, right arm joints 1–6 and gripper. Gripper command `1.0` opens; the cola baseline uses `0.08` to close.

## Configuration

| Parameter | Default / example | Meaning |
| --- | --- | --- |
| `ROS_DOMAIN_ID` | `99` | Same on server and client |
| `RMW_IMPLEMENTATION` | `rmw_cyclonedds_cpp` | ROS 2 middleware |
| `MUJOCO_GL` | `glfw` / `egl` | Windowed / headless renderer |
| `SUPERMARKET_HEADLESS` | `0` | Set to 1 for headless mode |
| `SUPERMARKET_ENABLE_RENDER` | `1` | Publish camera data |
| `SUPERMARKET_ENABLE_LIDAR` | `1` | Publish laser scan |
| `SUPERMARKET_USE_GS` | `1` | Enable 3DGS rendering |
| `SUPERMARKET_GS_SEQUENTIAL` | `1` | Render cameras sequentially to reduce peak GPU memory |
| `SUPERMARKET_FIXED_BASELINE` | `1` (fixed) | Fixed grasp scene; incompatible with randomized products |
| `SUPERMARKET_RANDOMIZE` | `0` fixed, `1` random | Randomize 45 product positions |
| `SUPERMARKET_RANDOMIZE_OBSTACLES` | `0` fixed, `1` random | Randomize 5 corridor obstacles |
| `SUPERMARKET_SEED` | `11` | Layout seed, optional in server code |
| `SUPERMARKET_OBSTACLE_SEED` | Optional | Separate obstacle seed; otherwise derived from layout seed |
| `SUPERMARKET_TASKS` | `product_032` / `all` | Comma-separated product kinds or neutral IDs |
| `SUPERMARKET_DETECTOR_DEVICE` | `auto` | Baseline YOLO device; can be cpu |

`start_server.sh` forwards `ROS_DOMAIN_ID`, `SUPERMARKET_HEADLESS` and the random layout seed from the host. It sets the other server options explicitly; edit its Docker environment flags to change them. Set baseline detector options on the client container with `-e SUPERMARKET_DETECTOR_DEVICE=cpu` or `-e SUPERMARKET_BASELINE_WEIGHTS=/path/in/container/weights.pt` before the image name.

## Source build and offline deployment

Download resources first, then build from the repository root:

```bash
docker build -t supermarket_sorting:server .
docker build -t supermarket_sorting:client docker/client
```

For offline use, copy this repository **including the extracted resources and baseline weights**, and transfer both Docker images with `docker save` / `docker load`. The optional [image export script](offline/export_images.sh) exports the pre-pull image names by default; use `SERVER_IMAGE=supermarket_sorting:server CLIENT_IMAGE=supermarket_sorting:client bash offline/export_images.sh /path/to/output` for the local tags. The host still needs the NVIDIA driver and Container Toolkit. Image archives alone do not include this checkout's mounted baseline and downloaded resources.

## Checks and troubleshooting

Run the six scene/layout unit tests:

```bash
docker run --rm --network none \
  -v "$PWD":/workspace/supermarket_sorting_task:ro \
  supermarket_sorting:server bash -lc \
  'cd /workspace/supermarket_sorting_task && source /opt/ros/humble/setup.bash && export PYTHONPATH="$PWD:${PYTHONPATH:-}" && python3 -m unittest discover -s examples/supermarket_sorting -p "test_*.py" -v'
```

Scene inspection has passed these six tests and compiled both fixed/random MuJoCo scenes with all 73 3DGS resource bindings present. Each scene completed 1,000 finite physics steps in a local diagnostic runtime. This is not an end-to-end GPU perception/control test of the published images. Full GPU rendering and grasp execution still need validation on a GPU-enabled Docker host.

- GPU vendor/CDI or device-driver errors: check NVIDIA Container Toolkit configuration and retry the GPU check above.
- Missing PLY, mesh, texture or checkpoint: rerun `bash scripts/download_assets.sh`.
- No image window: check DISPLAY/X11 authorization, or use the headless command.
- No task/camera messages: wait for server initialization and check matching ROS domain and middleware on both containers.
- Detector has no targets: verify camera publication and weights; inspect `/kele/result_image`. CPU detection is slower.
- Container name already in use: stop the existing demo container before restarting.

## Files and licenses

```text
baseline/client_task_1.py                     # fixed grasp controller
baseline/perception/kele_detect.py             # baseline visual detector
baseline/scripts/run_baseline.sh               # detector + controller launcher
examples/supermarket_sorting/
  supermarket_sorting_server.py                # simulation and ROS 2 bridge
  supermarket_sorting_client.py                # additional task controller
  retail_competition_layout.json               # product and shelf metadata
  perception/aruco_detect.py                   # head/wrist marker detection
  models/                                     # scene XML + downloaded resources
scripts/download_assets.sh                    # verified resource download
scripts/start_server.sh                       # fixed/random server launcher
```

See [LICENSE](LICENSE), [baseline/LICENSE](baseline/LICENSE) and [third-party notices](THIRD_PARTY_NOTICES.md).
