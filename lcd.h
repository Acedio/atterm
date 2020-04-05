#ifndef LCD_H
#define LCD_H

// Two shift registers control inputs to the LCD:
//  - The first is the flag register. See the flag constants below.
//  - The second is the address register. The MSB is the only LCD pin that is
//    readable by the MCU, and is available on PB0.

// == LCD FLAG REGISTER FLAGS ==
// LCD_E is the enable bit for sending data to the LCD. Reads are triggered by a
// rising edge, writes are triggered by a falling edge.
#define LCD_E 0x80
// When LCD_RW_READ is set, puts the LCD into a read state. Unset = write.
// Setting the LCD_RW_READ bit also turns off the address register outputs so
// the pins are in a high impedence state and don't short :P
#define LCD_RW_READ 0x40
// When LCD_RS_DR is set, selects the data register (DR). When unset, selects
// the instruction register (IR).
#define LCD_RS_DR 0x20
// Drives an LED when set.
#define LCD_LED 0x10

void lcd_init();

void lcd_enable();
void lcd_disable();

// Writes |address| and |flags| to the associated shift register and clocks the
// output to propagate the new contents to the output pins.
void lcd_out(unsigned char address, unsigned char flags);
// Waits for the LCD to be free for instructions.
void lcd_wait();
// Same as lcd_out, but handles the rise and fall of the E pin.
void lcd_write(unsigned char address, unsigned char flags);
void lcd_write_char(unsigned char c);

// Writes "acedio" to the LCD.
void acedio();

#endif  // LCD_H
