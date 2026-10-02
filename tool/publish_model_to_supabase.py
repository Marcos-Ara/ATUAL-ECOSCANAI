"""Publica um modelo EcoScan versionado no Supabase Storage e no registro.

Execute apenas em uma estação administrativa. A service-role nunca deve ser
incluída no Flutter, em arquivos versionados ou no pacote do aplicativo.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

from validate_yoloe_model import validate_model


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--platform", choices=("android", "ios"), required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--notes", default="")
    parser.add_argument("--url", default=os.environ.get("SUPABASE_URL", ""))
    parser.add_argument(
        "--service-role-key",
        default=os.environ.get("SUPABASE_SERVICE_ROLE_KEY", ""),
    )
    return parser.parse_args()


def request(
    url: str,
    key: str,
    *,
    method: str,
    data: bytes | None = None,
    content_type: str = "application/json",
    prefer: str | None = None,
    extra_headers: dict[str, str] | None = None,
) -> bytes:
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": content_type,
    }
    if prefer:
        headers["Prefer"] = prefer
    if extra_headers:
        headers.update(extra_headers)
    call = Request(url, data=data, method=method, headers=headers)
    try:
        with urlopen(call, timeout=180) as response:
            return response.read()
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Supabase respondeu {error.code}: {detail}") from error


def publish_model(
    *,
    model: Path,
    platform: str,
    version: str,
    notes: str,
    supabase_url: str,
    service_role_key: str,
) -> dict[str, object]:
    model = model.resolve()
    if not model.is_file():
        raise FileNotFoundError(model)
    lowered = model.name.lower()
    if platform == "android" and not lowered.endswith(".tflite"):
        raise ValueError("Android exige um arquivo .tflite")
    if platform == "ios" and not lowered.endswith(".mlpackage.zip"):
        raise ValueError("iOS exige um arquivo .mlpackage.zip")
    if platform == "android":
        validate_model(model)
    base_url = supabase_url.rstrip("/")
    if not base_url.startswith("https://") or not service_role_key:
        raise ValueError("Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY")

    payload = model.read_bytes()
    digest = hashlib.sha256(payload).hexdigest()
    safe_version = "".join(
        char if char.isalnum() or char in ".-_" else "_" for char in version
    )
    object_path = f"{platform}/{safe_version}/{model.name}"
    content_type = "application/zip" if platform == "ios" else "application/octet-stream"
    upload_url = (
        f"{base_url}/storage/v1/object/ecoscan-models/"
        f"{quote(object_path, safe='/')}"
    )
    request(
        upload_url,
        service_role_key,
        method="POST",
        data=payload,
        content_type=content_type,
        prefer="return=minimal",
        extra_headers={"x-upsert": "true"},
    )

    row = {
        "platform": platform,
        "version": version,
        "bucket_id": "ecoscan-models",
        "object_path": object_path,
        "sha256": digest,
        "byte_size": len(payload),
        "is_active": True,
        "notes": notes or None,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    registry_url = (
        f"{base_url}/rest/v1/ecoscan_model_releases?"
        "on_conflict=platform,version"
    )
    response = request(
        registry_url,
        service_role_key,
        method="POST",
        data=json.dumps(row).encode(),
        prefer="resolution=merge-duplicates,return=representation",
    )
    rows = json.loads(response or b"[]")
    filter_query = urlencode(
        {
            "platform": f"eq.{platform}",
            "is_active": "eq.true",
            "version": f"neq.{version}",
        }
    )
    request(
        f"{base_url}/rest/v1/ecoscan_model_releases?{filter_query}",
        service_role_key,
        method="PATCH",
        data=json.dumps({"is_active": False}).encode(),
        prefer="return=minimal",
    )
    return rows[0] if rows else row


def main() -> None:
    args = parse_args()
    release = publish_model(
        model=args.model,
        platform=args.platform,
        version=args.version,
        notes=args.notes,
        supabase_url=args.url,
        service_role_key=args.service_role_key,
    )
    print(json.dumps(release, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
