"""Load a DepthKit Lab Capture folder.

A capture folder contains, in sensor orientation (ignore EXIF orientation):
  ultrawide.jpg / wide.jpg / tele.jpg + <lens>_calibration.json
  apple_stereo_rgb.jpg + apple_stereo_depth.f32 + apple_stereo_depth.json   (Apple dual-camera depth)
  lidar_rgb.jpg + lidar_depth.f32 + lidar_depth.json                         (LiDAR depth camera)
  meta.json                                                                  (label, tape distance, device)
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image

from .calib import Calibration


@dataclass
class DepthMap:
    depth: np.ndarray                 # H x W float32 meters, NaN where invalid
    calibration: Calibration | None   # intrinsics at the camera's full reference size
    quality: str = ""
    accuracy: str = ""

    @property
    def K(self) -> np.ndarray:
        """Intrinsics scaled to this depth map's resolution."""
        h, w = self.depth.shape
        return self.calibration.scaled(w, h).K


@dataclass
class Capture:
    path: Path
    meta: dict
    images: dict[str, np.ndarray] = field(default_factory=dict)        # lens -> H x W x 3 uint8
    calibrations: dict[str, Calibration] = field(default_factory=dict)
    apple_stereo: DepthMap | None = None
    apple_stereo_rgb: np.ndarray | None = None
    lidar: DepthMap | None = None
    lidar_rgb: np.ndarray | None = None

    @property
    def label(self) -> str:
        return self.meta.get("label", "")

    @property
    def tape_distance(self) -> float | None:
        return self.meta.get("tapeDistanceMeters")


def read_image(path: Path) -> np.ndarray:
    # PIL does not apply EXIF orientation unless asked, so pixels stay in sensor orientation.
    with Image.open(path) as im:
        return np.asarray(im.convert("RGB"))


def read_depth(folder: Path, name: str) -> DepthMap | None:
    info_path = folder / f"{name}_depth.json"
    raw_path = folder / f"{name}_depth.f32"
    if not info_path.exists() or not raw_path.exists():
        return None
    info = json.loads(info_path.read_text())
    depth = np.fromfile(raw_path, dtype="<f4").reshape(info["height"], info["width"]).copy()
    depth[~np.isfinite(depth) | (depth <= 0)] = np.nan
    calibration = Calibration.from_dict(info["calibration"]) if info.get("calibration") else None
    return DepthMap(depth, calibration, info.get("quality", ""), info.get("accuracy", ""))


def load_capture(folder: str | Path) -> Capture:
    folder = Path(folder)
    capture = Capture(folder, json.loads((folder / "meta.json").read_text()))
    for lens in ("ultrawide", "wide", "tele"):
        image = folder / f"{lens}.jpg"
        calib = folder / f"{lens}_calibration.json"
        if image.exists():
            capture.images[lens] = read_image(image)
        if calib.exists():
            capture.calibrations[lens] = Calibration.from_json(calib)
    capture.apple_stereo = read_depth(folder, "apple_stereo")
    capture.lidar = read_depth(folder, "lidar")
    if (folder / "apple_stereo_rgb.jpg").exists():
        capture.apple_stereo_rgb = read_image(folder / "apple_stereo_rgb.jpg")
    if (folder / "lidar_rgb.jpg").exists():
        capture.lidar_rgb = read_image(folder / "lidar_rgb.jpg")
    return capture


def list_captures(root: str | Path) -> list[Path]:
    root = Path(root)
    return sorted(p for p in root.iterdir() if (p / "meta.json").exists())
