#!/bin/bash
set -e	# zatrzymaj skrypt, gdy pojawi się jakikolwiek błąd

# zmienne
BUILD="build"
C="clang"
LD="ld"
ISO="system.iso"

# posprzątaj śmieci
rm -rf ${BUILD}
mkdir -p ${BUILD}

### Budowa systemu operacyjnego ###

# kompilacja części składowych jądra
${C} -c kernel/init.c -o build/init.o -march=x86-64 -mtune=generic -ffreestanding

# utworzenie pliku kernel
${LD} build/init.o -o build/kernel -T tools/kernel.ld > /dev/null 2>&1

### Tworzenie nośnika ISO ###

# wszystkie niezbędne pliki do utworzenia obrazu płyty znajdą się w katalogu
mkdir -p ${BUILD}/iso

# pobierz aktualną kompilację programu rozruchowego
if [ ! -d limine ]; then git clone https://codeberg.org/Limine/limine -b v9.x-binary --depth 1
else (cd limine && git pull > /dev/null 2>&1 || exit $!); fi

# skompiluj limine
(cd limine && make > /dev/null 2>&1 || exit $!)

# skopiuj pliki programu rozruchowego
cp tools/limine.conf limine/{limine-bios.sys,limine-bios-cd.bin,limine-uefi-cd.bin} ${BUILD}/iso

# oraz jądro systemu
cp ${BUILD}/kernel ${BUILD}/iso

# utwórz nośnik w formacie ISO z obsługą Legacy (BIOS) oraz UEFI
xorriso -as mkisofs -b limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table --efi-boot limine-uefi-cd.bin -efi-boot-part --efi-boot-image --protective-msdos-label ${BUILD}/iso -o ${BUILD}/${ISO} > /dev/null 2>&1

# zainstaluj program rozruchowy
./limine/limine bios-install ${BUILD}/${ISO} > /dev/null 2>&1
