import argparse
import os

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageOps


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def preprocess(image):
    resized = image.resize((1024, 1024), Image.Resampling.BILINEAR)
    values = np.asarray(resized, dtype=np.float32) / 255.0
    return values.transpose(2, 0, 1)[None, ...]


def make_cutout(model_path, input_path, output_path):
    image = ImageOps.exif_transpose(Image.open(input_path)).convert("RGB")
    original_size = image.size
    session_options = ort.SessionOptions()
    session_options.intra_op_num_threads = max(1, min(os.cpu_count() or 1, 8))
    session_options.inter_op_num_threads = 1
    session_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    session = ort.InferenceSession(
        model_path,
        sess_options=session_options,
        providers=["CPUExecutionProvider"],
    )

    input_name = session.get_inputs()[0].name
    prediction = np.asarray(session.run(None, {input_name: preprocess(image)})[0])
    mask = np.squeeze(prediction).astype(np.float32)
    if mask.ndim != 2:
        raise RuntimeError(f"Expected a 2D mask, got shape {prediction.shape}.")
    minimum = float(mask.min())
    maximum = float(mask.max())
    spread = maximum - minimum
    mask = np.zeros_like(mask) if spread <= 1e-6 else (mask - minimum) / spread
    mask = np.clip(mask * 255.0, 0, 255).astype(np.uint8)
    alpha = Image.fromarray(mask).resize(original_size, Image.Resampling.BILINEAR)
    output = image.convert("RGBA")
    output.putalpha(alpha)
    output.save(output_path, format="PNG")


if __name__ == "__main__":
    arguments = parse_args()
    make_cutout(arguments.model, arguments.input, arguments.output)
