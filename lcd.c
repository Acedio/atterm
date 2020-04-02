#include <avr/io.h>
#define F_CPU 8000000UL
#include <util/delay.h>

#define LCD_E 0x80

// Setting the LCD_RW_READ bit also turns off OE in the address register so the
// pins are in a high impedence state.
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
  do {
    // Pin changes during a read look to be triggered on E rising, so need to
    // loop to poll.
    // TODO: Can shorten these to 8 bits (no address).
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

  // 4 bit mode is default, so need to send two bits in most significant nibble.
  // 8 bits, 2 lines, 5x8
  lcd_write(0x30, 0);
  lcd_write(0x80, 0);
  lcd_wait();

  // Enable screen, cursor, and blinking
  lcd_write(0x0F, 0);
  lcd_wait();
}

void lcd_write_char(unsigned char c) {
  lcd_write(c, LCD_RS_DR);
  lcd_wait();
}

int main(void) {
  DDRB = _BV(DDB1) | _BV(DDB2) | _BV(DDB3) | ~_BV(DDB4);

  lcd_init();

  lcd_write(0x80, 0);
  lcd_wait();

  // a ku se su
  lcd_write_char(0xB1);
  lcd_write_char(0xB8);
  lcd_write_char(0xBE);
  lcd_write_char(0xBD);
  lcd_write_char(0xF4);

  lcd_write(0xC0, 0);
  lcd_wait();

  lcd_write_char(0xB1);
  lcd_write_char(0xB8);
  lcd_write_char(0xBE);
  lcd_write_char(0xBD);

  while (1) {
    lcd_out(0, LCD_LED);
    _delay_ms(500);
    lcd_out(0, 0);
    _delay_ms(500);
  }
}
