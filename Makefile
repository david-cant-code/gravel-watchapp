CC ?= cc
CFLAGS ?= -std=c99 -Wall -Wextra -Werror -O1

.PHONY: build test clean
.NOTPARALLEL:

build:
	tools/build.sh

test: build-test/host/flow_test
	build-test/host/flow_test
	PYTHONPATH=tools/stubs python3 tests/freetype_stub_test.py
	python3 tests/normalize_pbw_test.py
	tests/source_date_test.sh
	tests/build_env_test.sh
	tests/repro_test.sh
	tests/verify_release_test.sh

build-test/host/flow_test: tests/flow_test.c src/c/flow.c src/c/flow.h
	mkdir -p build-test/host
	$(CC) $(CFLAGS) -o $@ tests/flow_test.c src/c/flow.c

clean:
	rm -rf build build-test
