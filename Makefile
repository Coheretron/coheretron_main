.PHONY: configure-upstreams check-upstream-pins test test-python test-contracts demo-p0 smoke-live-gosh

configure-upstreams:
	bash scripts/configure-upstreams.sh

check-upstream-pins:
	bash scripts/check-upstream-pins.sh

test: test-python test-contracts

test-python:
	PYTHONPATH=. python3 -m unittest discover -s tests -v

test-contracts:
	forge test -vvv

demo-p0:
	bash scripts/demo-p0.sh

smoke-live-gosh:
	bash scripts/smoke-live-gosh.sh
