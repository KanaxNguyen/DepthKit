"""Thin wrappers around the learned depth models. Each one is optional: install it with `./setup.sh <name>`.

| Name                | Input                       | Paper |
|---------------------|-----------------------------|-------|
| depth_pro           | one RGB image               | Bochkovskii et al., "Depth Pro", ICLR 2025 (Apple) |
| prompt_da           | RGB + low-res LiDAR prompt  | Lin et al., "Prompting Depth Anything for 4K Resolution Accurate Metric Depth Estimation", CVPR 2025 |
| foundation_stereo   | rectified stereo pair       | Wen et al., "FoundationStereo: Zero-Shot Stereo Matching", CVPR 2025 (NVIDIA) |

The wrappers keep images in sensor orientation and return metric depth (meters) as float32 numpy arrays.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

LAB = Path(__file__).resolve().parent.parent
THIRD_PARTY = LAB / "third_party"
CHECKPOINTS = LAB / "checkpoints"


def device():
    import torch
    if torch.cuda.is_available():
        return torch.device("cuda")
    if torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def _require(repo: str):
    path = THIRD_PARTY / repo
    if not path.exists():
        raise RuntimeError(f"{repo} is not installed. Run ./setup.sh from the lab folder first.")
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))
    return path


class DepthPro:
    """Monocular metric depth. Passing the true focal length (from calibration) removes its focal-length guess."""

    def __init__(self):
        _require("ml-depth-pro/src")
        import torch
        from depth_pro import create_model_and_transforms
        from depth_pro.depth_pro import DEFAULT_MONODEPTH_CONFIG_DICT

        config = DEFAULT_MONODEPTH_CONFIG_DICT
        config.checkpoint_uri = str(CHECKPOINTS / "depth_pro.pt")
        self.device = device()
        precision = torch.float16 if self.device.type != "cpu" else torch.float32
        self.model, self.transform = create_model_and_transforms(config=config, device=self.device, precision=precision)
        self.model.eval()

    def __call__(self, rgb: np.ndarray, focal_px: float | None = None) -> np.ndarray:
        import torch
        with torch.no_grad():
            f = torch.tensor(focal_px, device=self.device) if focal_px else None
            prediction = self.model.infer(self.transform(rgb), f_px=f)
        return prediction["depth"].float().cpu().numpy()


class PromptDA:
    """Depth Anything prompted with low-resolution LiDAR depth -> high-resolution metric depth."""

    def __init__(self, checkpoint: str = "depth-anything/prompt-depth-anything-vitl"):
        _require("PromptDA")
        from promptda.promptda import PromptDA as Model

        self.device = device()
        self.model = Model.from_pretrained(checkpoint).to(self.device).eval()

    def __call__(self, rgb: np.ndarray, lidar: np.ndarray, long_side: int = 1008,
                 prompt_size: tuple[int, int] = (256, 192)) -> np.ndarray:
        import cv2
        import torch

        h, w = rgb.shape[:2]
        scale = long_side / max(h, w)
        size = (int(round(w * scale / 14)) * 14, int(round(h * scale / 14)) * 14)   # ViT patch multiple
        image = cv2.resize(rgb, size, interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
        image = torch.from_numpy(image).permute(2, 0, 1)[None].to(self.device)

        # ARKit-like low-res prompt (the paper's setting); zeros mark missing depth.
        from .metrics import resize_depth
        prompt = np.nan_to_num(resize_depth(lidar, prompt_size), nan=0.0).astype(np.float32)
        prompt = torch.from_numpy(prompt)[None, None].to(self.device)
        with torch.no_grad():
            depth = self.model.predict(image, prompt)
        return depth.squeeze().float().cpu().numpy()


class FoundationStereo:
    """Zero-shot stereo. Released for CUDA; on Apple Silicon it may fall back to CPU and be slow."""

    def __init__(self, checkpoint_dir: Path = CHECKPOINTS / "foundation_stereo" / "23-51-11"):
        _require("FoundationStereo")
        import torch
        from omegaconf import OmegaConf
        from core.foundation_stereo import FoundationStereo as Model

        cfg = OmegaConf.load(checkpoint_dir / "cfg.yaml")
        if "vit_size" not in cfg:
            cfg["vit_size"] = "vitl"
        self.device = device()
        self.model = Model(cfg)
        state = torch.load(checkpoint_dir / "model_best_bp2.pth", map_location="cpu", weights_only=False)
        self.model.load_state_dict(state["model"])
        self.model.to(self.device).eval()

    def __call__(self, left: np.ndarray, right: np.ndarray, iters: int = 32) -> np.ndarray:
        import torch
        from core.utils.utils import InputPadder

        to_tensor = lambda im: torch.from_numpy(im).permute(2, 0, 1)[None].float().to(self.device)
        a, b = to_tensor(left), to_tensor(right)
        padder = InputPadder(a.shape, divis_by=32, force_square=False)
        a, b = padder.pad(a, b)
        with torch.no_grad():
            disparity = self.model.forward(a, b, iters=iters, test_mode=True)
        disparity = padder.unpad(disparity.float()).squeeze().cpu().numpy()
        disparity[disparity <= 0.5] = np.nan
        return disparity
