#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
asset_name=mmk2-supermarket-assets-v1.0.0.tar.gz
release_url=https://github.com/DISCOVER-Robotics/MMK2-Supermarket-Sorting-Demo/releases/download/v1.0.0
for command in curl sha256sum tar; do
  command -v "$command" >/dev/null || { echo "Required command missing: $command" >&2; exit 1; }
done
download_dir="$(mktemp -d)"
trap 'rm -f -- "$download_dir/$asset_name" "$download_dir/SHA256SUMS"; rmdir -- "$download_dir"' EXIT
curl --fail --location --retry 3 "$release_url/$asset_name" -o "$download_dir/$asset_name"
curl --fail --location --retry 3 "$release_url/SHA256SUMS" -o "$download_dir/SHA256SUMS"
(cd "$download_dir" && sha256sum --check SHA256SUMS)
tar -xzf "$download_dir/$asset_name" -C "$repo_root"
test -s "$repo_root/baseline/weights/kele.pt"
test -s "$repo_root/examples/supermarket_sorting/models/3dgs/shentoon/retail_background_fit.ply"
echo "Runtime assets and detector weights are ready."
