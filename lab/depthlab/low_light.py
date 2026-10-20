"""Low-light preprocessing for night captures.

CLAHE on the luminance channel is the no-download baseline. Learned enhancers to try next, run before the
depth models in the same way: Zero-DCE (Guo et al., CVPR 2020), Retinexformer (Cai et al., ICCV 2023), or a RAW
pipeline such as Learning to See in the Dark (Chen et al., CVPR 2018).
"""
from __future__ import annotations

import cv2
import numpy as np


def mean_luminance(rgb: np.ndarray) -> float:
    return float(cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).mean())


def is_dark(rgb: np.ndarray, threshold: float = 50) -> bool:
    return mean_luminance(rgb) < threshold


def clahe(rgb: np.ndarray, clip: float = 3.0, tiles: int = 8, gamma: float = 0.7) -> np.ndarray:
    """Gamma lift, then contrast-limited histogram equalization on L in Lab space."""
    lifted = np.clip(255 * (rgb / 255.0) ** gamma, 0, 255).astype(np.uint8)
    lab = cv2.cvtColor(lifted, cv2.COLOR_RGB2LAB)
    lab[..., 0] = cv2.createCLAHE(clipLimit=clip, tileGridSize=(tiles, tiles)).apply(lab[..., 0])
    return cv2.cvtColor(lab, cv2.COLOR_LAB2RGB)
