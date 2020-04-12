MCU_TARGET     = attiny85
OPTIMIZE       = -Os
CC             = avr-gcc

override CFLAGS        = -g -Wall $(OPTIMIZE) -mmcu=$(MCU_TARGET)
override AFLAGS        = -Wall -mmcu=$(MCU_TARGET)
override LDFLAGS       =

all: atterm.hex forth.hex

keyboard.o: keyboard.h

lcd.o: lcd.h

%.elf: %.o
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

atterm.elf: keyboard.o lcd.o

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
