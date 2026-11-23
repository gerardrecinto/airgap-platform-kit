#!/usr/bin/env bash
# Runs the playbook in --check mode inside a Rocky Linux 9 container (a RHEL 9
# rebuild) with real ansible-core and puppet-agent. Needs docker and network
# access to pull the image and the puppet-agent package, so it is a developer
# check, not an air-gapped one. The staging tag runs for real inside the throwaway
# container, everything else is --check with Puppet in --noop.
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Tiny stand-in bundle and RKE2 artifacts. They are fake files, enough for
# the check run to exercise copy, template and command tasks.
mkdir -p "$work/bundle/images" "$work/rke2"
printf '{"version":1,"images":[],"files":{}}\n' > "$work/bundle/manifest.json"
printf 'fake\n' > "$work/rke2/rke2.linux-amd64.tar.gz"
printf 'fake\n' > "$work/rke2/rke2-images.linux-amd64.tar.zst"
printf '#!/bin/sh\nexit 0\n' > "$work/rke2/install.sh"
if command -v sha256sum >/dev/null 2>&1; then hasher=(sha256sum); else hasher=(shasum -a 256); fi
(cd "$work/rke2" && "${hasher[@]}" rke2.linux-amd64.tar.gz rke2-images.linux-amd64.tar.zst > sha256sum-amd64.txt)

docker run --rm -v "$repo:/repo:ro" -v "$work:/work:ro" rockylinux:9 bash -euxo pipefail -c '
  dnf -y -q install ansible-core python3 procps-ng https://yum.puppet.com/puppet8-release-el-9.noarch.rpm
  dnf -y -q install puppet-agent
  cd /repo/ansible
  ansible-playbook -i tests/inventory.ini playbooks/site.yml --syntax-check
  vars=(-e airgap_bundle_src=/work/bundle -e airgap_rke2_artifacts_src=/work/rke2
        -e airgap_scripts_src=/repo/scripts -e airgap_puppet_src=/repo/puppet)
  # Real run of the staging tag only, inside the throwaway container.
  ansible-playbook -i tests/inventory.ini playbooks/site.yml --tags stage "${vars[@]}"
  # Check mode for everything, with Puppet in noop against the staged code.
  ansible-playbook -i tests/inventory.ini playbooks/site.yml --check --diff "${vars[@]}"
'
