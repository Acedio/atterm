// Port assignment
// PB0 - LCD busy pin and the MSB of the LCD bus.
// PB1 - Serial out to the shift registers.
// PB2 - Clock for serial input on the shift registers.
// PB3 - Clock for the outputs on the shift registers.
// PB4 - Unused, but will used for PS/2 clock.
// PB5 - Reset pin, left open for programming.

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
  } while (PINB & _BV(PINB0));
}

void lcd_write(unsigned char address, unsigned char flags) {
  // Writes look to be triggered on E falling.
  lcd_out(address, flags | LCD_E);
  lcd_out(address, flags & ~LCD_E);
}

void lcd_init() {
  lcd_wait();

  // 8 bits, 2 lines, 5x8
  lcd_write(0x38, 0);
  lcd_wait();

  // Clear the screen.
  lcd_write(0x01, 0);
  lcd_wait();

  // Enable screen, cursor, and blinking
  lcd_write(0x0F, 0);
  lcd_wait();
}

void lcd_write_char(unsigned char c) {
  lcd_write(c, LCD_RS_DR);
  lcd_wait();
}

void lcd_custom_char(int index, unsigned char b[8]) {
  if (index < 0 || index >= 16) {
    return;
  }

  lcd_write(0x40 + (index * 8), 0);
  lcd_wait();

  int row;
  for (row = 0; row < 8; ++row) {
    lcd_write_char(b[row]);
  }
}

unsigned char smile[8] = {
    0b00001110, 0b00011111, 0b00010101, 0b00011111,
    0b00010001, 0b00010001, 0b00011011, 0b00001110,
};

void acedio() {
  unsigned char acedio_chars[4][8] = {
      {
          0b00000011,
          0b00000111,
          0b00001111,
          0b00001111,
          0b00001111,
          0b00011111,
          0b00011111,
          0b00011111,
      },
      {
          0b00011000,
          0b00011100,
          0b00011110,
          0b00011110,
          0b00011110,
          0b00011111,
          0b00011111,
          0b00011111,
      },
      {
          0b00011111,
          0b00011111,
          0b00011111,
          0b00001111,
          0b00001111,
          0b00001111,
          0b00000111,
          0b00000011,
      },
      {
          0b00011111,
          0b00011111,
          0b00011111,
          0b00011110,
          0b00011110,
          0b00011110,
          0b00011100,
          0b00011000,
      },
  };

  unsigned char acedio[2][16] = {
      {0x00, 0x01, 0x20, 0x00, 0x03, 0x20, 0xFF, 0x03, 0x20, 0xFF, 0x01, 0x20,
       0x01, 0x20, 0x00, 0x01},
      {0x02, 0xFF, 0x20, 0x02, 0x01, 0x20, 0x02, 0xFF, 0x20, 0xFF, 0x03, 0x20,
       0x02, 0x20, 0x02, 0x03},
  };

  lcd_custom_char(0, acedio_chars[0]);
  lcd_custom_char(1, acedio_chars[1]);
  lcd_custom_char(2, acedio_chars[2]);
  lcd_custom_char(3, acedio_chars[3]);

  lcd_write(0x80, 0);
  lcd_wait();
  int c;
  for (c = 0; c < 16; ++c) {
    lcd_write_char(acedio[0][c]);
  }

  lcd_write(0xC0, 0);
  lcd_wait();
  for (c = 0; c < 16; ++c) {
    lcd_write_char(acedio[1][c]);
  }
}

int main(void) {
  DDRB =  _BV(DDB1) | _BV(DDB2) | _BV(DDB3);
  // Enable pullups on the input ports.
  PORTB = _BV(PB0) | _BV(PB4) | _BV(PB5);

  lcd_init();

  lcd_custom_char(0, smile);

  acedio();

  while (1) {
    lcd_out(0, LCD_LED);
    _delay_ms(500);
    lcd_out(0, 0);
    _delay_ms(500);
  }
}
