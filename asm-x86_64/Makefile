NASM := nasm
LD := ld

.PHONY: all clean test

all: ccc

ccc-bin: ccc.asm
	$(NASM) -f elf64 -o ccc.o ccc.asm
	$(LD) -o ccc-bin ccc.o

ccc: ccc-bin ccc.sh
	cp ccc.sh ccc
	chmod +x ccc

test: ccc
	bash tests/test_ccc.sh

clean:
	rm -f ccc.o ccc-bin ccc
