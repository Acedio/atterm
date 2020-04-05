MCU_TARGET     = attiny85
OPTIMIZE       = -Os
CC             = avr-gcc

override CFLAGS        = -g -Wall $(OPTIMIZE) -mmcu=$(MCU_TARGET)
override LDFLAGS       =

all: atterm.hex

keyboard.o: keyboard.h

atterm.elf: atterm.o keyboard.o
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

%.o: %.c
	$(CC) -c $(CFLAGS) $(LDFLAGS) -o $@ $<

%.hex: %.elf
	avr-objcopy -j .text -j .data -O ihex $< $@

upload: atterm.hex
	avrdude -p t85 -c ftdifriend -b 19200 -u -U flash:w:$<

clean:
	rm -rf *.o
	rm -rf *.hex
	rm -rf *.elf
