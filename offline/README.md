# 离线镜像交付

`export_images.sh` 将本机已有的 server/client 镜像原样导出为 Docker image tar，适合没有
网络的比赛机器。它不会重新构建，也不会把本机源码、Git 历史或 Docker build cache 混入交付物。

## 生成交付物

```bash
./offline/export_images.sh /path/to/output
```

输出目录包含：

```text
supermarket_sorting_server.tar   # Server 完整运行时
supermarket_sorting_client.tar   # Client 完整运行时
MANIFEST.txt                     # 镜像 tag、image ID、Baseline 仓库地址
SHA256SUMS                       # 传输完整性校验
README_OFFLINE.txt               # 目标机加载说明
```

默认镜像名可以通过环境变量覆盖：

```bash
SERVER_IMAGE=supermarket_sorting:server \
CLIENT_IMAGE=supermarket_sorting:client \
./offline/export_images.sh /path/to/output
```

## 目标机加载

目标机只需安装 Docker 和 NVIDIA Container Toolkit，完全离线执行：

```bash
sha256sum -c SHA256SUMS
docker load -i supermarket_sorting_server.tar
docker load -i supermarket_sorting_client.tar
docker tag crpi-1pzq998p9m7w0auy.cn-hangzhou.personal.cr.aliyuncs.com/challengecup/supermarket_sorting_final:server supermarket_sorting:server
docker tag crpi-1pzq998p9m7w0auy.cn-hangzhou.personal.cr.aliyuncs.com/challengecup/supermarket_sorting_final:client supermarket_sorting:client
```

Baseline 位于本仓库的 `baseline/`。请连同本仓库和已下载解压的场景资源、检测权重一起复制到目标机；仅转移镜像不包含这些挂载文件。

启动时把 `baseline/` 挂载到 `/workspace/baseline`。完整命令见 [English](../README.md) / [中文](../README.zh-CN.md)。若导出时指定了本地镜像标签，加载后无需执行上面的两条 `docker tag`。

## 交付前检查

目标机不需要 `docker pull`、`apt`、`pip` 或重新执行 Dockerfile；tar 中已包含 CUDA、ROS2、
PyTorch、MuJoCo、OpenCV 和 Ultralytics 运行时。宿主机仍必须提供 NVIDIA 驱动和容器工具包。
