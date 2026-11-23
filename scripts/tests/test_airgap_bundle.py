import json
from pathlib import Path

import pytest

import airgap_bundle as ab


def make_bundle(tmp_path, stub, images_file, extra=()):
    out = tmp_path / "bundle"
    rc = ab.main(["create", "--images", str(images_file), "--out", str(out),
                  "--skopeo", str(stub), *extra])
    assert rc == 0
    return out


class TestParse:
    def test_defaults_to_docker_hub_library(self):
        item = ab.parse_image_ref("busybox:1.37")
        assert (item["host"], item["path"], item["tag"]) == ("docker.io", "library/busybox", "1.37")

    def test_private_host_with_port(self):
        item = ab.parse_image_ref("registry.local:5000/team/app:2.0")
        assert (item["host"], item["path"]) == ("registry.local:5000", "team/app")

    def test_tag_required(self):
        with pytest.raises(ab.BundleError, match="explicit tag"):
            ab.parse_image_ref("busybox")

    def test_digest_rejected(self):
        with pytest.raises(ab.BundleError, match="digest"):
            ab.parse_image_ref("busybox@sha256:" + "a" * 64)

    def test_comments_and_blanks_skipped(self, images_file):
        assert [i["path"] for i in ab.read_images(images_file)] == [
            "nginxinc/nginx-unprivileged", "library/busybox"]

    def test_duplicates_rejected(self, tmp_path):
        f = tmp_path / "i.txt"
        f.write_text("busybox:1\ndocker.io/library/busybox:1\n")
        with pytest.raises(ab.BundleError, match="duplicate"):
            ab.read_images(f)

    def test_empty_file_rejected(self, tmp_path):
        f = tmp_path / "i.txt"
        f.write_text("# nothing\n")
        with pytest.raises(ab.BundleError, match="no images"):
            ab.read_images(f)


class TestCreateVerify:
    def test_manifest_created_and_verifies(self, tmp_path, stub_skopeo, images_file):
        bundle = make_bundle(tmp_path, stub_skopeo, images_file)
        manifest = json.loads((bundle / "manifest.json").read_text())
        assert len(manifest["images"]) == 2
        assert manifest["images"][0]["manifest_digest"].startswith("sha256:")
        assert all(len(v) == 64 for v in manifest["files"].values())
        assert ab.main(["verify", "--bundle", str(bundle)]) == 0

    def test_manifest_hashes_match_files(self, tmp_path, stub_skopeo, images_file):
        bundle = make_bundle(tmp_path, stub_skopeo, images_file)
        manifest = json.loads((bundle / "manifest.json").read_text())
        for rel, digest in manifest["files"].items():
            assert ab.sha256_file(bundle / rel) == digest

    def test_modified_blob_detected(self, tmp_path, stub_skopeo, images_file, capsys):
        bundle = make_bundle(tmp_path, stub_skopeo, images_file)
        blob = next((bundle / "images").rglob("blobs/sha256/*"))
        blob.write_bytes(b"tampered")
        assert ab.main(["verify", "--bundle", str(bundle)]) == 1
        assert "modified:" in capsys.readouterr().err

    def test_missing_file_detected(self, tmp_path, stub_skopeo, images_file, capsys):
        bundle = make_bundle(tmp_path, stub_skopeo, images_file)
        next((bundle / "images").rglob("index.json")).unlink()
        assert ab.main(["verify", "--bundle", str(bundle)]) == 1
        assert "missing:" in capsys.readouterr().err

    def test_extra_file_detected(self, tmp_path, stub_skopeo, images_file, capsys):
        bundle = make_bundle(tmp_path, stub_skopeo, images_file)
        (bundle / "images" / "evil.bin").write_bytes(b"x")
        assert ab.main(["verify", "--bundle", str(bundle)]) == 1
        assert "unexpected file" in capsys.readouterr().err

    def test_missing_manifest(self, tmp_path, capsys):
        (tmp_path / "b").mkdir()
        assert ab.main(["verify", "--bundle", str(tmp_path / "b")]) == 1
        assert "manifest.json" in capsys.readouterr().err

    def test_existing_out_dir_refused(self, tmp_path, stub_skopeo, images_file):
        make_bundle(tmp_path, stub_skopeo, images_file)
        rc = ab.main(["create", "--images", str(images_file), "--out", str(tmp_path / "bundle"),
                      "--skopeo", str(stub_skopeo)])
        assert rc == 1


class TestTarball:
    def test_tarball_roundtrip(self, tmp_path, stub_skopeo, images_file):
        tar = tmp_path / "bundle.tar"
        make_bundle(tmp_path, stub_skopeo, images_file, ["--tarball", str(tar)])
        assert Path(f"{tar}.sha256").is_file()
        assert ab.main(["verify", "--bundle", str(tar)]) == 0

    def test_tarball_tamper_detected(self, tmp_path, stub_skopeo, images_file, capsys):
        tar = tmp_path / "bundle.tar"
        make_bundle(tmp_path, stub_skopeo, images_file, ["--tarball", str(tar)])
        with tar.open("ab") as fh:
            fh.write(b"junk")
        assert ab.main(["verify", "--bundle", str(tar)]) == 1
        assert "checksum mismatch" in capsys.readouterr().err

    def test_sidecar_required(self, tmp_path, stub_skopeo, images_file, capsys):
        tar = tmp_path / "bundle.tar"
        make_bundle(tmp_path, stub_skopeo, images_file, ["--tarball", str(tar)])
        Path(f"{tar}.sha256").unlink()
        assert ab.main(["verify", "--bundle", str(tar)]) == 1


class TestDryRun:
    def test_create_dry_run_needs_no_skopeo_and_writes_nothing(self, tmp_path, images_file, capsys):
        out = tmp_path / "bundle"
        rc = ab.main(["create", "--images", str(images_file), "--out", str(out),
                      "--skopeo", "/nonexistent/skopeo", "--dry-run"])
        assert rc == 0
        assert not out.exists()
        text = capsys.readouterr().out
        assert "docker://docker.io/nginxinc/nginx-unprivileged:1.27-alpine" in text
        assert "dry run: 2 image(s)" in text

    def test_load_dry_run_still_verifies(self, tmp_path, stub_skopeo, images_file, capsys):
        bundle = make_bundle(tmp_path, stub_skopeo, images_file)
        capsys.readouterr()
        rc = ab.main(["load", "--bundle", str(bundle), "--registry", "harbor.example.internal/library",
                      "--skopeo", "/nonexistent/skopeo", "--dry-run"])
        assert rc == 0
        text = capsys.readouterr().out
        assert "docker://harbor.example.internal/library/nginxinc/nginx-unprivileged:1.27-alpine" in text
        assert "docker://harbor.example.internal/library/library/busybox:1.37" in text

    def test_load_dry_run_fails_on_tamper(self, tmp_path, stub_skopeo, images_file):
        bundle = make_bundle(tmp_path, stub_skopeo, images_file)
        next((bundle / "images").rglob("blobs/sha256/*")).write_bytes(b"bad")
        rc = ab.main(["load", "--bundle", str(bundle), "--registry", "r.example/x", "--dry-run"])
        assert rc == 1


class TestLoad:
    def test_load_calls_skopeo_for_each_image(self, tmp_path, stub_skopeo, images_file, monkeypatch):
        bundle = make_bundle(tmp_path, stub_skopeo, images_file)
        log = tmp_path / "calls.log"
        monkeypatch.setenv("STUB_LOG", str(log))
        rc = ab.main(["load", "--bundle", str(bundle), "--registry", "harbor.example.internal/library/",
                      "--authfile", "/run/auth.json", "--no-tls-verify", "--skopeo", str(stub_skopeo)])
        assert rc == 0
        lines = log.read_text().splitlines()
        assert len(lines) == 2
        assert all("--dest-authfile /run/auth.json" in ln for ln in lines)
        assert all("--dest-tls-verify=false" in ln for ln in lines)

    def test_load_refuses_tampered_bundle_and_pushes_nothing(self, tmp_path, stub_skopeo, images_file, monkeypatch):
        bundle = make_bundle(tmp_path, stub_skopeo, images_file)
        next((bundle / "images").rglob("blobs/sha256/*")).write_bytes(b"bad")
        log = tmp_path / "calls.log"
        monkeypatch.setenv("STUB_LOG", str(log))
        rc = ab.main(["load", "--bundle", str(bundle), "--registry", "r.example/x",
                      "--skopeo", str(stub_skopeo)])
        assert rc == 1
        assert not log.exists()

    def test_skopeo_failure_reported(self, tmp_path, images_file, capsys):
        rc = ab.main(["create", "--images", str(images_file), "--out", str(tmp_path / "b"),
                      "--skopeo", "/nonexistent/skopeo"])
        assert rc == 1
        assert "command not found" in capsys.readouterr().err


class TestPlatform:
    def test_platform_passed_to_skopeo(self, tmp_path, images_file, capsys):
        rc = ab.main(["create", "--images", str(images_file), "--out", str(tmp_path / "b"),
                      "--platform", "linux/amd64", "--dry-run"])
        assert rc == 0
        assert "--override-os linux --override-arch amd64 copy" in capsys.readouterr().out
