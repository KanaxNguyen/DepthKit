"""Depth error metrics and resampling onto a common grid."""
from __future__ import annotations

import numpy as np


def resize_depth(depth: np.ndarray, size: tuple[int, int]) -> np.ndarray:
    """Nearest-neighbour resize (width, height) that never blends valid and invalid pixels."""
    h, w = depth.shape
    out_w, out_h = size
    ys = np.clip(((np.arange(out_h) + 0.5) * h / out_h).astype(int), 0, h - 1)
    xs = np.clip(((np.arange(out_w) + 0.5) * w / out_w).astype(int), 0, w - 1)
    return depth[ys[:, None], xs[None, :]]


def errors(pred: np.ndarray, gt: np.ndarray, min_depth: float = 0.1, max_depth: float = 10.0) -> dict:
    """Standard monocular-depth metrics over pixels valid in both maps."""
    if pred.shape != gt.shape:
        pred = resize_depth(pred, (gt.shape[1], gt.shape[0]))
    mask = np.isfinite(pred) & np.isfinite(gt) & (gt > min_depth) & (gt < max_depth) & (pred > 0)
    if not mask.any():
        return {"n": 0, "abs_rel": np.nan, "rmse": np.nan, "mae": np.nan, "delta1": np.nan}
    p, g = pred[mask], gt[mask]
    ratio = np.maximum(p / g, g / p)
    return {
        "n": int(mask.sum()),
        "abs_rel": float(np.mean(np.abs(p - g) / g)),
        "rmse": float(np.sqrt(np.mean((p - g) ** 2))),
        "mae": float(np.mean(np.abs(p - g))),
        "delta1": float(np.mean(ratio < 1.25)),
    }


def center_depth(depth: np.ndarray, window: int = 9) -> float:
    """Median depth in a square at the image center, ignoring invalid pixels."""
    h, w = depth.shape
    half = window // 2
    patch = depth[h // 2 - half:h // 2 + half + 1, w // 2 - half:w // 2 + half + 1]
    values = patch[np.isfinite(patch)]
    return float(np.median(values)) if values.size else float("nan")
