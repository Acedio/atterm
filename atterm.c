#include "keyboard.h"

#include <avr/io.h>
#include <avr/interrupt.h>
#define F_CPU 8000000UL
#include <util/delay.h>

int main(void) {
  cli();
  DDRB |= _BV(DDB0);
  PORTB &= ~_BV(PB0);
  kb_init();

  kb_enable();
  sei();

  while(1) {
    unsigned char b;
    if (kb_read(&b) && b == 0x1C) {
      PORTB ^= _BV(PB0);
    }
  }
}
