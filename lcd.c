#include <avr/io.h>
#define F_CPU 8000000UL
#include <util/delay.h>

#define LCD_E 0x80

#define LCD_RW_READ 0x40

#define LCD_RS_DR 0x20

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
  // Can shorten these to 8 bits (no address).
  do {
    lcd_out(0, LCD_RW_READ);
    lcd_out(0, LCD_E | LCD_RW_READ);
  } while (PINB & _BV(PINB4));
}

void lcd_write(unsigned char address, unsigned char flags) {
  // Writes look to be triggered on E falling.
  lcd_out(address, flags | LCD_E);
  lcd_out(address, flags & ~LCD_E);
}

void lcd_init() {
  lcd_wait();

  // 4 bit mode is default, so need to send two bits.
  // 8 bits, 2 lines, 5x8
  lcd_write(0x03, 0);
  lcd_write(0x08, 0);
  lcd_wait();

  lcd_write(0x0F, 0);
  lcd_wait();
}

int main(void) {
  DDRB = _BV(DDB1) | _BV(DDB2) | _BV(DDB3) | ~_BV(DDB4);

  lcd_init();

  /*
  lcd_out(0x0E, LCD_E | LCD_IR);
  lcd_out(0x0E, LCD_IR);

  lcd_out(0, LCD_E | LCD_IR | LCD_RW_READ);
  lcd_out(0, LCD_IR | LCD_RW_READ);
  lcd_wait();
  */

  while (1) {
    lcd_out(0, LCD_LED);
    _delay_ms(500);
    lcd_out(0, 0);
    _delay_ms(500);
  }
}
