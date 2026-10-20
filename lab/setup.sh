#!/usr/bin/env bash
# Install the optional learned models into lab/third_party and lab/checkpoints.
#   ./setup.sh depth_pro          Apple Depth Pro              (code: github.com/apple/ml-depth-pro, weights ~1.9 GB)
#   ./setup.sh prompt_da          Prompt Depth Anything ViT-L  (code: github.com/DepthAnything/PromptDA, weights from Hugging Face on first use)
#   ./setup.sh foundation_stereo  NVIDIA FoundationStereo      (code: github.com/NVlabs/FoundationStereo; weights must be downloaded by hand, see below)
#   ./setup.sh all
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p third_party checkpoints

uv sync --extra models

clone() {  # repo url, folder
  [ -d "third_party/$2" ] || git clone --depth 1 "$1" "third_party/$2"
}

depth_pro() {
  clone https://github.com/apple/ml-depth-pro.git ml-depth-pro
  [ -f checkpoints/depth_pro.pt ] || curl -L -o checkpoints/depth_pro.pt \
    https://ml-site.cdn-apple.com/models/depth-pro/depth_pro.pt
}

prompt_da() {
  clone https://github.com/DepthAnything/PromptDA.git PromptDA
  echo "PromptDA weights download from Hugging Face (depth-anything/prompt-depth-anything-vitl) on first use."
}

foundation_stereo() {
  clone https://github.com/NVlabs/FoundationStereo.git FoundationStereo
  if [ ! -f checkpoints/foundation_stereo/23-51-11/model_best_bp2.pth ]; then
    echo "FoundationStereo weights are shared on Google Drive (see the README of NVlabs/FoundationStereo)."
    echo "Download the '23-51-11' folder (cfg.yaml + model_best_bp2.pth) into lab/checkpoints/foundation_stereo/."
  fi
}

case "${1:-all}" in
  depth_pro) depth_pro ;;
  prompt_da) prompt_da ;;
  foundation_stereo) foundation_stereo ;;
  all) depth_pro; prompt_da; foundation_stereo ;;
  *) echo "unknown model: $1"; exit 1 ;;
esac
