"""Ajusta o YOLOE-26n em um dataset YOLO revisado e exporta LiteRT."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

from ultralytics import YOLOE
from ultralytics.models.yolo.yoloe import YOLOEPETrainer


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--source", default="yoloe-26n-seg.pt")
    parser.add_argument("--architecture", default="yoloe-26n.yaml")
    parser.add_argument("--output", type=Path, default=Path("work/yoloe-training"))
    parser.add_argument("--epochs", type=int, default=80)
    parser.add_argument("--patience", type=int, default=10)
    parser.add_argument("--batch", type=int, default=8)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--device", default="")
    parser.add_argument("--skip-validation", action="store_true")
    return parser.parse_args()


def locate_tflite(exported: Path) -> Path:
    if exported.is_file() and exported.suffix == ".tflite":
        return exported
    candidates = sorted(exported.rglob("*.tflite")) if exported.exists() else []
    if not candidates:
        raise FileNotFoundError(f"Nenhum .tflite encontrado em {exported}")
    preferred = [item for item in candidates if "w8a32" in item.name.lower()]
    return (preferred or candidates)[0]


def main() -> None:
    args = parse_args()
    data = args.data.resolve()
    if not data.is_file():
        raise FileNotFoundError(data)
    args.output.mkdir(parents=True, exist_ok=True)
    train_kwargs = {
        "data": str(data),
        "epochs": args.epochs,
        "patience": args.patience,
        "batch": args.batch,
        "imgsz": args.imgsz,
        "trainer": YOLOEPETrainer,
        "project": str(args.output / "runs"),
        "name": "ecoscan-yoloe26n",
    }
    if args.device:
        train_kwargs["device"] = args.device

    model = YOLOE(args.architecture).load(args.source)
    model.train(**train_kwargs)
    trainer = model.trainer
    if trainer is None:
        raise RuntimeError("O treinamento terminou sem expor o checkpoint.")
    best = Path(str(trainer.best))
    if not best.is_file():
        raise FileNotFoundError(f"Checkpoint best.pt não encontrado: {best}")

    trained = YOLOE(str(best))
    if not args.skip_validation:
        trained.val(data=str(data), imgsz=args.imgsz)
    exported = Path(
        str(
            trained.export(
                format="litert",
                imgsz=args.imgsz,
                nms=None,
                quantize="w8a32",
            )
        )
    )
    source_file = locate_tflite(exported)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    destination = args.output / f"ecoscan_yoloe26n_{timestamp}_w8a32.tflite"
    shutil.copy2(source_file, destination)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    manifest = {
        "model": str(destination),
        "sha256": digest,
        "bytes": destination.stat().st_size,
        "source": args.source,
        "architecture": args.architecture,
        "dataset": str(data),
        "epochs": args.epochs,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    (args.output / f"{destination.stem}.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
