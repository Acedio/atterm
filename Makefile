MCU_TARGET     = attiny85
OPTIMIZE       = -Os
CC             = avr-gcc

override CFLAGS        = -g -Wall $(OPTIMIZE) -mmcu=$(MCU_TARGET)
override LDFLAGS       =

all: lcd.hex 

lcd.elf: lcd.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

lcd.hex: lcd.elf
	avr-objcopy -j .text -j .data -O ihex $< $@

upload: lcd.hex
	avrdude -p t85 -c ftdifriend -b 19200 -u -U flash:w:lcd.hex

clean:
	rm -rf *.o
	rm -rf *.hex
	rm -rf *.elf
