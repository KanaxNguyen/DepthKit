# DepthKit Lab: multi-camera depth on iPhone

How well can an iPhone 15 Pro Max estimate depth from its **cameras alone**, compared with its **LiDAR**, by day and at night? This lab compares five methods on the same tripod captures.

| Method | Input | Reference |
|---|---|---|
| `apple_stereo` | wide + ultra-wide | Apple's dual-camera disparity depth (AVFoundation) |
| `sgbm` | wide + ultra-wide, rectified here | Semi-global matching (OpenCV), no download |
| `foundation_stereo` | wide + ultra-wide, rectified here | Wen et al., *FoundationStereo: Zero-Shot Stereo Matching*, CVPR 2025 |
| `depth_pro` | wide only | Bochkovskii et al., *Depth Pro: Sharp Monocular Metric Depth in Less Than a Second*, ICLR 2025 |
| `prompt_da` | wide + LiDAR prompt | Lin et al., *Prompting Depth Anything for 4K Resolution Accurate Metric Depth Estimation*, CVPR 2025 |

The reference is the **LiDAR depth camera**, which is Apple's processed LiDAR depth rather than laser ground truth. A **tape-measured distance** to the image center is the absolute check. `prompt_da` uses LiDAR as input, so its error against LiDAR is not independent; judge it by the tape distance and by visible detail.

## 1. Capture (iPhone)

1. Open **DepthKit › Settings › Developer › Lab Capture**. You need an iPhone Pro with LiDAR.
2. Put the iPhone on a tripod. Enter a label such as `box-1.5m-day`, and the tape distance from the phone to whatever is at the center of the view.
3. Tap **Capture**. In about 4 seconds the app saves:
   - every back camera (`ultrawide.jpg`, `wide.jpg`, `tele.jpg`) with calibration files containing intrinsics, extrinsics in millimeters, and lens distortion tables
   - Apple stereo depth (`apple_stereo_*`)
   - LiDAR depth (`lidar_*`)

   Everything is in sensor orientation (landscape). Ignore the EXIF orientation.
4. A suggested set:
   - distances 0.5, 1, 1.5, 2, 3 m
   - each distance twice: room lights on, and lights off (dark)
   - a textured target and a plain wall

## 2. Analyze (Mac)

```bash
cd lab
uv sync                      # numpy, OpenCV, matplotlib, Jupyter
./pull_captures.sh           # copies Documents/LabCaptures from the USB-connected iPhone into data/
uv run pytest                # geometry + synthetic stereo checks
uv run python -m depthlab.evaluate data --methods apple_stereo sgbm
uv run jupyter lab notebooks/evaluate.ipynb
```

Learned models are optional and large:

```bash
./setup.sh depth_pro          # ~1.9 GB checkpoint from Apple
./setup.sh prompt_da          # weights from Hugging Face on first run
./setup.sh foundation_stereo  # code only; weights are a manual Google Drive download (see its README)
```

FoundationStereo is released for NVIDIA GPUs. On an M1 Mac it may run on CPU or MPS slowly, or need a CUDA machine such as Colab.

## How stereo works here

`depthlab/stereo.py` handles the stereo pipeline:

1. Undistorts both images with Apple's lookup tables (`calib.lut_map` ports Apple's `lensDistortionPoint`).
2. Rectifies them with the relative pose from the extrinsics.
3. Rotates the pair when the cameras are stacked vertically, and orders it so the left image is the left camera.
4. Maps the depth back onto the wide camera's original pixel grid, the same grid as LiDAR.

The tests check this end to end on synthetic scenes with horizontal and vertical baselines.

With a baseline of about 1 cm, disparity at 3 m is only a few pixels. Expect stereo error to grow quickly with distance; measuring that curve is one of the results.

## Night

LiDAR and TrueDepth emit their own infrared light, so they keep working in the dark; RGB stereo and monocular models do not. Pass `--enhance` to lift dark captures with CLAHE before the RGB methods (`depthlab/low_light.py`). Learned enhancers worth adding next:

- Zero-DCE (CVPR 2020)
- Retinexformer (ICCV 2023)
- a RAW pipeline in the style of *Learning to See in the Dark* (CVPR 2018)
