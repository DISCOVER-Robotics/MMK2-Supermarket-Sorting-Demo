#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-fixed}"
case "$mode" in
  fixed) task_env=(-e SUPERMARKET_FIXED_BASELINE=1 -e SUPERMARKET_RANDOMIZE=0 -e SUPERMARKET_RANDOMIZE_OBSTACLES=0 -e SUPERMARKET_TASKS=product_032) ;;
  random) task_env=(-e SUPERMARKET_FIXED_BASELINE=0 -e SUPERMARKET_RANDOMIZE=1 -e SUPERMARKET_RANDOMIZE_OBSTACLES=1 -e SUPERMARKET_SEED="${SUPERMARKET_SEED:-11}" -e SUPERMARKET_TASKS=all) ;;
  *) echo "Usage: bash scripts/start_server.sh [fixed|random]" >&2; exit 2 ;;
esac
display_env=()
if [[ "${SUPERMARKET_HEADLESS:-0}" == 1 ]]; then
  display_env=(-e MUJOCO_GL=egl -e SUPERMARKET_HEADLESS=1)
else
  : "${DISPLAY:?Set DISPLAY and run xhost +local:docker, or use SUPERMARKET_HEADLESS=1}"
  display_env=(-e DISPLAY="$DISPLAY" -e MUJOCO_GL=glfw -e SUPERMARKET_HEADLESS=0 -v /tmp/.X11-unix:/tmp/.X11-unix:rw)
fi
test -s "$repo_root/examples/supermarket_sorting/models/3dgs/shentoon/retail_background_fit.ply" || {
  echo "Missing runtime assets. Run: bash scripts/download_assets.sh" >&2; exit 1;
}
docker run --rm -it --gpus all --network host --ipc host \
  --name supermarket_sorting_server \
  -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-99}" -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -e SUPERMARKET_ENABLE_RENDER=1 -e SUPERMARKET_ENABLE_LIDAR=1 \
  -e SUPERMARKET_USE_GS=1 -e SUPERMARKET_GS_SEQUENTIAL=1 \
  -e TORCH_EXTENSIONS_DIR=/root/.cache/torch_extensions \
  "${task_env[@]}" "${display_env[@]}" \
  -v "$repo_root":/workspace/supermarket_sorting_task:ro \
  -v supermarket_sorting_cache:/root/.cache \
  supermarket_sorting:server \
  bash -lc 'cd /workspace/supermarket_sorting_task && source /opt/ros/humble/setup.bash && python3 examples/supermarket_sorting/supermarket_sorting_server.py'
