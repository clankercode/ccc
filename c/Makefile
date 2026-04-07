CC ?= gcc
CFLAGS ?= -Wall -Wextra -Werror -std=c11

build/ccc: src/ccc.c
	mkdir -p build
	$(CC) $(CFLAGS) -o build/ccc src/ccc.c

build/test_ccc: tests/test_ccc.c build/ccc
	mkdir -p build
	$(CC) $(CFLAGS) -o build/test_ccc tests/test_ccc.c

test: build/test_ccc
	./build/test_ccc
