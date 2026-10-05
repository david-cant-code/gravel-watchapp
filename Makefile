CC ?= cc
CFLAGS ?= -std=c99 -Wall -Wextra -Werror -O1

.PHONY: build test clean
.NOTPARALLEL:

build:
	tools/build.sh

test: build/host/flow_test
	build/host/flow_test
	PYTHONPATH=tools/stubs python3 tests/freetype_stub_test.py
	tests/build_env_test.sh

build/host/flow_test: tests/flow_test.c src/c/flow.c src/c/flow.h
	mkdir -p build/host
	$(CC) $(CFLAGS) -o $@ tests/flow_test.c src/c/flow.c

clean:
	rm -rf build
