# MMK2 fixed grasp baseline

[English instructions](../README.md#fixed-grasp-demo) | [中文说明](../README.zh-CN.md#固定抓取演示)

Run from the repository root using the main deployment guide. The client mounts this directory at `/workspace/baseline`. Download the model and scene assets with `bash scripts/download_assets.sh` from the repository root first.

The controller approaches the shelf, visually grasps a cola can, lifts and retreats with the grasp retained. Delivery placement and randomized obstacle avoidance are not included in this baseline.

请在仓库根目录按主部署指南操作。Client 将本目录挂载到 `/workspace/baseline`。先在仓库根目录执行 `bash scripts/download_assets.sh` 下载模型和场景资源。控制器完成接近货架、视觉抓取可乐、抬升与保持抓取退回，不包含配送放置和随机障碍避障。

See [LICENSE](LICENSE) and [third-party notices](../THIRD_PARTY_NOTICES.md).
