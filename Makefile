MCU_TARGET     = attiny85
OPTIMIZE       = -Os
CC             = avr-gcc

override CFLAGS        = -Wall $(OPTIMIZE) -mmcu=$(MCU_TARGET)
override LDFLAGS       = -Wl,-Tdata,0x800180

all: atterm.hex

keyboard.o: keyboard.h

lcd.o: lcd.h

atterm.elf: keyboard.o lcd.o

%.elf: %.o
	$(CC) $(LDFLAGS) -o $@ $^

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
