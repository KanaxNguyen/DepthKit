"""Plot helpers for the notebook."""
from __future__ import annotations

import matplotlib.pyplot as plt
import numpy as np


def show_depths(maps: dict[str, np.ndarray], vmax: float | None = None, cols: int = 3):
    """Grid of depth maps sharing one color scale (meters, near = bright)."""
    finite = [m[np.isfinite(m)] for m in maps.values() if np.isfinite(m).any()]
    vmax = vmax or (float(np.percentile(np.concatenate(finite), 98)) if finite else 5.0)
    rows = int(np.ceil(len(maps) / cols))
    fig, axes = plt.subplots(rows, cols, figsize=(4.2 * cols, 3.4 * rows), squeeze=False)
    for ax, (name, depth) in zip(axes.ravel(), maps.items()):
        im = ax.imshow(depth, cmap="turbo_r", vmin=0, vmax=vmax)
        ax.set_title(name)
        ax.axis("off")
    for ax in axes.ravel()[len(maps):]:
        ax.axis("off")
    fig.colorbar(im, ax=axes, shrink=0.8, label="depth (m)")
    return fig


def show_images(images: dict[str, np.ndarray], cols: int = 3):
    rows = int(np.ceil(len(images) / cols))
    fig, axes = plt.subplots(rows, cols, figsize=(4.2 * cols, 3.4 * rows), squeeze=False)
    for ax, (name, image) in zip(axes.ravel(), images.items()):
        ax.imshow(image)
        ax.set_title(name)
        ax.axis("off")
    for ax in axes.ravel()[len(images):]:
        ax.axis("off")
    return fig


def show_rectified(left: np.ndarray, right: np.ndarray, lines: int = 12):
    """Side-by-side rectified pair with horizontal guide lines: matching points should share a row."""
    pair = np.hstack([left, right])
    fig, ax = plt.subplots(figsize=(12, 12 * pair.shape[0] / pair.shape[1]))
    ax.imshow(pair)
    for y in np.linspace(0, pair.shape[0] - 1, lines):
        ax.axhline(y, color="lime", linewidth=0.6)
    ax.axis("off")
    return fig


def error_vs_distance(pred: np.ndarray, gt: np.ndarray, bins=(0, 0.5, 1, 1.5, 2, 3, 5), ax=None, label=None):
    """Mean absolute relative error per LiDAR distance bin."""
    from .metrics import resize_depth
    if pred.shape != gt.shape:
        pred = resize_depth(pred, (gt.shape[1], gt.shape[0]))
    mask = np.isfinite(pred) & np.isfinite(gt) & (gt > 0)
    centers, values = [], []
    for lo, hi in zip(bins[:-1], bins[1:]):
        m = mask & (gt >= lo) & (gt < hi)
        if m.sum() > 50:
            centers.append((lo + hi) / 2)
            values.append(float(np.mean(np.abs(pred[m] - gt[m]) / gt[m])))
    ax = ax or plt.gca()
    ax.plot(centers, values, marker="o", label=label)
    ax.set_xlabel("LiDAR distance (m)")
    ax.set_ylabel("AbsRel")
    return ax
