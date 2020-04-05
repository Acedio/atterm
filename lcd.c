#include "lcd.h"

#include <avr/io.h>

// Keyboard pins
// PB0 - LCD busy pin and the MSB of the LCD bus.
// PB1 - Serial out to the shift registers (USI default).
// PB2 - Clock for serial input on the shift registers (USI default).
// PB3 - Clock for the outputs on the shift registers.
#define SER_BUSY_PIN 0
#define SER_OUT_PIN 1
#define SER_CLK_PIN 2
#define SER_LATCH_PIN 3

// Shifts the contents of the flag register into the address register and writes
// |b| to the flag register. The output pin will need to be clocked before this
// change is propagated to the register pins.
void ser_byte(unsigned char b) {
  // Enable USI.
  USIDR = b;
  USISR = _BV(USIOIF);

  do {
    USICR = _BV(USIWM0) | _BV(USICS1) | _BV(USICLK) | _BV(USITC);
  } while ((USISR & _BV(USIOIF)) == 0);

  // Turn off USI.
  USICR = 0;
}

void lcd_out(unsigned char address, unsigned char flags) {
  ser_byte(address);
  ser_byte(flags);

  PORTB &= ~_BV(SER_LATCH_PIN);
  PORTB |= _BV(SER_LATCH_PIN);
}

void lcd_wait() {
  do {
    // Pin changes during a read look to be triggered on E rising, so need to
    // loop to poll.
    // TODO: Can shorten these to 8 bits (no address).
    lcd_out(0, LCD_RW_READ);
    lcd_out(0, LCD_E | LCD_RW_READ);
  } while (PINB & _BV(SER_BUSY_PIN));
}

void lcd_write(unsigned char address, unsigned char flags) {
  // Writes look to be triggered on E falling.
  lcd_out(address, flags | LCD_E);
  lcd_out(address, flags & ~LCD_E);
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

void lcd_enable() {
  DDRB |= _BV(SER_OUT_PIN);
}

void lcd_disable() {
  DDRB &= ~_BV(SER_OUT_PIN);
  // Enable pull-up.
  PORTB |= _BV(SER_OUT_PIN);
}

void lcd_init() {
  // Busy pin is always an input.
  DDRB &= ~_BV(SER_BUSY_PIN);
  // Enable pullups on the busy pin.
  PORTB |= _BV(SER_BUSY_PIN);

  // CLK and LATCH are always outputs.
  DDRB |= _BV(SER_CLK_PIN) | _BV(SER_LATCH_PIN);
  // Init both to low.
  PORTB &= ~(_BV(SER_CLK_PIN) | _BV(SER_LATCH_PIN));

  lcd_enable();
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

  lcd_disable();
}
