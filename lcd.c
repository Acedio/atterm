#include <avr/io.h>
#define F_CPU 8000000UL
#include <util/delay.h>

void ser_out(unsigned char b) {
  PORTB &= !_BV(PORTB3);

  USIDR = b;
  USISR = _BV(USIOIF);

  do {
    USICR = _BV(USIWM0) | _BV(USICS1) | _BV(USICLK) | _BV(USITC);
  } while ((USISR & _BV(USIOIF)) == 0);

  PORTB |= _BV(PORTB3);
}

int main(void) {
  DDRB = _BV(DDB1) | _BV(DDB2) | _BV(DDB3) | _BV(DDB4);
  PORTB &= ! _BV(PORTB4);

  unsigned char b = 0;
  while (1) {
    PORTB ^= _BV(PORTB4);
    ser_out(b++);
    _delay_ms(500);
  }
}
