# airgap-platform-kit

Reusable infrastructure code for building a disconnected Kubernetes platform on RHEL 9: a STIG-aligned Puppet baseline, a hardened Helm chart, an image bundle tool for air-gapped registries, and Ansible to stage and install RKE2.

This is a portfolio project. It covers a STIG-aligned subset only and makes no compliance claim. See [docs/STIG_MAPPING.md](docs/STIG_MAPPING.md).

## Architecture

```
 connected side                                   disconnected side
 --------------                                   -----------------
 images.txt                                       media / one-way transfer
     |                                                    |
 airgap_bundle.py create  ----  bundle.tar + sha256 ----> airgap_bundle.py verify
 (skopeo -> OCI dirs,                                     |
  sha256 manifest)                                airgap_bundle.py load
 RKE2 release files  ------------------------------->     |
                                                          v
                                                  Harbor (Trivy scan on push)
                                                          |
   Ansible role "airgap" on each node                     |
   1 stage bundle + scripts + puppet code                 |
   2 puppet apply stig_baseline (Hiera role data)         |
   3 rke2-airgap-install.sh (checksum verified)           |
   4 registries.yaml -> mirrors point at Harbor <---------+
                                                          |
   helm/umbrella + values-airgap.yaml  -> pods pull from Harbor
   (global.imageRegistry, restricted PSA, read-only rootfs, NetworkPolicy)
```

## Layout

| Path | What it is |
|------|------------|
| `puppet/modules/stig_baseline` | Puppet module, Hiera module data, rspec-puppet tests |
| `puppet/hiera.yaml`, `puppet/hiera/role` | Site Hiera with an `rke2_node` role override |
| `helm/charts/app` | Hardened app chart with `values.schema.json` |
| `helm/umbrella` | Umbrella chart and `values-airgap.yaml` |
| `scripts/airgap_bundle.py` | Bundle create, verify, load (skopeo) |
| `scripts/rke2-airgap-install.sh` | Offline RKE2 install with checksum verification |
| `ansible/` | Playbook and `airgap` role |
| `.gitlab-ci.yml`, `.github/workflows/ci.yml` | Lint, test, scan, build-bundle |
| `docs/` | STIG mapping, air-gap workflow, Keycloak OIDC notes |
| `examples/keycloak-values.yaml` | Keycloak Helm values example (untested live) |

## Quick start

These are the commands I ran, with the output they produced on a Mac with Docker, Python 3.12, helm, kubeconform, shellcheck and a source-built skopeo 1.25.2.

Puppet module (parser validate, puppet-lint, rspec-puppet, in a `ruby:3.3` container):

```
$ make puppet
parser validate: ok
puppet-lint: ok
.....................................................
Finished in 0.59 seconds
53 examples, 0 failures
```

Helm charts:

```
$ ./helm/validate.sh
==> Linting charts/app
1 chart(s) linted, 0 chart(s) failed
==> Linting umbrella
1 chart(s) linted, 0 chart(s) failed
Summary: 4 resources found parsing stdin - Valid: 4, Invalid: 0, Errors: 0, Skipped: 0
Summary: 5 resources found parsing stdin - Valid: 5, Invalid: 0, Errors: 0, Skipped: 0
Summary: 4 resources found parsing stdin - Valid: 4, Invalid: 0, Errors: 0, Skipped: 0
rendered images: harbor.example.internal/library/nginxinc/nginx-unprivileged:1.27-alpine
schema rejects writable rootfs: ok
```

Python tests, shell tests and shellcheck:

```
$ python3 -m pytest -q scripts
........................                                                 [100%]
24 passed in 1.64s
$ shellcheck scripts/rke2-airgap-install.sh scripts/tests/test_rke2_install.sh && scripts/tests/test_rke2_install.sh
ok: dry run on good stage
ok: agent type and --no-start
ok: tamper detected
ok: missing dir rejected
ok: bad type rejected
5 checks passed
```

Bundle round trip with real skopeo. A local `registry:2` container on port 5055 stood in for Harbor:

```
$ python3 scripts/airgap_bundle.py create --images images.txt --out bundle --tarball bundle.tar --platform linux/amd64
...
wrote bundle/manifest.json: 1 image(s), 5 file(s)
wrote bundle.tar sha256=11838a9ce1531e1b84d15cc28f40517239ced1d14ce5da9135ce8b0fe7b42b03
$ python3 scripts/airgap_bundle.py verify --bundle bundle.tar
ok: 1 image(s), 5 file(s) verified
$ python3 scripts/airgap_bundle.py load --bundle bundle.tar --registry localhost:5055/library --no-tls-verify
bundle verified: 1 image(s)
...
$ curl -s localhost:5055/v2/_catalog
{"repositories":["library/library/busybox"]}
```

Tamper detection after appending a byte to one blob:

```
$ python3 scripts/airgap_bundle.py verify --bundle bundle-bad; echo "exit=$?"
error: bundle verification failed
  modified: images/docker.io_library_busybox_1.37/blobs/sha256/30ecbe15...
exit=1
```

Dry run, no network and no skopeo needed:

```
$ python3 scripts/airgap_bundle.py load --bundle bundle --registry harbor.example.internal/library --dry-run
bundle verified: 1 image(s)
+ skopeo copy --retry-times 3 oci:.../docker.io_library_busybox_1.37:1.37 docker://harbor.example.internal/library/library/busybox:1.37
dry run: 1 image(s) would be pushed to harbor.example.internal/library
```

Ansible lint, then the playbook in a Rocky Linux 9 container (`ansible/tests/container-check.sh`):

```
$ cd ansible && ansible-lint
Passed: 0 failure(s), 0 warning(s) in 13 files processed of 16 encountered. Profile 'production' was required, and it passed.
$ ansible/tests/container-check.sh
...
PLAY RECAP
localhost : ok=8  changed=5 unreachable=0 failed=0 skipped=0   (--tags stage, real run in the container)
localhost : ok=15 changed=5 unreachable=0 failed=0 skipped=2   (--check, Puppet in --noop)
```

Chart on a real cluster (kind, namespace labeled `pod-security.kubernetes.io/enforce=restricted`):

```
$ helm install demo helm/charts/app -n demo --wait
STATUS: deployed
$ kubectl -n demo get pods
demo-app-896764c5f-48db9   1/1   Running   0   10s
demo-app-896764c5f-mq4nm   1/1   Running   0   10s
```

Trivy 0.74.0 on this repo (`trivy fs --scanners vuln,secret` and `trivy config`, HIGH and CRITICAL) reported no findings.

## Validated vs not validated

| Item | Status |
|------|--------|
| Puppet: parser validate, puppet-lint, 53 rspec-puppet examples | Run, passing (Puppet 8.10, Ruby 3.3 container) |
| Puppet `--noop` on Rocky Linux 9 container via Ansible check mode | Run, reports pending changes, applies nothing |
| Puppet apply for real, including sshd, auditd and sysctl reload | Not run (needs a systemd host) |
| STIG scan (OpenSCAP or DISA SCC) of a hardened host | Not run. No compliance claim |
| STIG IDs checked against the current DISA benchmark | Not done. Taken from a public listing, verify before use |
| Helm lint and kubeconform on chart and umbrella | Run, passing |
| Chart installed on kind with restricted Pod Security | Run, pods Running |
| NetworkPolicy enforcement | Not tested. Depends on the CNI |
| Python bundle tool, 24 pytest tests | Run, passing |
| Bundle create, verify, load with real skopeo against a local `registry:2` | Run, passing |
| Load into Harbor | Not run. `registry:2` is not Harbor, so robot accounts, projects and scan on push are untested |
| `rke2-airgap-install.sh` dry run and checksum tests against fake artifacts | Run, passing |
| Real RKE2 install from release artifacts | Not run |
| Ansible lint (production profile) and syntax check | Run, passing |
| Ansible `--check` in a Rocky 9 container | Run, passing. Real RKE2 install tasks not run |
| Anything on a real air-gapped network | Not run |
| `.github/workflows/ci.yml` | Run on GitHub, see the Actions tab |
| `.gitlab-ci.yml` | Parsed as YAML only. Never run on GitLab |
| Keycloak OIDC and LDAP | Docs only, untested against a live Keycloak. Values were rendered with `helm template` |

## Scope and claims

The Puppet module implements a small subset of RHEL 9 STIG-aligned settings. It is aligned to those controls, not compliant, certified, or accredited. This project makes no DoD, clearance, or customer claims. Replace the placeholder banner text and review every setting before using it anywhere real.

## Requirements

Docker (for the Puppet and Rocky checks), Python 3.12, helm 3, kubeconform, shellcheck, skopeo, ansible-core, ansible-lint, trivy. `make check` runs the local suite.

## License

MIT. See [SECURITY.md](SECURITY.md) for reporting issues.
