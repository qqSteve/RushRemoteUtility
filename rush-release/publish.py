"""Run on VPS as an unprivileged deployment account. Publish manifest last."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import sys


def number(version):
    if not re.fullmatch(r"(0|[1-9][0-9]{0,8})(\.(0|[1-9][0-9]{0,8})){2}", version):
        raise ValueError("Invalid release version")
    return tuple(map(int, version.split(".")))


def publish(root, incoming):
    archive = incoming / "windows-x64.zip"
    envelope = (incoming / "stable.bin").read_bytes()
    manifest = json.loads(envelope[64:])
    version = manifest["version"]
    ver = number(version)
    if (manifest["product"] != "RushRemoteUtility/windows-x64" or
            manifest["size"] != archive.stat().st_size or
            manifest["sha256"] != hashlib.sha256(archive.read_bytes()).hexdigest()):
        raise ValueError("Incomplete release")
    with (root / ".publish.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        stable = root / "stable.bin"
        if stable.exists():
            current = stable.read_bytes()
            if current == envelope:
                return
            if ver <= number(json.loads(current[64:])["version"]):
                raise ValueError("Published versions are immutable; select a newer tag")
        dest = root / ("v" + version)
        dest.mkdir(exist_ok=True)
        final = dest / archive.name
        if final.exists() and hashlib.sha256(final.read_bytes()).hexdigest() != manifest["sha256"]:
            raise ValueError("Version already used")
        os.replace(archive, final)
        os.replace(incoming / "stable.bin", stable)


if __name__ == "__main__":
    publish(Path("/srv/rush-updates"), Path(sys.argv[1]))
