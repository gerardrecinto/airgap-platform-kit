#!/usr/bin/env bash
# Runs parser validate, puppet-lint and rspec-puppet for stig_baseline.
set -euo pipefail
cd "$(dirname "$0")/modules/stig_baseline"
export BUNDLE_GEMFILE="${BUNDLE_GEMFILE:-../../Gemfile}"
bundle exec puppet parser validate manifests/*.pp
echo "parser validate: ok"
bundle exec puppet-lint --fail-on-warnings --no-140chars-check manifests
echo "puppet-lint: ok"
bundle exec rspec spec/classes
