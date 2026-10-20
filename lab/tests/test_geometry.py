import numpy as np
import pytest

from depthlab.calib import Calibration, lut_map, relative_pose
from depthlab.metrics import center_depth, errors, resize_depth


def make_calib(fx, size, R=np.eye(3), t_mm=(0, 0, 0), lut=None, inverse_lut=None):
    w, h = size
    lut = np.zeros(16) if lut is None else lut
    inverse_lut = np.zeros(16) if inverse_lut is None else inverse_lut
    return Calibration.from_dict({
        "intrinsicMatrix": [[fx, 0, w / 2], [0, fx, h / 2], [0, 0, 1]],
        "intrinsicReferenceDimensions": [w, h],
        "extrinsicMatrix": np.hstack([R, np.asarray(t_mm, float)[:, None]]).tolist(),
        "pixelSizeMillimeters": 0.001,
        "lensDistortionCenter": [w / 2, h / 2],
        "lensDistortionLookupTable": list(lut),
        "inverseLensDistortionLookupTable": list(inverse_lut),
    })


def test_extrinsic_translation_is_converted_to_meters():
    c = make_calib(1000, (4032, 3024), t_mm=(12, 0, 0))
    assert np.allclose(c.t_m, [0.012, 0, 0])


def test_scaled_intrinsics():
    c = make_calib(3000, (4032, 3024)).scaled(1008, 756)
    assert np.isclose(c.K[0, 0], 750) and np.isclose(c.K[0, 2], 504) and np.isclose(c.K[1, 2], 378)


def test_relative_pose_composes_extrinsics():
    angle = np.deg2rad(5)
    Ra = np.array([[np.cos(angle), -np.sin(angle), 0], [np.sin(angle), np.cos(angle), 0], [0, 0, 1]])
    a = make_calib(1000, (100, 100), R=Ra, t_mm=(1, 2, 3))
    b = make_calib(1000, (100, 100), t_mm=(10, 0, 0))
    R, t = relative_pose(a, b)
    X_ref = np.array([0.3, -0.2, 1.5])
    X_a = a.R @ X_ref + a.t_m
    X_b = b.R @ X_ref + b.t_m
    assert np.allclose(R @ X_a + t, X_b)


def test_lut_forward_then_inverse_is_identity():
    m = np.linspace(0, 0.05, 32)               # barrel-like growth toward the corners
    size = (400, 300)
    # Keep distorted points inside the image, where Apple's tables are defined.
    pts = np.random.default_rng(0).uniform([50, 40], [350, 260], (200, 2))
    center = np.array([200.0, 150.0])
    distorted = lut_map(pts, m, center, size)
    # Build the inverse table numerically on the same radius samples.
    r_max = np.hypot(200, 150)
    radii = np.linspace(0, r_max, 400)
    forward_r = radii * (1 + np.interp(radii / r_max, np.linspace(0, 1, len(m)), m))
    inv_samples = np.interp(radii, forward_r, radii)
    inv = np.where(radii > 0, inv_samples / np.maximum(radii, 1e-9) - 1, 0)
    back = lut_map(distorted, inv, center, size)
    assert np.allclose(back, pts, atol=0.05)


def test_metrics():
    gt = np.full((4, 4), 2.0)
    pred = gt * 1.1
    pred[0, 0] = np.nan
    e = errors(pred, gt)
    assert e["n"] == 15
    assert np.isclose(e["abs_rel"], 0.1)
    assert e["delta1"] == 1.0
    assert center_depth(gt) == 2.0
    assert resize_depth(np.arange(4.0).reshape(2, 2), (4, 4)).shape == (4, 4)
