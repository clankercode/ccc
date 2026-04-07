CC ?= gcc
CFLAGS ?= -Wall -Wextra -Werror -std=c11

build/ccc: src/ccc.c src/prompt_spec.c
	mkdir -p build
	$(CC) $(CFLAGS) -o build/ccc src/ccc.c src/prompt_spec.c

build/test_ccc: tests/test_ccc.c build/ccc
	mkdir -p build
	$(CC) $(CFLAGS) -o build/test_ccc tests/test_ccc.c

build/test_prompt_spec: tests/test_prompt_spec.c src/prompt_spec.c
	mkdir -p build
	$(CC) $(CFLAGS) -o build/test_prompt_spec tests/test_prompt_spec.c src/prompt_spec.c

build/test_runner: tests/test_runner.c src/runner.c
	mkdir -p build
	$(CC) $(CFLAGS) -o build/test_runner tests/test_runner.c src/runner.c

test: build/test_ccc build/test_prompt_spec build/test_runner
	./build/test_ccc
	./build/test_prompt_spec
	./build/test_runner
