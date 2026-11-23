import stat
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

STUB = """#!{python}
import hashlib, json, os, sys
from pathlib import Path

args = sys.argv[1:]
log = os.environ.get("STUB_LOG")
if log:
    with open(log, "a") as fh:
        fh.write(" ".join(args) + "\\n")
src, dst = args[-2], args[-1]
if src.startswith("docker://") and dst.startswith("oci:"):
    layout = Path(dst[4:].rsplit(":", 1)[0])
    blobs = layout / "blobs" / "sha256"
    blobs.mkdir(parents=True)
    body = ("layer of " + src).encode()
    digest = hashlib.sha256(body).hexdigest()
    (blobs / digest).write_bytes(body)
    (layout / "oci-layout").write_text('{{"imageLayoutVersion": "1.0.0"}}')
    (layout / "index.json").write_text(json.dumps(
        {{"schemaVersion": 2, "manifests": [{{"digest": "sha256:" + digest}}]}}))
"""


@pytest.fixture
def stub_skopeo(tmp_path):
    path = tmp_path / "skopeo-stub"
    path.write_text(STUB.format(python=sys.executable))
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return path


@pytest.fixture
def images_file(tmp_path):
    path = tmp_path / "images.txt"
    path.write_text(
        "# comment\n"
        "docker.io/nginxinc/nginx-unprivileged:1.27-alpine\n"
        "\n"
        "busybox:1.37  # trailing comment\n"
    )
    return path
