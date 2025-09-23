Powrót do strony głównej >  https://4programmers.net/Forum/Hardware_Software/376880-programowanie_systemowe_procesorow_z_rodziny_x86_64

Witaj na moim mikroblogu poświęconemu programowaniu. Celem wpisów będzie przedstawienie Ci w jaki sposób, wykonując minimalną ilość kroków stworzyć mały i zarazem w pełni funkcjonalny system operacyjny. Każdy kolejny wpis będzie pojawiał się cyklicznie, gdy wskazówki mojego zegarka zrównają się ze sobą.
<sub>ekhm, jest cyfrowy...</sub>

Jest to mój pierwszy akt napisania czegoś więcej niż odpowiedzi na forum. Za wszelkie niedociągnięcia, przepraszam :D

Zamieszczony materiał będzie oznaczany za pomocą taga **#blackdev.org**, pozwoli to na łatwe zlokalizowanie wszystkich wpisów mojego autorstwa. Nie omieszkam dodać innych, zależnie od poruszanego tematu.

Nie jestem osobą postronną w tym temacie i nie sądzę bym rzucał się z motyką na słońce. Posiadam odpowiednie zaplecze doświadczenia z tej dziedziny, co mogę udowodnić okazując moje dwa repozytoria już w jakimś stopniu działających systemów. Jedno w języku Asemblera (<a href="https://github.com/CorruptedByCPU/Cyjon/tree/eldest">Cyjon v1</a>, <a href="https://github.com/CorruptedByCPU/Cyjon/tree/old">Cyjon v2</a>) oraz drugie zapisane w czystym języku C (<a href="https://github.com/CorruptedByCPU/Foton">Foton</a>)
<sup>*no dobra, jest trochę wstawek z języka Asemblera, bez tego się nie obejdzie*</sup>

Naszymi głównymi narzędziami programistycznymi będą języki **C** i **Asembler** — każdy w swoim zakresie odpowiedzialności. Do kompilacji kodu w języku C posłuży nam **Clang** z rodziny LLVM (https://clang.llvm.org/), zarazem pliki asemblerowe przetwarzane będą przez **NASM** (https://www.nasm.us/). Za środowisko produkcyjne posłuży nam jakikolwiek system operacyjny z rodziny GNU/Linux. Można też wszystkie akcje wykonać za pomocą MS Windows i subsystemu WSL (sprawdzałem, działa).

Ostatnia informacja gwoli ścisłości: każdy przykład zostanie przedstawiony w sposób minimalny, aby osiągnąć oczekiwany efekt. Funkcjonalność będziemy rozwijać powoli, krok po kroku, aby wszystko było dobrze zrozumiałe. Wszelkie uwagi, pytania, pomysły, domysły i spekulacje mogą zostać poddane przemyśleniom, ale niekoniecznie zaimplementowane.

## Jądro systemu operacyjnego
Na początek osiągnijmy status quo w środowisku wirtualnym (lub fizycznym) tworząc prosty szkielet pierwszej funkcji jądra systemu.

<sub>Plik: `kernel/init.c`</sub>
```c
void kernel_init( void ) {
	while( 1 );
}
```

Próba kompilacji powyższego kodu za pomocą domyślnego podejścia, nie przyniesie pożądanego efektu.

<sub>Przykład:</sub>
```sh
$ clang kernel/init.c
/usr/bin/ld: /usr/bin/../lib64/gcc/x86_64-pc-linux-gnu/15.2.1/../../../../lib64/Scrt1.o: in function `_start':
(.text+0x1b): undefined reference to `main'
```

Dzieje się tak dlatego, że kompilator Clang (podobnie jak GCC) zakłada, iż tworzymy zwykłą aplikację użytkową dla istniejącego systemu operacyjnego (w którym aktualnie pracujemy). Musimy zatem przekazać kompilatorowi jasne instrukcje, że piszemy kod działający „samodzielnie”, bez nadzoru jakiegokolwiek systemu operacyjnego.

<sub>Przykład:</sub>
```sh
$ clang -c kernel/init.c -o build/init.o -march=x86-64 -mtune=generic -ffreestanding
```

W powyższym poleceniu informujemy kompilator o oczekiwanych właściwościach generowanego kodu maszynowego:

|Flaga|Opis|
|---|---|
|**-c**|<u>Tylko</u> przetłumacz kod źródłowy na język maszynowy - **bez linkowania**|
|**-o**|Wyniki swojej pracy zapisz w pliku `build/init.o`.|
|**-march=x86-64**|Wygeneruj kod dla 64-bitowej architektury x86, kompatybilny z większością współczesnych procesorów.|
|**-mtune=generic**|Zastosuj uniwersalne optymalizacje, bez wiązania kodu z konkretnym modelem procesora.|
|**-ffreestanding**|Kompiluj w trybie **niezależnym od środowiska systemowego** – bez standardowej biblioteki, bez `main()`.|

⚙️ Tryb **freestanding** to jeden z dwóch trybów kompilacji w standardzie języka C (obok hosted). Pozwala tworzyć kod dla systemów operacyjnych, firmware, bootloaderów itp.

## Przestrzeń adresowa systemu operacyjnego.

Zanim przejdziemy do analizy kodu źródłowego linkera (`tools/kernel.ld`), warto na chwilę przystanąć i zaznajomić się z przestrzenią pamięci w której będziemy pracować na co dzień.

Nie będziemy czytać/modyfikować zawartości przestrzeni pamięci fizycznej bezpośrednio. Nie jest to możliwe z punktu widzenia programisty. Za poruszanie się i wszelkie na niej operacje posłuży nam **wirtualna przestrzeń adresowa** (tzw. logiczna). Natomiast bezpośredni dostęp do pamięci fizycznej stanowi wyjątek i dostęp zezwolony jest tylko dla urządzeń oraz specjalnych sterowników, często w fazie inicjalizacji sprzętu.

Choć rejestry ogólnego przeznaczenia w architekturze x86-64 mają 64 bity, to pierwsze procesory x86-64 udostępniły jedynie 48 bitów adresowych. Daje nam to przestrzeń o rozmiarze 256 TiB...

Pozostałe bity (63..48) muszą być kopią bitu 47, jest to tak zwana **kanoniczność adresów**. Dzięki temu przestrzeń wirtualna składa się z:

- Dolna połowa **0x0000000000000000**...**0x00007FFFFFFFFFFF** - dla procesów i bibliotek użytkownika,
- Górna połowa **0xFFFF800000000000...0xFFFFFFFFFFFFFFFF** - dla jądra systemu, modułów i sterowników.

Między nimi pozostaje obszar niekanoniczny, jakakolwiek próba dostępu generuje wyjątek procesora.<sup>(General Protection Fault)</sup>

Prosty przykład wizualizacji wirtualnej przestrzeni pamięci:

```
0x0000000000000000
|	0x00007FFFFFFFFFFF
+---+------------------------------------+---+
| P |      przestrzeń niekanoniczna      | K |
+---+------------------------------------+---+
						0xFFFF800000000000	 |
							0xFFFFFFFFFFFFFFFF
P - przestrzeń procesu
K - przestrzeń jądra systemu
```
lub w formie tabelki:

|Rozmiar|Adresacja|Opis|
|-|-|-|
|128 TiB|0x0000000000000000 - 0x00007FFFFFFFFFFF|Przestrzeń użytkownika: programy, stos, biblioteki.|
|~16 EiB|0x0000800000000000 - 0xFFFF7FFFFFFFFFFF|Zarezerwowana / niekanoniczna przestrzeń adresowa.|
|128 TiB|0xFFFF800000000000 - 0xFFFFFFFFFFFFFFFF|Przestrzeń jądra: kernel, moduły, odwzorowanie pamięci fizycznej.|

Na stan dzisiejszy nie spotkałem się z serwerami o pojemności większej niż 6 TiB pamięci fizycznej RAM, a nadal jest to kropla w morzu przy możliwościach jakie daje nam **PML5** i 56-bitowa adresacja<sup>(o tym w następnych wpisach na mikroblogu)

## Linker

Po skompilowaniu kodu źródłowego wchodzącego w skład jądra systemu otrzymujemy zestaw plików obiektowych, w których funkcje i dane posiadają adresy względne. Pozwala nam to na umieszczenie jądra w każdym miejscu przestrzeni wirtualnej. Teraz naszym zadaniem będzie połączenie wszystkich plików w jeden i w tym celu posłużymy się linkerem.

<sub>Plik: `tools/kernel.ld`</sub>
```ld
OUTPUT_FORMAT( elf64-x86-64 )

ENTRY( kernel_init )

SECTIONS {
	. = 0xFFFFFFFFFFFF0000;

	.all : {
		*(.all)
	} :all
}

PHDRS {
	all		PT_LOAD		FLAGS( (1 << 0) | (1 << 1) | (1 << 2) );
}
```

Plik ten zawiera minimalną konfigurację, nic zbędnego na nasze aktualne zapotrzebowanie. Do naszych celów wykorzystamy plik typu ELF (64 bitowy). Format ten pozwoli nam na skorzystanie z obsługi bibliotek w późniejszym czasie.

- `OUTPUT_FORMAT( elf64-x86-64 )` typ pliku docelowego to 64-bitowy ELF dla architektury x86-64,
- `ENTRY( kernel_init )` ustala punkt wejścia programu. To adres, pod który skoczy program rozruchowy po zakończeniu swojej pracy,
- `0xFFFFFFFFFFFF0000` lokalizacja jądra systemu w przestrzeni wirtualnej,
- `.all` wszystkie części/sekcje jądra będziemy trzymać w jednej sekcji, w tym momencie jest to nam w zupełności wystarczające,

Ostatnia pozycja **PHDRS** określa właściwości segmentów ELF, w tym przypadku naszej sekcji **.all** tj.

- **(1 << 0 )** sekcja zawiera kod wykonywalny,
- **(1 << 1 )** zawartość sekcji można modyfikować,
- **(1 << 2 )** zawartość sekcji można czytać.

Zatem wykonajmy linkowanie, otrzymując finalnie gotowy plik jądra systemu:
```sh
$ ld build/init.o -o build/kernel -T tools/kernel.ld
```

## Program rozruchowy.

Stworzenie własnego programu rozruchowego to zadanie niemal tak wymagające jak napisanie całego systemu operacyjnego. Na potrzeby tego mikrobloga nie będziemy się tym zajmować – zamiast tego wykorzystamy gotowe narzędzie, które sprawdza się idealnie w tej roli.

Sięgniemy po [Limine](https://codeberg.org/Limine/Limine) – nowoczesny, zaawansowany i przenośny program rozruchowy. Pozwala na załadowanie i uruchomienie czysto 64-bitowego jądra systemu oraz bardzo wygodny [protokół](https://codeberg.org/Limine/limine-protocol/src/branch/trunk/PROTOCOL.md).

<sub>Plik: `tools/limine.conf`</sub>
```cfg
timeout:	8

/4programmers
	protocol:	limine
	path:		boot():/kernel
```

Krótki opis każdej z linii:

- `timeout` ilość pozostałych sekund, po których uruchomiony zostanie nasz wpis,
- `/4programmers` etykieta menu,
- `protocol` w jaki sposób ma się komunikować program rozruchowy z jądrem systemu,
- `path` ścieżka do pliku jądra systemu, `boot():/` oznacza katalog główny nośnika z którego uruchomiony został program rozruchowy

Wizualizacja:

![hello](https://blackdev.org/shot/4p-limine.png)

Po wszystkie możliwe opcje konfiguracji pliku konfiguracyjnego odsyłam do [źródła](https://codeberg.org/Limine/Limine/src/branch/v9.x/CONFIG.md).

## Nośnik informacji.

Wykorzystamy najbardziej powszechny format dystrybucyjny jakim jest ISO. Działa wszędzie, łatwo stworzyć i świetnie nadaje się do naszych prac. Nie ma tu żadnego pliku konfiguracyjnego ;)

## Budowa i uruchomienie.

W skrypcie zostały wykorzystane przekierowania standardowego wyjścia do **/dev/null 2>&1**. Ma to na celu niezaśmiecania zbędnymi informacjami podczas pracy. Jeśli w trakcie jakiejkolwiek czynności wystąpi błąd to zostanie wyświetlony.

<sub>Plik: `make.sh`:</sub>
```sh
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
```

<sub>Plik: `qemu.sh`</sub>

```sh
#!/bin/bash

qemu-system-x86_64 -cdrom build/system.iso
```

Jaki efekt będzie na nas czekał po uruchomieniu obydwu skryptów?

![hello](https://blackdev.org/shot/4p-hello.png)

Realny efekt końcowy – czarny ekran po uruchomieniu, czyli prawdziwy "Hello, OSDev!" w praktyce.
