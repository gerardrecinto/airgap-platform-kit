#!/usr/bin/env bash
# Lints the charts, renders them, and validates the output with kubeconform.
set -euo pipefail
cd "$(dirname "$0")"

helm lint charts/app
helm lint charts/app -f charts/app/ci/namespace-values.yaml

helm dependency build umbrella >/dev/null
helm lint umbrella -f umbrella/values-airgap.yaml

KC=(kubeconform -strict -summary -kubernetes-version 1.30.0)
helm template t charts/app | "${KC[@]}"
helm template t charts/app -f charts/app/ci/namespace-values.yaml | "${KC[@]}"
helm template t umbrella -f umbrella/values-airgap.yaml | "${KC[@]}"

# Every rendered image must come from the private registry.
images=$(helm template t umbrella -f umbrella/values-airgap.yaml | grep -E '^\s+image:' | sed 's/.*image: *//; s/"//g')
echo "rendered images: ${images}"
if echo "${images}" | grep -vq '^harbor.example.internal/'; then
  echo "found an image outside the private registry" >&2
  exit 1
fi

# The schema must reject an unsafe override.
if helm template t charts/app --set securityContext.readOnlyRootFilesystem=false >/dev/null 2>&1; then
  echo "schema accepted a writable root filesystem" >&2
  exit 1
fi
echo "schema rejects writable rootfs: ok"
