#include <avr/io.h>
#define F_CPU 8000000UL
#include <util/delay.h>

#define LCD_E 0x80

#define LCD_READ 0x40
#define LCD_WRITE 0x00

#define LCD_DR 0x20
#define LCD_IR 0x00

#define LCD_LED 0x10

void ser_byte(unsigned char b) {
  USIDR = b;
  USISR = _BV(USIOIF);

  do {
    USICR = _BV(USIWM0) | _BV(USICS1) | _BV(USICLK) | _BV(USITC);
  } while ((USISR & _BV(USIOIF)) == 0);

  USICR = 0;
}

void lcd_out(unsigned char address, unsigned char flags) {
  ser_byte(address);
  ser_byte(flags);

  PORTB &= ~_BV(PORTB3);
  PORTB |= _BV(PORTB3);
}

void lcd_wait() {
  while (PINB & _BV(PINB4)) {
  }
}

int main(void) {
  DDRB = _BV(DDB1) | _BV(DDB2) | _BV(DDB3) | ~_BV(DDB4);

  lcd_out(0, LCD_IR | LCD_READ | LCD_LED);
  lcd_out(0, LCD_E | LCD_IR | LCD_READ | LCD_LED);

  lcd_wait();

  while (1) {
    lcd_out(0, LCD_LED);
    _delay_ms(500);
    lcd_out(0, 0);
    _delay_ms(500);
  }
}
