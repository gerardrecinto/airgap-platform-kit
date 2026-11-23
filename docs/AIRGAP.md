# Air-gapped workflow

The flow has a connected side that builds a bundle and a disconnected side
that verifies and consumes it. Only a file transfer connects the two.

```
connected side                          disconnected side
--------------                          -----------------
images.txt
   |  airgap_bundle.py create
   v
bundle/ + manifest.json (sha256)  --->  bundle/ (media or one-way transfer)
bundle.tar + bundle.tar.sha256          |  airgap_bundle.py verify
RKE2 release files + sha256sum          |  airgap_bundle.py load  -> Harbor
                                        |  ansible-playbook site.yml
                                        v
                                   RKE2 nodes pulling from Harbor
```

## 1. Build on the connected side

1. List images in `scripts/images.txt`, one per line, tag required.
2. `python3 scripts/airgap_bundle.py create --images scripts/images.txt --out bundle --tarball airgap-bundle.tar --platform linux/amd64`
3. Download the RKE2 release files for your version: `rke2.linux-amd64.tar.gz`,
   `rke2-images.linux-amd64.tar.zst`, `sha256sum-amd64.txt`, and `install.sh`
   from `https://get.rke2.io`. Put them in one directory.
4. Record `airgap-bundle.tar.sha256` somewhere that does not travel on the
   same media, for example a ticket, so a swapped tarball is noticed.
5. For scanning, download the Trivy database with `trivy image --download-db-only`
   and carry the cache directory across.

## 2. Verify and load on the disconnected side

```
python3 scripts/airgap_bundle.py verify --bundle airgap-bundle.tar
python3 scripts/airgap_bundle.py load --bundle airgap-bundle.tar \
  --registry harbor.example.internal/library --authfile /root/.docker/config.json
```

`load` verifies first and pushes nothing when a file is missing, modified, or
unexpected. Use `--dry-run` to see the skopeo commands with no network.
Images land at `<registry>/<repository>:<tag>`, so
`docker.io/nginxinc/nginx-unprivileged:1.27-alpine` becomes
`harbor.example.internal/library/nginxinc/nginx-unprivileged:1.27-alpine`.

Harbor notes: create the `library` project (or your own) first, use a robot
account for the push, and let Harbor's built-in Trivy scanner scan on push.
Trivy in Harbor needs its own offline database update path.

## 3. Install the nodes

The Ansible role in `ansible/roles/airgap` copies the bundle, RKE2 artifacts
and Puppet code to each node, runs `puppet apply` for `stig_baseline`, then runs
`scripts/rke2-airgap-install.sh`, which checks every file against
`sha256sum-amd64.txt` before installing. It writes `registries.yaml` so RKE2
pulls from Harbor.

Secrets such as the RKE2 join token must come from Ansible Vault or your
secret store. The role never defaults them to a real value.

## 4. Deploy applications

```
helm upgrade --install platform helm/umbrella -f helm/umbrella/values-airgap.yaml -n apps
```

`global.imageRegistry` repoints every image at Harbor. `helm/validate.sh`
fails if any rendered image is outside the private registry.

## What the tooling does not do

It does not mirror Helm chart repositories (pull charts with `helm pull` and
carry the `.tgz`), does not sign or verify image signatures, and does not
rotate the bundle. Treat the checksum manifest as integrity protection against
corruption and casual tampering. It is not a signature, since anyone who can
rewrite the bundle can rewrite `manifest.json`. Use a signed checksum or
a detached signature for stronger assurance.
