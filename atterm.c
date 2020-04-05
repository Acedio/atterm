// ATTiny85 Terminal
//
// == Simplified Schematic ==
//
//   ________________       ________________       ___________________
//  |                |     |                |     |                   |
//  | ATTiny85 (MCU) |-----| 74HC595 (FLAG) |-----| 74HC595 (ADDRESS) |
//  |________________|     |________________|     |___________________|
//                          |  |  |                 |    |
//                          |  |  |           +-/7/-+    +--- TO MCU
//                          |__|__|___________|________  |
//                         |E  RW RS        A0-A6    A7|-*
//                         | HD44780U (LCD controller) |
//                         |___________________________|

// == ATTiny85 Port Assignment ==
//
// PB0 - LCD busy pin and the MSB of the LCD bus.
// PB1 - Serial out to the shift registers.
// PB2 - Clock for serial input on the shift registers.
// PB3 - Clock for the outputs on the shift registers.
// PB4 - PS/2 clock.
// PB5 - Reset pin, left open for programming.

#include "keyboard.h"
#include "lcd.h"

#include <avr/io.h>
#include <avr/interrupt.h>
#define F_CPU 8000000UL
#include <util/delay.h>

// TODO: Add a set of enums that represent the current pin state and set up a
// state machine around them. e.g. state = S_LCD_WRITE would ensure that the
// keyboard clock is held low and state = S_KEYBOARD_READ would enable a pin
// change interrupt on the keyboard clock line and set it as an input.

int main(void) {
  /*
  cli();
  kb_init();

  kb_enable();
  sei();

  while(1) {
    unsigned char b;
    if (kb_read(&b) && b == 0x1C) {
      PORTB ^= _BV(PB0);
    }
  }
  */
  lcd_init();
  lcd_enable();
  acedio();
  lcd_disable();
}
