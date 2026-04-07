NASM := nasm
LD := ld

.PHONY: all clean test

all: ccc

ccc: ccc.asm
	$(NASM) -f elf64 -o ccc.o ccc.asm
	$(LD) -o ccc ccc.o

test: ccc
	bash tests/test_ccc.sh

clean:
	rm -f ccc.o ccc
