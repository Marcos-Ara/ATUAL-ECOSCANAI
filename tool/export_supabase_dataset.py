"""Exporta somente amostras aprovadas no Supabase para o formato YOLO."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("work/ecoscan-dataset"))
    parser.add_argument("--url", default=os.environ.get("SUPABASE_URL", ""))
    parser.add_argument(
        "--service-role-key",
        default=os.environ.get("SUPABASE_SERVICE_ROLE_KEY", ""),
    )
    return parser.parse_args()


def fetch(url: str, key: str) -> bytes:
    call = Request(
        url,
        headers={"apikey": key, "Authorization": f"Bearer {key}"},
    )
    try:
        with urlopen(call, timeout=120) as response:
            return response.read()
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Supabase respondeu {error.code}: {detail}") from error


def valid_box(annotation: dict[str, object]) -> tuple[float, float, float, float] | None:
    try:
        left = float(annotation["left"])
        top = float(annotation["top"])
        right = float(annotation["right"])
        bottom = float(annotation["bottom"])
    except (KeyError, TypeError, ValueError):
        return None
    if not (0 <= left < right <= 1 and 0 <= top < bottom <= 1):
        return None
    return ((left + right) / 2, (top + bottom) / 2, right - left, bottom - top)


def safe_name(value: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_-]+", "_", value).strip("_") or "sample"


def main() -> None:
    args = parse_args()
    base_url = args.url.rstrip("/")
    key = args.service_role_key
    if not base_url.startswith("https://") or not key:
        raise ValueError("Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY")
    query = urlencode(
        {
            "select": (
                "user_id,client_sample_id,storage_path,verified_label,annotations"
            ),
            "status": "eq.approved",
            "verified_label": "not.is.null",
        }
    )
    rows = json.loads(
        fetch(f"{base_url}/rest/v1/ecoscan_training_samples?{query}", key)
    )
    prepared: list[tuple[dict[str, object], list[tuple[str, tuple[float, ...]]]]] = []
    class_names: set[str] = set()
    for row in rows:
        annotations = row.get("annotations")
        if not isinstance(annotations, list):
            continue
        parsed = []
        for raw in annotations:
            if not isinstance(raw, dict):
                continue
            label = str(raw.get("label") or row.get("verified_label") or "").strip()
            box = valid_box(raw)
            if label and box:
                parsed.append((label, box))
                class_names.add(label)
        if parsed:
            prepared.append((row, parsed))
    if not prepared:
        raise RuntimeError(
            "Nenhuma amostra aprovada possui annotations com caixas normalizadas."
        )

    classes = sorted(class_names)
    class_ids = {name: index for index, name in enumerate(classes)}
    output = args.output.resolve()
    for split in ("train", "val"):
        (output / "images" / split).mkdir(parents=True, exist_ok=True)
        (output / "labels" / split).mkdir(parents=True, exist_ok=True)

    manifest = []
    for index, (row, annotations) in enumerate(prepared):
        identity = f"{row['user_id']}:{row['client_sample_id']}"
        split = "val" if int(hashlib.sha256(identity.encode()).hexdigest()[:8], 16) % 5 == 0 else "train"
        if len(prepared) > 1 and index == len(prepared) - 1:
            existing_val = any(item["split"] == "val" for item in manifest)
            if not existing_val:
                split = "val"
        file_stem = safe_name(
            f"{str(row['user_id'])[:8]}_{row['client_sample_id']}"
        )
        storage_path = str(row["storage_path"])
        image_url = (
            f"{base_url}/storage/v1/object/authenticated/ecoscan-training/"
            f"{quote(storage_path, safe='/')}"
        )
        image = fetch(image_url, key)
        (output / "images" / split / f"{file_stem}.jpg").write_bytes(image)
        label_lines = [
            f"{class_ids[label]} {x:.8f} {y:.8f} {width:.8f} {height:.8f}"
            for label, (x, y, width, height) in annotations
        ]
        (output / "labels" / split / f"{file_stem}.txt").write_text(
            "\n".join(label_lines) + "\n",
            encoding="utf-8",
        )
        manifest.append(
            {
                "client_sample_id": row["client_sample_id"],
                "split": split,
                "labels": [label for label, _ in annotations],
            }
        )

    yaml_lines = [
        f"path: {json.dumps(str(output), ensure_ascii=False)}",
        "train: images/train",
        "val: images/val",
        "names:",
        *[
            f"  {index}: {json.dumps(name, ensure_ascii=False)}"
            for index, name in enumerate(classes)
        ],
    ]
    (output / "dataset.yaml").write_text(
        "\n".join(yaml_lines) + "\n",
        encoding="utf-8",
    )
    (output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Dataset: {output / 'dataset.yaml'}")
    print(f"Amostras: {len(prepared)} | classes: {len(classes)}")


if __name__ == "__main__":
    main()
