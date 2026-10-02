"""Exporta um detector YOLOE-26n com vocabulário estático do EcoScan.

O checkpoint de origem é pré-treinado. O script fixa as classes por prompt e
gera um LiteRT compatível com o plugin Flutter oficial; não substitui o futuro
treinamento supervisionado com imagens reais do EcoScan.
"""

from __future__ import annotations

import argparse
import json

from validate_yoloe_model import validate_model
import shutil
from pathlib import Path

from ultralytics import YOLOE


ROOT = Path(__file__).resolve().parents[1]
ECOSCAN_CLASSES = [item["label"] for item in json.loads(
    (ROOT / "assets/data/yoloe_classes.json").read_text()
)["classes"]]



def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default="yoloe-26n-seg.pt")
    parser.add_argument("--output", type=Path, default=Path("assets/models"))
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--keep-profile", action="store_true")
    return parser.parse_args()


def locate_tflite(exported: Path) -> Path:
    if exported.is_file() and exported.suffix == ".tflite":
        return exported
    candidates = sorted(exported.rglob("*.tflite")) if exported.exists() else []
    if not candidates:
        raise FileNotFoundError(f"Nenhum .tflite encontrado em {exported}")
    preferred = [
        item
        for item in candidates
        if "w8a32" in item.name.lower() 
    ]
    return (preferred or candidates)[0]


def main() -> None:
    args = parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    profile = args.output / "ecoscan_yoloe26n_prompts.npz"

    prompted = YOLOE(args.source)
    prompted.set_classes(ECOSCAN_CLASSES)
    prompted.save_prompt_embeddings(str(profile))

    detector = YOLOE("yoloe-26n.yaml").load(args.source)
    detector.load_prompt_embeddings(str(profile))
    exported = Path(
        str(
            detector.export(
                format="litert",
                imgsz=args.imgsz,
                nms=None,
                quantize="w8a32",
            )
        )
    )
    source_file = locate_tflite(exported)
    destination = args.output / "ecoscan_yoloe26n_w8a32.tflite"
    shutil.copy2(source_file, destination)
    manifest = validate_model(destination, invoke=True)
    (args.output / "model_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    )
    if not args.keep_profile:
        profile.unlink(missing_ok=True)
    print(f"Modelo gerado: {destination}")
    print(f"Classes fixadas: {len(ECOSCAN_CLASSES)}")


if __name__ == "__main__":
    main()
