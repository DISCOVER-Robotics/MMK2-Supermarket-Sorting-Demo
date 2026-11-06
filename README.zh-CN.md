# MMK2 超市分拣 Demo

[English](README.md) | 简体中文

面向 MMK2 移动操作的 ROS 2 超市仿真，包含 MuJoCo 物理仿真、3D Gaussian Splatting 渲染、RGB-D 相机和激光雷达。配套 Baseline 完成到货架、视觉识别并抓取可乐、抬升、退回并保持抓取，不包含配送台放置。随机多商品配送需要另外实现控制和避障策略；Server 不包含裁判或计分模块。

## 目录

- [环境要求](#环境要求)
- [下载准备](#下载准备)
- [固定抓取演示](#固定抓取演示)
- [随机场景仿真](#随机场景仿真)
- [ROS 2 接口](#ros-2-接口)
- [参数配置](#参数配置)
- [源码构建与离线部署](#源码构建与离线部署)
- [检查与故障排查](#检查与故障排查)
- [文件与许可](#文件与许可)

## 环境要求

- Ubuntu 22.04、Docker、NVIDIA Container Toolkit、NVIDIA 驱动 ≥ 570.26。
- NVIDIA Turing 及更新架构 GPU（RTX 20/30/40/50 系列）。当前 CUDA wheel 不支持 Pascal/GTX 10 或 Volta 的 GPU 推理。检测器回退 CPU 不代表 3DGS Server 可以仅靠 CPU 运行。
- 运行时：ROS 2 Humble、CUDA 12.8、PyTorch 2.7.1+cu128、torchvision 0.22.1+cu128。
- 窗口模式需要 X11；无头渲染使用 EGL。两份镜像压缩下载量合计约 17 GB，另需预留解压、构建和缓存空间。

## 下载准备

克隆代码并下载场景资源与检测权重（压缩后约 248 MB）。脚本在解压前校验 SHA-256，无需配置 Git LFS。

```bash
git clone https://github.com/DISCOVER-Robotics/MMK2-Supermarket-Sorting-Demo.git
cd MMK2-Supermarket-Sorting-Demo
bash scripts/download_assets.sh
```

下载两个运行时镜像，并设置本地名称：

```bash
registry=crpi-1pzq998p9m7w0auy.cn-hangzhou.personal.cr.aliyuncs.com/challengecup/supermarket_sorting_final
docker pull "$registry:server"
docker pull "$registry:client"
docker tag "$registry:server" supermarket_sorting:server
docker tag "$registry:client" supermarket_sorting:client
```

启动前检查容器 GPU 接入。此命令必须能显示 GPU：

```bash
docker run --rm --gpus all --entrypoint nvidia-smi supermarket_sorting:server
```

## 固定抓取演示

### 1. 启动仿真 Server

在终端 1 的本仓库根目录执行：

```bash
xhost +local:docker
docker volume create supermarket_sorting_cache
bash scripts/start_server.sh fixed
```

启动脚本将当前仓库只读挂载到容器，使用固定目标 `product_032`，关闭商品和障碍物随机化。保持 Server 运行。首次编译 3DGS CUDA 扩展可能需要几分钟，等待初始化完成并发布相机数据后再继续。

### 2. 启动 Client 与 Baseline

终端 2 进入同一个仓库根目录，然后执行：

```bash
docker run --rm -dit --gpus all --network host --ipc host \
  --name supermarket_sorting_client \
  -e ROS_DOMAIN_ID=99 -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -v "$PWD/baseline":/workspace/baseline:ro \
  supermarket_sorting:client

docker exec -it supermarket_sorting_client \
  bash -lc 'cd /workspace/baseline && bash scripts/run_baseline.sh'
```

`baseline/` 已包含控制器、检测器、运动学模型和下载的权重，无需另行克隆 Baseline。Server 和 Client 必须使用相同的 ROS 域，此处为 99。

执行顺序为：到达货架 → 视觉定位 → 抓取 → 抬升 → 退回。结束时控制器输出 `retreat done; task-one baseline complete with grasp retained`，并继续停留在 done 阶段。需要在仿真画面中确认物品确实被抓住并退回，日志本身不是成功计分。

### 3. 检查与停止

在终端 3 查看当前任务：

```bash
docker exec supermarket_sorting_client bash -lc \
  'source /opt/ros/humble/setup.bash && ros2 topic echo --once --qos-durability transient_local /supermarket_sorting/task'
```

终端 2 按 Ctrl+C 停止 Baseline，然后关闭容器：

```bash
docker stop supermarket_sorting_client supermarket_sorting_server
xhost -local:docker
```

无头运行时，将 Server 启动命令换为下面这条。RGB-D 渲染仍保持启用，依然需要 GPU。

```bash
SUPERMARKET_HEADLESS=1 bash scripts/start_server.sh fixed
```

## 随机场景仿真

先停止固定 Server，再启动同名的随机场景容器：

```bash
bash scripts/start_server.sh random
```

该模式随机放置 45 个商品和 5 个通道障碍物。布局按照底盘完整转弯扫掠范围加 0.05 m 安全余量生成，用 0.05 m 栅格 A* 检查连通性，要求比空通道至少增加 0.30 m 绕行距离。障碍物分布于五个纵向区段，相邻区段横向和纵向间隔至少 0.40 m。启动日志输出生成尝试次数、路径长度和绕行距离。

通过 `SUPERMARKET_SEED=42 bash scripts/start_server.sh random` 指定布局种子。即使种子相同，每次启动 Server 的匿名目标 ID 和 run_prefix 也会变化。任务 JSON 包含 `schema_version`、`run_prefix`、`count` 与由 `{id, kind}` 构成的 `targets` 数组，ID 不编码货架位置。修改启动脚本中的 `SUPERMARKET_TASKS` 可按商品类别或中性 ID 筛选目标。

固定 Baseline 用于固定抓取场景，其航点不能解决随机场景的导航或配送。需要使用 `/slamware_ros_sdk_server_node/scan` 自行实现规划与避障，并扩展多商品抓取放置控制。

## ROS 2 接口

### Server 发布

| Topic | Type | 说明 |
| --- | --- | --- |
| `/slamware_ros_sdk_server_node/odom` | `nav_msgs/msg/Odometry` | 底盘位姿与速度 |
| `/tf` | `tf2_msgs/msg/TFMessage` | 动态坐标变换，包括 odom → base_link |
| `/slamware_ros_sdk_server_node/scan` | `sensor_msgs/msg/LaserScan` | 360 点激光雷达，12 Hz，坐标系 laser |
| `/joint_states` | `sensor_msgs/msg/JointState` | 升降、头部、双臂与夹爪关节 |
| `/head_camera/color/image_raw` | `sensor_msgs/msg/Image` | 头部 RGB 图像，640 × 480 |
| `/head_camera/color/camera_info` | `sensor_msgs/msg/CameraInfo` | 头部 RGB 相机内参 |
| `/head_camera/aligned_depth_to_color/image_raw` | `sensor_msgs/msg/Image` | 头部深度图，mono16，单位毫米 |
| `/head_camera/aligned_depth_to_color/camera_info` | `sensor_msgs/msg/CameraInfo` | 头部深度相机内参 |
| `/left_camera/color/image_raw`, `/right_camera/color/image_raw` | `sensor_msgs/msg/Image` | 双腕 RGB 图像 |
| `/left_camera/color/camera_info`, `/right_camera/color/camera_info` | `sensor_msgs/msg/CameraInfo` | 双腕相机内参 |
| `/supermarket_sorting/task` | `std_msgs/msg/String` | 可靠、持久化发布的 JSON 任务清单 |

### Server 订阅

| Topic | Type | 格式 |
| --- | --- | --- |
| `/cmd_vel` | `geometry_msgs/msg/Twist` | linear.x 前进速度；angular.z 偏航角速度 |
| `/spine_forward_position_controller/commands` | `std_msgs/msg/Float64MultiArray` | [slide_joint] |
| `/head_forward_position_controller/commands` | `std_msgs/msg/Float64MultiArray` | [head_yaw_joint, head_pitch_joint] |
| `/left_arm_forward_position_controller/commands`, `/right_arm_forward_position_controller/commands` | `std_msgs/msg/Float64MultiArray` | [joint1, joint2, joint3, joint4, joint5, joint6, gripper] |

### 视觉节点发布

| Topic | Type | 说明 |
| --- | --- | --- |
| `/kele/detections` | `vision_msgs/msg/Detection3DArray` | 世界坐标系中的可乐检测结果 |
| `/kele/result_image` | `sensor_msgs/msg/Image` | 检测可视化 |
| `/aruco/<camera>/ids` | `std_msgs/msg/Int32MultiArray` | 升序排列的标记 ID |
| `/aruco/<camera>/poses` | `geometry_msgs/msg/PoseArray` | 相机坐标系中的标记位姿 |
| `/aruco/<camera>/detections` | `std_msgs/msg/String` | 包含 ID、平移与四元数的 JSON |
| `/aruco/<camera>/result_image` | `sensor_msgs/msg/Image` | 标记检测可视化 |

`<camera>` 为 `head`、`left` 或 `right`。标记 ID 与位姿按数组下标对应；ArUco 节点还发布 `aruco_<camera>_<id>` TF。ArUco 检测是单独的可选节点，默认 Baseline 不启动它。

关节状态顺序：升降、头部 yaw/pitch、左臂关节 1–6 与夹爪、右臂关节 1–6 与夹爪。夹爪命令 `1.0` 表示张开，可乐 Baseline 使用 `0.08` 闭合。

## 参数配置

| 参数 | 默认值 / 示例 | 含义 |
| --- | --- | --- |
| `ROS_DOMAIN_ID` | `99` | 服务端与客户端保持一致 |
| `RMW_IMPLEMENTATION` | `rmw_cyclonedds_cpp` | ROS 2 中间件 |
| `MUJOCO_GL` | `glfw` / `egl` | 窗口 / 无头渲染 |
| `SUPERMARKET_HEADLESS` | `0` | 设为 1 启用无头模式 |
| `SUPERMARKET_ENABLE_RENDER` | `1` | 发布相机数据 |
| `SUPERMARKET_ENABLE_LIDAR` | `1` | 发布激光扫描 |
| `SUPERMARKET_USE_GS` | `1` | 启用 3DGS 渲染 |
| `SUPERMARKET_GS_SEQUENTIAL` | `1` | 逐相机渲染，降低峰值显存 |
| `SUPERMARKET_FIXED_BASELINE` | `1` (fixed) | 固定抓取场景，不能同时随机化商品 |
| `SUPERMARKET_RANDOMIZE` | `0` fixed, `1` random | 随机化 45 个商品位置 |
| `SUPERMARKET_RANDOMIZE_OBSTACLES` | `0` fixed, `1` random | 随机化 5 个通道障碍物 |
| `SUPERMARKET_SEED` | `11` | 布局随机种子，服务端代码中可选 |
| `SUPERMARKET_OBSTACLE_SEED` | 可选 | 独立障碍物种子；默认从布局种子派生 |
| `SUPERMARKET_TASKS` | `product_032` / `all` | 逗号分隔的商品类别或中性 ID |
| `SUPERMARKET_DETECTOR_DEVICE` | `auto` | Baseline YOLO 运行设备，也可设为 cpu |

`start_server.sh` 从宿主机传入 `ROS_DOMAIN_ID`、`SUPERMARKET_HEADLESS` 和随机布局种子，其余 Server 选项由脚本显式设置，需要修改脚本的 Docker 环境参数才能调整。检测器参数可在 Client 启动命令的镜像名前加入 `-e SUPERMARKET_DETECTOR_DEVICE=cpu` 或 `-e SUPERMARKET_BASELINE_WEIGHTS=/path/in/container/weights.pt`。

## 源码构建与离线部署

先下载资源，再在仓库根目录构建：

```bash
docker build -t supermarket_sorting:server .
docker build -t supermarket_sorting:client docker/client
```

离线部署时复制本仓库，**包括已解压资源和 Baseline 权重**，并通过 `docker save` / `docker load` 转移两份镜像。可选的[镜像导出脚本](offline/export_images.sh)默认导出拉取时的镜像名称；本地标签使用 `SERVER_IMAGE=supermarket_sorting:server CLIENT_IMAGE=supermarket_sorting:client bash offline/export_images.sh /path/to/output`。宿主机仍需 NVIDIA 驱动和容器工具包。只有镜像归档并不包含当前仓库挂载的 Baseline 与下载资源。

## 检查与故障排查

执行六项场景和布局单元测试：

```bash
docker run --rm --network none \
  -v "$PWD":/workspace/supermarket_sorting_task:ro \
  supermarket_sorting:server bash -lc \
  'cd /workspace/supermarket_sorting_task && source /opt/ros/humble/setup.bash && export PYTHONPATH="$PWD:${PYTHONPATH:-}" && python3 -m unittest discover -s examples/supermarket_sorting -p "test_*.py" -v'
```

场景检查已通过六项测试；固定和随机两种 MuJoCo 场景均可编译，73 项 3DGS 资源绑定全部存在，每种场景在本地诊断运行时完成 1,000 步有限值物理仿真。这不等同于对公开镜像完成了 GPU 感知和控制全流程测试，完整 GPU 渲染与抓取仍需在支持容器 GPU 的机器验证。

- GPU vendor/CDI 或设备驱动错误：检查 NVIDIA Container Toolkit 配置，再执行上述 GPU 检查。
- 缺少 PLY、网格、纹理或权重：重新执行 `bash scripts/download_assets.sh`。
- 无图像窗口：检查 DISPLAY 与 X11 授权，或使用无头命令。
- 无任务或相机消息：等待初始化完成，并检查双方 ROS 域与中间件一致。
- 检测不到目标：检查相机发布与权重，查看 `/kele/result_image`。CPU 检测速度较慢。
- 容器名已存在：停止旧 Demo 容器后再启动。

## 文件与许可

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

参见 [LICENSE](LICENSE)、[baseline/LICENSE](baseline/LICENSE) 与[第三方声明](THIRD_PARTY_NOTICES.md)。
