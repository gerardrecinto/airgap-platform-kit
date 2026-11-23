.PHONY: check puppet helm shell python ansible trivy

check: puppet helm shell python ansible trivy

# Needs docker. Uses ruby:3.3 because Puppet 8 does not run on the newest Ruby.
puppet:
	docker run --rm -v "$(CURDIR)/puppet:/w" -w /w ruby:3.3 bash -c \
	  'bundle config set path /tmp/bundle >/dev/null && bundle install -j4 >/dev/null && BUNDLE_GEMFILE=/w/Gemfile ./check.sh'

helm:
	./helm/validate.sh

shell:
	shellcheck scripts/rke2-airgap-install.sh scripts/tests/test_rke2_install.sh helm/validate.sh puppet/check.sh ansible/tests/container-check.sh
	scripts/tests/test_rke2_install.sh

python:
	python3 -m pytest -q scripts

ansible:
	cd ansible && ansible-lint && ansible-playbook -i tests/inventory.ini playbooks/site.yml --syntax-check

trivy:
	trivy fs --scanners vuln,secret --severity HIGH,CRITICAL --exit-code 1 .
	trivy config --severity HIGH,CRITICAL --exit-code 1 .
