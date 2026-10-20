"""Stereo depth from two of the iPhone's back cameras (normally wide = reference, ultra-wide = second view).

Pipeline:
1. Resize both images to a common working size and undistort them with Apple's lookup tables.
2. Rectify with OpenCV using the relative pose from the calibration. The cameras sit a centimetre or so apart,
   often one above the other, so the rectified pair may be rotated 90° to give the horizontal disparity
   that stereo networks expect, and swapped so the left image is the left camera.
3. Run a stereo matcher (classic SGBM here; learned models in models.py) to get disparity.
4. Convert disparity to depth and resample it onto the reference camera's original (distorted) pixel grid,
   which is the grid LiDAR and Apple's depth maps use.

Depth error from stereo grows with distance squared over baseline, so expect useful results only up to
a metre or two with a ~1 cm baseline.
"""
from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

from .calib import Calibration, lut_map, relative_pose, undistort_maps


@dataclass
class RectifiedPair:
    left: np.ndarray        # H x W x 3 uint8, rectified (and rotated if needed)
    right: np.ndarray
    focal: float            # pixels, in the rectified images
    baseline: float         # meters
    reference_is_left: bool
    rotated: bool           # rectified images were rotated 90° clockwise
    R1: np.ndarray          # rectifying rotation of the reference camera
    P1: np.ndarray          # 3x4 projection of the rectified reference camera
    size: tuple[int, int]   # rectified image size before rotation (w, h)
    work_calib: Calibration  # reference calibration at the working size


def rectify(ref_img: np.ndarray, ref_calib: Calibration, other_img: np.ndarray, other_calib: Calibration,
            work_width: int = 1024) -> RectifiedPair:
    h0, w0 = ref_img.shape[:2]
    size = (work_width, int(round(work_width * h0 / w0)))

    ref_c = ref_calib.scaled(*size)
    other_c = other_calib.scaled(*size)
    ref_u = cv2.remap(cv2.resize(ref_img, size, interpolation=cv2.INTER_AREA), *undistort_maps(ref_calib, size),
                      cv2.INTER_LINEAR)
    other_u = cv2.remap(cv2.resize(other_img, size, interpolation=cv2.INTER_AREA), *undistort_maps(other_calib, size),
                        cv2.INTER_LINEAR)

    R, t = relative_pose(ref_c, other_c)
    R1, R2, P1, P2, _, _, _ = cv2.stereoRectify(ref_c.K, None, other_c.K, None, size, R, t.reshape(3, 1),
                                                flags=cv2.CALIB_ZERO_DISPARITY, alpha=0)
    maps1 = cv2.initUndistortRectifyMap(ref_c.K, None, R1, P1, size, cv2.CV_32FC1)
    maps2 = cv2.initUndistortRectifyMap(other_c.K, None, R2, P2, size, cv2.CV_32FC1)
    ref_r = cv2.remap(ref_u, *maps1, cv2.INTER_LINEAR)
    other_r = cv2.remap(other_u, *maps2, cv2.INTER_LINEAR)

    # Second camera's center in the rectified reference frame decides orientation and order.
    center = R1 @ (-R.T @ t)
    vertical = abs(center[1]) > abs(center[0])
    if vertical:
        ref_r = cv2.rotate(ref_r, cv2.ROTATE_90_CLOCKWISE)
        other_r = cv2.rotate(other_r, cv2.ROTATE_90_CLOCKWISE)
        # After a clockwise rotation, the new x axis points along the old -y.
        other_to_the_right = -center[1] > 0
    else:
        other_to_the_right = center[0] > 0

    left, right = (ref_r, other_r) if other_to_the_right else (other_r, ref_r)
    return RectifiedPair(left, right, float(P1[0, 0]), float(np.linalg.norm(t)), other_to_the_right, vertical,
                         R1, P1, size, ref_c)


def sgbm_disparity(pair: RectifiedPair, max_disparity: int = 96, block: int = 5) -> np.ndarray:
    """Classic semi-global matching as a no-download baseline. Returns disparity in pixels (NaN invalid)."""
    left = cv2.cvtColor(pair.left, cv2.COLOR_RGB2GRAY)
    right = cv2.cvtColor(pair.right, cv2.COLOR_RGB2GRAY)
    matcher = cv2.StereoSGBM_create(
        minDisparity=0, numDisparities=int(np.ceil(max_disparity / 16) * 16), blockSize=block,
        P1=8 * block * block, P2=32 * block * block, uniquenessRatio=10, speckleWindowSize=100, speckleRange=2,
        disp12MaxDiff=1, mode=cv2.STEREO_SGBM_MODE_SGBM_3WAY)
    disparity = matcher.compute(left, right).astype(np.float32) / 16.0
    disparity[disparity <= 0.5] = np.nan
    return disparity


def disparity_to_reference_depth(pair: RectifiedPair, disparity: np.ndarray, out_size: tuple[int, int],
                                 ref_calib: Calibration) -> np.ndarray:
    """Depth (meters) on the reference camera's distorted pixel grid of `out_size` (w, h)."""
    if not pair.reference_is_left:
        # Disparity is defined on the left image, which is the other camera here. Warp it onto the reference
        # (right) view: x_right = x_left - d.
        disparity = _left_to_right(disparity)

    w, h = out_size
    calib = ref_calib.scaled(w, h)
    xs, ys = np.meshgrid(np.arange(w, dtype=np.float64), np.arange(h, dtype=np.float64))
    pts = np.stack([xs.ravel(), ys.ravel()], axis=1)
    undistorted = lut_map(pts, calib.inverse_lut, calib.distortion_center, (w, h))

    rays = np.linalg.solve(calib.K, np.vstack([undistorted.T, np.ones(len(pts))]))   # z = 1 in camera frame
    rect_rays = pair.R1 @ rays
    # Rays are normalized (resolution-free), so P1 projects them straight into working-size rectified pixels.
    proj = pair.P1[:, :3] @ rect_rays
    u = proj[0] / proj[2]
    v = proj[1] / proj[2]
    if pair.rotated:
        u, v = pair.size[1] - 1 - v, u
    xi = np.round(u).astype(int)
    yi = np.round(v).astype(int)
    dh, dw = disparity.shape
    inside = (xi >= 0) & (yi >= 0) & (xi < dw) & (yi < dh)
    d = np.full(len(pts), np.nan)
    d[inside] = disparity[yi[inside], xi[inside]]
    depth_rect = pair.focal * pair.baseline / d
    depth = depth_rect / rect_rays[2]
    return depth.reshape(h, w).astype(np.float32)


def _left_to_right(disparity: np.ndarray) -> np.ndarray:
    h, w = disparity.shape
    out = np.full_like(disparity, np.nan)
    ys, xs = np.nonzero(np.isfinite(disparity))
    d = disparity[ys, xs]
    xr = np.round(xs - d).astype(int)
    ok = (xr >= 0) & (xr < w)
    # Keep the largest disparity (closest surface) when several pixels land on the same spot.
    order = np.argsort(d[ok])
    out[ys[ok][order], xr[ok][order]] = d[ok][order]
    return out
