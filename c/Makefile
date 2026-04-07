CC ?= gcc
CFLAGS ?= -Wall -Wextra -Werror -std=c11

build/ccc: src/ccc.c src/runner.c src/parser.c src/config.c
	mkdir -p build
	$(CC) $(CFLAGS) -o build/ccc src/ccc.c src/runner.c src/parser.c src/config.c

build/test_ccc: tests/test_ccc.c build/ccc src/runner.c src/prompt_spec.c
	mkdir -p build
	$(CC) $(CFLAGS) -o build/test_ccc tests/test_ccc.c src/runner.c src/prompt_spec.c

build/test_prompt_spec: tests/test_prompt_spec.c src/prompt_spec.c
	mkdir -p build
	$(CC) $(CFLAGS) -o build/test_prompt_spec tests/test_prompt_spec.c src/prompt_spec.c

build/test_runner: tests/test_runner.c src/runner.c
	mkdir -p build
	$(CC) $(CFLAGS) -o build/test_runner tests/test_runner.c src/runner.c

build/test_parser: tests/test_parser.c src/parser.c
	mkdir -p build
	$(CC) $(CFLAGS) -o build/test_parser tests/test_parser.c src/parser.c

build/test_json_output: tests/test_json_output.c src/json_output.c
	mkdir -p build
	$(CC) $(CFLAGS) -o build/test_json_output tests/test_json_output.c src/json_output.c -lm

clean:
	rm -rf build

test: build/test_ccc build/test_prompt_spec build/test_runner build/test_parser build/test_json_output
	./build/test_ccc
	./build/test_prompt_spec
	./build/test_runner
	./build/test_parser
	./build/test_json_output
