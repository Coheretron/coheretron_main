.PHONY: configure-upstreams check-upstream-pins

configure-upstreams:
	bash scripts/configure-upstreams.sh

check-upstream-pins:
	bash scripts/check-upstream-pins.sh
