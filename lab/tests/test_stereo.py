"""End-to-end stereo check on a synthetic scene: a textured plane seen by two pinhole cameras ~1 cm apart."""
import numpy as np
import pytest

cv2 = pytest.importorskip("cv2")

from depthlab import stereo  # noqa: E402
from test_geometry import make_calib  # noqa: E402

SIZE = (640, 480)


def texture(x, y):
    """Smooth random texture indexed by world coordinates (meters)."""
    rng = np.random.default_rng(42)
    freqs = rng.uniform(20, 120, (12, 2))
    phases = rng.uniform(0, 2 * np.pi, 12)
    value = sum(np.sin(f[0] * x + f[1] * y + p) for f, p in zip(freqs, phases))
    return np.clip(128 + 18 * value, 0, 255).astype(np.uint8)


def render(calib, plane_z):
    """Image of the plane Z = plane_z (reference frame) seen by `calib`."""
    w, h = SIZE
    xs, ys = np.meshgrid(np.arange(w) + 0.0, np.arange(h) + 0.0)
    rays = np.linalg.solve(calib.K, np.stack([xs.ravel(), ys.ravel(), np.ones(xs.size)]))
    # Camera frame -> reference frame: X_ref = R^T (X_cam - t)
    origin = -calib.R.T @ calib.t_m
    dirs = calib.R.T @ rays
    s = (plane_z - origin[2]) / dirs[2]
    pts = origin[:, None] + dirs * s
    gray = texture(pts[0], pts[1]).reshape(h, w)
    return np.repeat(gray[..., None], 3, axis=2)


@pytest.mark.parametrize("offset_mm", [(0, 12, 0), (0, -12, 0), (12, 0, 0), (-12, 0, 0)])
def test_recovers_plane_depth(offset_mm):
    plane = 0.5
    ref = make_calib(600, SIZE)
    other = make_calib(420, SIZE, t_mm=offset_mm)     # wider lens, like the ultra-wide
    pair = stereo.rectify(render(ref, plane), ref, render(other, plane), other, work_width=SIZE[0])
    assert np.isclose(pair.baseline, 0.012)
    assert pair.rotated == (offset_mm[1] != 0)

    disparity = stereo.sgbm_disparity(pair, max_disparity=48)
    depth = stereo.disparity_to_reference_depth(pair, disparity, (160, 120), ref)
    center = depth[40:80, 50:110]
    values = center[np.isfinite(center)]
    assert values.size > 0.5 * center.size
    assert abs(np.median(values) - plane) < 0.03
