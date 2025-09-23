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