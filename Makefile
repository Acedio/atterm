MCU_TARGET     = attiny85
OPTIMIZE       = -Os
CC             = avr-gcc

override CFLAGS        = -Wall $(OPTIMIZE) -mmcu=$(MCU_TARGET)
override AFLAGS        = -nostdlib -Wall -mmcu=$(MCU_TARGET)
override LDFLAGS       = -Wl,-Tdata,0x800180

all: atterm.hex forth.hex

keyboard.o: keyboard.h

lcd.o: lcd.h

atterm.elf: keyboard.o lcd.o

forth.o: forth.S token_table.i

token_table.i: forth.S
	< forth.S grep -E "^def(code|word|var|const|string)" \
	| sed "s/^[^,]*,[^,]*,// ; s/[^A-Z_].*// ; s/\(.*\)/T_\1: .word \1/" > $@

%.elf: %.o
	$(CC) $(LDFLAGS) -o $@ $^

%.o: %.S
	$(CC) -c $(AFLAGS) -o $@ $<

%.o: %.c
	$(CC) -c $(CFLAGS) $(LDFLAGS) -o $@ $<

%.hex: %.elf
	avr-objcopy -j .text -j .data -O ihex $< $@

upload: forth.hex
	avrdude -p t85 -c ftdifriend -b 19200 -u -U flash:w:$<

clean:
	rm -rf *.o
	rm -rf *.hex
	rm -rf *.elf
	rm token_table.i
