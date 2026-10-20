"""Compare depth methods on DepthKit Lab Captures.

    python -m depthlab.evaluate data/ --methods sgbm apple_stereo depth_pro prompt_da foundation_stereo

Everything is compared on the wide camera's pixel grid at the LiDAR depth map's resolution:
- Reference: the LiDAR depth camera. It is Apple's processed LiDAR depth, not laser ground truth, so the tape
  measure (meta.json -> tapeDistanceMeters, aimed at the image center) is reported as an absolute check.
- prompt_da takes LiDAR as input, so its error against LiDAR is not independent; judge it on the tape
  distance and on detail.
Captures whose wide image is dark can also be evaluated after low-light enhancement (--enhance).
"""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import numpy as np

from . import low_light, metrics, stereo
from .io import Capture, list_captures, load_capture

ALL_METHODS = ["apple_stereo", "sgbm", "foundation_stereo", "depth_pro", "prompt_da"]


class Evaluator:
    def __init__(self, methods: list[str]):
        self.methods = methods
        self._models: dict[str, object] = {}

    def model(self, name: str):
        if name not in self._models:
            from . import models
            self._models[name] = {"depth_pro": models.DepthPro, "prompt_da": models.PromptDA,
                                  "foundation_stereo": models.FoundationStereo}[name]()
        return self._models[name]

    def predict(self, capture: Capture, method: str, enhance: bool) -> np.ndarray | None:
        """Depth in meters on the wide camera grid at LiDAR resolution, or None if not applicable."""
        if capture.lidar is None or "wide" not in capture.images:
            return None
        gh, gw = capture.lidar.depth.shape
        wide = capture.images["wide"]
        if enhance:
            wide = low_light.clahe(wide)

        if method == "apple_stereo":
            return None if capture.apple_stereo is None else metrics.resize_depth(capture.apple_stereo.depth, (gw, gh))

        if method in ("sgbm", "foundation_stereo"):
            if "ultrawide" not in capture.images or not {"wide", "ultrawide"} <= capture.calibrations.keys():
                return None
            other = capture.images["ultrawide"]
            if enhance:
                other = low_light.clahe(other)
            pair = stereo.rectify(wide, capture.calibrations["wide"], other, capture.calibrations["ultrawide"])
            disparity = (stereo.sgbm_disparity(pair) if method == "sgbm"
                         else self.model("foundation_stereo")(pair.left, pair.right))
            return stereo.disparity_to_reference_depth(pair, disparity, (gw, gh), capture.calibrations["wide"])

        if method == "depth_pro":
            focal = capture.calibrations["wide"].scaled(wide.shape[1], wide.shape[0]).K[0, 0] \
                if "wide" in capture.calibrations else None
            return metrics.resize_depth(self.model("depth_pro")(wide, focal), (gw, gh))

        if method == "prompt_da":
            return metrics.resize_depth(self.model("prompt_da")(wide, capture.lidar.depth), (gw, gh))

        raise ValueError(method)


def evaluate(root: Path, methods: list[str], enhance: bool, out: Path) -> list[dict]:
    out.mkdir(parents=True, exist_ok=True)
    evaluator = Evaluator(methods)
    rows = []
    for folder in list_captures(root):
        capture = load_capture(folder)
        if capture.lidar is None:
            print(f"skip {folder.name}: no LiDAR depth")
            continue
        gt = capture.lidar.depth
        dark = "wide" in capture.images and low_light.is_dark(capture.images["wide"])
        predictions = {}
        for method in methods:
            try:
                pred = evaluator.predict(capture, method, enhance and dark)
            except Exception as error:  # one failing model shouldn't stop the run
                print(f"{folder.name} {method}: {error}")
                continue
            if pred is None:
                continue
            predictions[method] = pred
            np.save(out / f"{folder.name}__{method}.npy", pred)
            row = {"capture": folder.name, "label": capture.label, "dark": dark, "method": method,
                   **metrics.errors(pred, gt),
                   "center_m": metrics.center_depth(pred), "lidar_center_m": metrics.center_depth(gt),
                   "tape_m": capture.tape_distance}
            row["center_vs_tape_m"] = (row["center_m"] - row["tape_m"]) if row["tape_m"] else None
            rows.append(row)
            print(json.dumps({k: (round(v, 4) if isinstance(v, float) else v) for k, v in row.items()}))
        np.save(out / f"{folder.name}__lidar.npy", gt)

    if rows:
        with open(out / "results.csv", "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("root", type=Path, help="folder of Lab Capture folders")
    parser.add_argument("--methods", nargs="+", default=["apple_stereo", "sgbm"], choices=ALL_METHODS)
    parser.add_argument("--enhance", action="store_true", help="apply low-light enhancement to dark captures")
    parser.add_argument("--out", type=Path, default=Path("results"))
    args = parser.parse_args()
    evaluate(args.root, args.methods, args.enhance, args.out)


if __name__ == "__main__":
    main()
