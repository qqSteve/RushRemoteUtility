"""Create a Windows runtime archive and a signed stable-channel manifest."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import zipfile

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


def package(runtime: Path, out: Path, version: str, private_pem: str, pin: str):
    if not re.fullmatch(r"(0|[1-9][0-9]{0,8})(\.(0|[1-9][0-9]{0,8})){2}", version):
        raise ValueError("Expected a release version such as 1.1.0")
    if (runtime / "rush-version.txt").read_text().strip() != version:
        raise ValueError("Runtime version mismatch")
    for required in ("RushRemoteUtility.exe", "librustdesk.dll", "data/flutter_assets"):
        if not (runtime / required).exists():
            raise ValueError(f"Missing runtime component: {required}")
    key = serialization.load_pem_private_key(private_pem.encode(), password=None)
    if not isinstance(key, Ed25519PrivateKey):
        raise ValueError("Expected a dedicated Ed25519 release key")
    public = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    if public != base64.b64decode(pin, validate=True):
        raise ValueError("Release key does not match the client trust anchor")
    out.mkdir(parents=True, exist_ok=True)
    archive = out / "windows-x64.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as target:
        for file in sorted(runtime.rglob("*")):
            if file.is_file():
                target.write(file, file.relative_to(runtime))
    size = archive.stat().st_size
    if size > 300 * 1024 * 1024:
        raise ValueError("Archive exceeds updater limit")
    manifest = json.dumps(dict(product="RushRemoteUtility/windows-x64", version=version,
                               size=size, sha256=hashlib.sha256(archive.read_bytes()).hexdigest()),
                          separators=(",", ":")).encode()
    (out / "stable.bin").write_bytes(key.sign(manifest) + manifest)


if __name__ == "__main__":
    package(Path("rustdesk"), Path("rush-feed"), os.environ["RUSH_RELEASE_VERSION"],
            os.environ["UPDATE_SIGNING_KEY"], os.environ["RUSH_UPDATE_PIN"])
