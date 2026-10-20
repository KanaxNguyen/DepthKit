"""Camera calibration from DepthKit Lab Capture (AVCameraCalibrationData exported as JSON).

Conventions follow Apple's AVCameraCalibrationData:
- Intrinsics are in pixels at `reference_size` (sensor orientation, landscape). Scale them to the image you use.
- Extrinsics are [R | t] mapping reference-camera coordinates to this camera: X_cam = R @ X_ref + t,
  with t in millimeters.
- Lens distortion is a radial lookup table: the magnification of a point's distance from
  `distortion_center`, sampled from 0 to the largest distance to an image corner.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np


@dataclass
class Calibration:
    K: np.ndarray                    # 3x3, pixels at reference_size
    reference_size: tuple[int, int]  # (width, height)
    R: np.ndarray                    # 3x3
    t_m: np.ndarray                  # 3, meters
    pixel_size_mm: float
    distortion_center: np.ndarray    # (x, y) pixels at reference_size
    lut: np.ndarray                  # undistorted -> distorted
    inverse_lut: np.ndarray          # distorted -> undistorted

    @classmethod
    def from_json(cls, path: str | Path) -> "Calibration":
        return cls.from_dict(json.loads(Path(path).read_text()))

    @classmethod
    def from_dict(cls, d: dict) -> "Calibration":
        E = np.asarray(d["extrinsicMatrix"], dtype=np.float64)
        return cls(
            K=np.asarray(d["intrinsicMatrix"], dtype=np.float64),
            reference_size=(int(d["intrinsicReferenceDimensions"][0]), int(d["intrinsicReferenceDimensions"][1])),
            R=E[:, :3],
            t_m=E[:, 3] / 1000.0,
            pixel_size_mm=float(d["pixelSizeMillimeters"]),
            distortion_center=np.asarray(d["lensDistortionCenter"], dtype=np.float64),
            lut=np.asarray(d["lensDistortionLookupTable"], dtype=np.float64),
            inverse_lut=np.asarray(d["inverseLensDistortionLookupTable"], dtype=np.float64),
        )

    def scaled(self, width: int, height: int) -> "Calibration":
        """The same calibration for an image of a different resolution (same aspect ratio)."""
        sx = width / self.reference_size[0]
        sy = height / self.reference_size[1]
        S = np.diag([sx, sy, 1.0])
        return Calibration(S @ self.K, (width, height), self.R, self.t_m, self.pixel_size_mm,
                           self.distortion_center * [sx, sy], self.lut, self.inverse_lut)


def relative_pose(a: Calibration, b: Calibration) -> tuple[np.ndarray, np.ndarray]:
    """(R, t) mapping camera-a coordinates to camera-b coordinates, t in meters."""
    R = b.R @ a.R.T
    t = b.t_m - R @ a.t_m
    return R, t


def scale_intrinsics(K: np.ndarray, from_size: tuple[int, int], to_size: tuple[int, int]) -> np.ndarray:
    sx = to_size[0] / from_size[0]
    sy = to_size[1] / from_size[1]
    return np.diag([sx, sy, 1.0]) @ K


def lut_map(points: np.ndarray, table: np.ndarray, center: np.ndarray, size: tuple[int, int]) -> np.ndarray:
    """Apply Apple's radial lookup table to points (N x 2, pixels).

    Port of Apple's `lensDistortionPoint(for:lookupTable:distortionOpticalCenter:imageSize:)`:
    r_max is the largest distance from the center to an image corner; the table holds magnifications m(r)
    sampled uniformly on [0, r_max]; the mapped point is center + delta * (1 + m(r)).
    """
    points = np.asarray(points, dtype=np.float64)
    w, h = size
    corners = np.array([[0, 0], [w, 0], [0, h], [w, h]], dtype=np.float64)
    r_max = np.max(np.linalg.norm(corners - center, axis=1))

    delta = points - center
    r = np.linalg.norm(delta, axis=-1)
    position = np.clip(r / r_max, 0, 1) * (len(table) - 1)
    lo = np.floor(position).astype(int)
    hi = np.minimum(lo + 1, len(table) - 1)
    frac = position - lo
    magnification = table[lo] * (1 - frac) + table[hi] * frac
    return center + delta * (1 + magnification)[..., None]


def undistort_maps(calib: Calibration, size: tuple[int, int]) -> tuple[np.ndarray, np.ndarray]:
    """cv2.remap maps that turn a distorted image of `size` into an ideal pinhole image.

    For every output (undistorted) pixel we look up where it lands in the distorted image, which is what the
    forward table (`lut`) gives.
    """
    c = calib.scaled(*size)
    w, h = size
    xs, ys = np.meshgrid(np.arange(w, dtype=np.float64), np.arange(h, dtype=np.float64))
    pts = np.stack([xs.ravel(), ys.ravel()], axis=1)
    distorted = lut_map(pts, c.lut, c.distortion_center, size)
    return (distorted[:, 0].reshape(h, w).astype(np.float32),
            distorted[:, 1].reshape(h, w).astype(np.float32))
