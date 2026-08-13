import argparse
import hashlib
import os

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageOps


MAX_PIXELS = 50_000_000
MAX_DIMENSION = 12_000


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--worker-sha256", required=True)
    return parser.parse_args()


def preprocess(image):
    resized = image.resize((1024, 1024), Image.Resampling.BILINEAR)
    values = np.asarray(resized, dtype=np.float32) / 255.0
    return values.transpose(2, 0, 1)[None, ...]


def make_cutout(model_path, input_path, output_path):
    image_file = Image.open(input_path)
    if getattr(image_file, "n_frames", 1) != 1:
        raise RuntimeError("Animated images are not supported.")
    image_file.verify()
    image_file = Image.open(input_path)
    image = ImageOps.exif_transpose(image_file)
    if image.width < 1 or image.height < 1 or image.width > MAX_DIMENSION or image.height > MAX_DIMENSION or image.width * image.height > MAX_PIXELS:
        raise RuntimeError("Image dimensions exceed BEN2 limits.")
    image = image.convert("RGB")
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
    with Image.open(output_path) as result:
        if result.format != "PNG" or result.size != original_size:
            raise RuntimeError("Generated output is not a valid PNG.")


if __name__ == "__main__":
    arguments = parse_args()
    with open(__file__, "rb") as worker:
        worker_sha256 = hashlib.sha256(worker.read()).hexdigest()
    if arguments.worker_sha256 != worker_sha256:
        raise RuntimeError("Worker identity verification failed.")
    make_cutout(arguments.model, arguments.input, arguments.output)
