#!/usr/bin/env bash
set -Eeuo pipefail

# Export the already-built Docker images for an air-gapped machine. This uses
# docker save rather than rebuilding, preserving the complete runtime.

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
default_output="${repo_root}/../supermarket_sorting_offline_delivery"
output_dir="${1:-$default_output}"
server_image="${SERVER_IMAGE:-crpi-1pzq998p9m7w0auy.cn-hangzhou.personal.cr.aliyuncs.com/challengecup/supermarket_sorting_final:server}"
client_image="${CLIENT_IMAGE:-crpi-1pzq998p9m7w0auy.cn-hangzhou.personal.cr.aliyuncs.com/challengecup/supermarket_sorting_final:client}"

die() {
  echo "错误：$*" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || die "未找到 docker"
docker info >/dev/null 2>&1 || die "Docker daemon 不可用"

server_id="$(docker image inspect --format '{{.Id}}' "$server_image" 2>/dev/null)" \
  || die "本机没有 server 镜像：$server_image"
client_id="$(docker image inspect --format '{{.Id}}' "$client_image" 2>/dev/null)" \
  || die "本机没有 client 镜像：$client_image"

if [[ -e "$output_dir/supermarket_sorting_server.tar" || \
      -e "$output_dir/supermarket_sorting_client.tar" ]]; then
  die "输出目录已有 tar；请换一个目录，或先人工确认后删除旧产物：$output_dir"
fi
mkdir -p "$output_dir"

server_tar="$output_dir/supermarket_sorting_server.tar"
client_tar="$output_dir/supermarket_sorting_client.tar"

echo "导出 server: $server_image ($server_id)"
docker save "$server_image" -o "$server_tar.part"
mv -- "$server_tar.part" "$server_tar"

echo "导出 client: $client_image ($client_id)"
docker save "$client_image" -o "$client_tar.part"
mv -- "$client_tar.part" "$client_tar"
chmod 0644 "$server_tar" "$client_tar"

cat > "$output_dir/MANIFEST.txt" <<EOF
Supermarket Sorting offline image delivery
Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Architecture: $(uname -m)

SERVER_IMAGE=$server_image
SERVER_IMAGE_ID=$server_id
SERVER_TAR=$(basename "$server_tar")

CLIENT_IMAGE=$client_image
CLIENT_IMAGE_ID=$client_id
CLIENT_TAR=$(basename "$client_tar")

Source repository (copy with extracted resources and baseline weights):
https://github.com/DISCOVER-Robotics/MMK2-Supermarket-Sorting-Demo
EOF

(
  cd "$output_dir"
  sha256sum "$(basename "$server_tar")" "$(basename "$client_tar")" MANIFEST.txt > SHA256SUMS
)

cat > "$output_dir/README_OFFLINE.txt" <<'EOF'
离线交付包
==========

本目录的两个 tar 是 Docker image archive，不是源码压缩包。目标机无需联网，执行：

  sha256sum -c SHA256SUMS
  docker load --input supermarket_sorting_server.tar
  docker load --input supermarket_sorting_client.tar

建议加载后固定本地别名，后续命令更短：

  docker tag crpi-1pzq998p9m7w0auy.cn-hangzhou.personal.cr.aliyuncs.com/challengecup/supermarket_sorting_final:server supermarket_sorting:server
  docker tag crpi-1pzq998p9m7w0auy.cn-hangzhou.personal.cr.aliyuncs.com/challengecup/supermarket_sorting_final:client supermarket_sorting:client

Baseline 不放进 client image，请复制 Demo 仓库中的 baseline 目录（包括下载的权重），启动 client 时挂载：

  -v /path/to/MMK2-Supermarket-Sorting-Demo/baseline:/workspace/baseline:ro

同时复制 Demo 仓库及已解压场景资源，启动命令见主 README。若导出时使用本地别名，加载后无需 docker tag。

运行参数和原 Docker 部署一致：宿主机需 Linux x86_64、Docker、NVIDIA Driver/Container
Toolkit；Server/Client 使用 --network host、--ipc host，ROS_DOMAIN_ID 默认 99。
EOF

echo
echo "导出完成：$output_dir"
du -h "$server_tar" "$client_tar"
echo "校验文件：$output_dir/SHA256SUMS"
