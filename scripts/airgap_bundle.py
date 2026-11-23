#!/usr/bin/env python3
"""Build, verify and load an offline container image bundle.

Connected side:     airgap_bundle.py create --images images.txt --out bundle
Disconnected side:  airgap_bundle.py verify --bundle bundle
                    airgap_bundle.py load --bundle bundle --registry harbor.example.internal/library

Images are copied with skopeo into an OCI layout directory per image. A
manifest.json records the sha256 of every file in the bundle so tampering or
a truncated transfer is caught before anything is pushed to the registry.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

MANIFEST_NAME = "manifest.json"
IMAGES_DIR = "images"
MANIFEST_VERSION = 1


class BundleError(Exception):
    """Raised for any error the user needs to act on."""


# --------------------------------------------------------------------------
# images.txt parsing
# --------------------------------------------------------------------------


def parse_image_ref(ref: str) -> dict:
    """Split ``host/path/name:tag`` into parts. A tag is required."""
    if "@" in ref:
        raise BundleError(f"digest references are not supported, use a tag: {ref}")
    last = ref.rsplit("/", 1)[-1]
    if ":" not in last:
        raise BundleError(f"image needs an explicit tag: {ref}")
    name, tag = ref.rsplit(":", 1)
    if not tag:
        raise BundleError(f"empty tag: {ref}")
    parts = name.split("/")
    first = parts[0]
    if "." in first or ":" in first or first == "localhost":
        host, path = first, "/".join(parts[1:])
    else:
        host, path = "docker.io", name
    if not path:
        raise BundleError(f"missing repository path: {ref}")
    if host == "docker.io" and "/" not in path:
        path = f"library/{path}"
    return {"ref": ref, "host": host, "path": path, "tag": tag}


def read_images(images_file: Path) -> list[dict]:
    if not images_file.is_file():
        raise BundleError(f"images file not found: {images_file}")
    refs = []
    for raw in images_file.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            refs.append(parse_image_ref(line))
    if not refs:
        raise BundleError(f"no images listed in {images_file}")
    seen = set()
    for item in refs:
        key = (item["host"], item["path"], item["tag"])
        if key in seen:
            raise BundleError(f"duplicate image: {item['ref']}")
        seen.add(key)
    return refs


def layout_dir_name(item: dict) -> str:
    """Directory name inside images/ for one image."""
    raw = f"{item['host']}/{item['path']}_{item['tag']}"
    return raw.replace("/", "_").replace(":", "_")


# --------------------------------------------------------------------------
# hashing and manifest
# --------------------------------------------------------------------------


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def hash_tree(root: Path) -> dict[str, str]:
    """Map relative posix path to sha256 for every file under root/images."""
    files: dict[str, str] = {}
    base = root / IMAGES_DIR
    if not base.is_dir():
        return files
    for path in sorted(base.rglob("*")):
        if path.is_file():
            files[path.relative_to(root).as_posix()] = sha256_file(path)
    return files


def manifest_digest_of_layout(layout: Path) -> str:
    """Return the manifest digest recorded in an OCI layout index.json."""
    index_path = layout / "index.json"
    try:
        index = json.loads(index_path.read_text())
        return index["manifests"][0]["digest"]
    except (OSError, ValueError, KeyError, IndexError) as exc:
        raise BundleError(f"cannot read manifest digest from {index_path}: {exc}")


def build_manifest(bundle: Path, items: list[dict]) -> dict:
    entries = []
    for item in items:
        rel = f"{IMAGES_DIR}/{layout_dir_name(item)}"
        entries.append(
            {
                "source": item["ref"],
                "repository": item["path"],
                "tag": item["tag"],
                "layout": rel,
                "manifest_digest": manifest_digest_of_layout(bundle / rel),
            }
        )
    return {
        "version": MANIFEST_VERSION,
        "images": entries,
        "files": hash_tree(bundle),
    }


def verify_bundle(bundle: Path) -> dict:
    """Check every file against manifest.json. Return the manifest."""
    manifest_path = bundle / MANIFEST_NAME
    if not manifest_path.is_file():
        raise BundleError(f"{manifest_path} is missing")
    try:
        manifest = json.loads(manifest_path.read_text())
        expected = manifest["files"]
        manifest["images"]
    except (ValueError, KeyError) as exc:
        raise BundleError(f"manifest is not valid: {exc}")

    actual = hash_tree(bundle)
    problems = []
    for rel, digest in sorted(expected.items()):
        if rel not in actual:
            problems.append(f"missing: {rel}")
        elif actual[rel] != digest:
            problems.append(f"modified: {rel}")
    for rel in sorted(set(actual) - set(expected)):
        problems.append(f"unexpected file: {rel}")
    if problems:
        raise BundleError("bundle verification failed\n  " + "\n  ".join(problems))
    return manifest


# --------------------------------------------------------------------------
# skopeo
# --------------------------------------------------------------------------


def skopeo_bin(override: str | None) -> str:
    return override or os.environ.get("SKOPEO", "skopeo")


def run(cmd: list[str], dry_run: bool) -> None:
    print("+ " + " ".join(cmd))
    if dry_run:
        return
    try:
        subprocess.run(cmd, check=True)
    except FileNotFoundError:
        raise BundleError(f"command not found: {cmd[0]}")
    except subprocess.CalledProcessError as exc:
        raise BundleError(f"command failed with exit code {exc.returncode}: {cmd[0]}")


def write_tarball(bundle: Path, tar_path: Path) -> str:
    with tarfile.open(tar_path, "w") as tar:
        tar.add(bundle / MANIFEST_NAME, arcname=MANIFEST_NAME)
        tar.add(bundle / IMAGES_DIR, arcname=IMAGES_DIR)
    digest = sha256_file(tar_path)
    Path(f"{tar_path}.sha256").write_text(f"{digest}  {tar_path.name}\n")
    return digest


# --------------------------------------------------------------------------
# commands
# --------------------------------------------------------------------------


def cmd_create(args: argparse.Namespace) -> int:
    items = read_images(Path(args.images))
    bundle = Path(args.out)
    skopeo = skopeo_bin(args.skopeo)
    if not args.dry_run:
        if (bundle / IMAGES_DIR).exists():
            raise BundleError(f"{bundle / IMAGES_DIR} already exists, use a new --out directory")
        (bundle / IMAGES_DIR).mkdir(parents=True)

    for item in items:
        dest = f"{bundle / IMAGES_DIR / layout_dir_name(item)}"
        cmd = [skopeo]
        if args.platform:
            os_name, _, arch = args.platform.partition("/")
            cmd += ["--override-os", os_name, "--override-arch", arch]
        cmd += ["copy", "--retry-times", "3"]
        if args.all:
            cmd.append("--all")
        cmd += [f"docker://{item['ref']}", f"oci:{dest}:{item['tag']}"]
        run(cmd, args.dry_run)

    if args.dry_run:
        print(f"dry run: {len(items)} image(s) would be copied to {bundle}")
        return 0

    manifest = build_manifest(bundle, items)
    (bundle / MANIFEST_NAME).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"wrote {bundle / MANIFEST_NAME}: {len(items)} image(s), {len(manifest['files'])} file(s)")

    if args.tarball:
        tar_path = Path(args.tarball)
        digest = write_tarball(bundle, tar_path)
        print(f"wrote {tar_path} sha256={digest}")
    return 0


def resolve_bundle(path: str, scratch: list[str]) -> Path:
    """Accept a bundle directory or a .tar with a .sha256 sidecar."""
    target = Path(path)
    if target.is_dir():
        return target
    if target.is_file():
        sidecar = Path(f"{target}.sha256")
        if not sidecar.is_file():
            raise BundleError(f"{sidecar} is missing")
        expected = sidecar.read_text().split()[0]
        actual = sha256_file(target)
        if expected != actual:
            raise BundleError(f"tarball checksum mismatch: expected {expected}, got {actual}")
        tmp = tempfile.mkdtemp(prefix="airgap-bundle-")
        scratch.append(tmp)
        with tarfile.open(target) as tar:
            tar.extractall(tmp, filter="data")
        return Path(tmp)
    raise BundleError(f"bundle not found: {path}")


def cmd_verify(args: argparse.Namespace) -> int:
    scratch: list[str] = []
    try:
        bundle = resolve_bundle(args.bundle, scratch)
        manifest = verify_bundle(bundle)
    finally:
        for tmp in scratch:
            shutil.rmtree(tmp, ignore_errors=True)
    print(f"ok: {len(manifest['images'])} image(s), {len(manifest['files'])} file(s) verified")
    return 0


def cmd_load(args: argparse.Namespace) -> int:
    scratch: list[str] = []
    try:
        bundle = resolve_bundle(args.bundle, scratch)
        manifest = verify_bundle(bundle)
        print(f"bundle verified: {len(manifest['images'])} image(s)")
        skopeo = skopeo_bin(args.skopeo)
        registry = args.registry.rstrip("/")
        for entry in manifest["images"]:
            cmd = [skopeo, "copy", "--retry-times", "3"]
            if args.all:
                cmd.append("--all")
            if args.authfile:
                cmd += ["--dest-authfile", args.authfile]
            if not args.tls_verify:
                cmd.append("--dest-tls-verify=false")
            cmd += [
                f"oci:{bundle / entry['layout']}:{entry['tag']}",
                f"docker://{registry}/{entry['repository']}:{entry['tag']}",
            ]
            run(cmd, args.dry_run)
        if args.dry_run:
            print(f"dry run: {len(manifest['images'])} image(s) would be pushed to {registry}")
    finally:
        for tmp in scratch:
            shutil.rmtree(tmp, ignore_errors=True)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="airgap-bundle", description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)

    create = sub.add_parser("create", help="copy images into a bundle (connected side)")
    create.add_argument("--images", required=True, help="file with one image reference per line")
    create.add_argument("--out", required=True, help="new bundle directory")
    create.add_argument("--tarball", help="also write this tar file and a .sha256 sidecar")
    create.add_argument("--all", action="store_true", help="copy every architecture")
    create.add_argument("--platform", help="os/arch to pull, for example linux/amd64")
    create.add_argument("--skopeo", help="skopeo binary (default: $SKOPEO or skopeo)")
    create.add_argument("--dry-run", action="store_true", help="print commands, no network")
    create.set_defaults(func=cmd_create)

    verify = sub.add_parser("verify", help="check a bundle against its manifest")
    verify.add_argument("--bundle", required=True, help="bundle directory or .tar")
    verify.set_defaults(func=cmd_verify)

    load = sub.add_parser("load", help="verify then push to a registry (disconnected side)")
    load.add_argument("--bundle", required=True, help="bundle directory or .tar")
    load.add_argument("--registry", required=True, help="for example harbor.example.internal/library")
    load.add_argument("--authfile", help="skopeo auth file for the destination")
    load.add_argument("--no-tls-verify", dest="tls_verify", action="store_false")
    load.add_argument("--all", action="store_true", help="push every architecture")
    load.add_argument("--skopeo", help="skopeo binary (default: $SKOPEO or skopeo)")
    load.add_argument("--dry-run", action="store_true", help="verify and print commands only")
    load.set_defaults(func=cmd_load)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except BundleError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
