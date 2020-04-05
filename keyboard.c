#include <avr/io.h>
#include <avr/interrupt.h>
#define F_CPU 8000000UL
#include <util/delay.h>
#include <util/parity.h>

#define DD_BUS DDB1
#define PORT_BUS PB1
#define PIN_BUS PINB1

#define DD_CLK DDB4
#define PORT_CLK PB4
#define PIN_CLK PINB4
#define CLK_PCMSK PCINT4

// Keyboard must be disabled (keyboard clock held low) during LCD operations.
void disable_keyboard() {
  DDRB |= _BV(DD_BUS) | _BV(DD_CLK);
  // Clock low, data high.
  PORTB = (PORTB | _BV(PORT_BUS)) & ~_BV(PORT_CLK);
}

void enable_keyboard() {
  DDRB &= ~_BV(DD_BUS) & ~_BV(DD_CLK);
  // Enable pullups.
  PORTB |= _BV(PORT_BUS) | _BV(PORT_CLK);
}

#define PS2_ERROR 0
#define PS2_START 1
#define PS2_BIT0 2
#define PS2_BIT1 3
#define PS2_BIT2 4
#define PS2_BIT3 5
#define PS2_BIT4 6
#define PS2_BIT5 7
#define PS2_BIT6 8
#define PS2_BIT7 9
#define PS2_PARITY 10
#define PS2_STOP 11

unsigned char kb_state;
unsigned char kb_byte;

ISR(PCINT0_vect) {
  // Read bus on the falling clock edge.
  if (!(PINB & _BV(PIN_CLK))) {
    // TODO: Waiting here is necessary but shouldn't hold up everything else on
    // the MCU.
    _delay_us(25);
    unsigned char b = PINB & _BV(PIN_BUS);
    switch (kb_state) {
      case PS2_START: {
        if (b) {
          kb_state = PS2_ERROR;
        } else {
          kb_byte = 0;
          kb_state = PS2_BIT0;
        }
        break;
      }
      case PS2_BIT0:
      case PS2_BIT1:
      case PS2_BIT2:
      case PS2_BIT3:
      case PS2_BIT4:
      case PS2_BIT5:
      case PS2_BIT6:
      case PS2_BIT7: {
        kb_byte >>= 1;
        if (b) {
          kb_byte |= 0x80;
        }
        ++kb_state;
        break;
      }
      case PS2_PARITY: {
        if (parity_even_bit(kb_byte) && b || !parity_even_bit(kb_byte) && !b) {
          kb_state = PS2_ERROR;
        } else {
          kb_state = PS2_STOP;
        }
        break;
      }
      case PS2_STOP: {
        if (!b) {
          kb_state = PS2_ERROR;
        } else {
          kb_state = PS2_START;
          // Blink LED on 'A'.
          if (kb_byte == 0x1C) {
            led(1);
            _delay_ms(100);
            led(0);
          }
        }
        break;
      }
      default:
        kb_state = PS2_ERROR;
        break;
    }
  }

  if (kb_state == PS2_ERROR) {
    led(1);
    disable_keyboard();
    // _delay_us(150);
    _delay_ms(100);
    enable_keyboard();
    kb_state = PS2_START;
  }
}

int main(void) {
  cli();
  // PB3 = PS/2 bus
  // PB4 = PS/2 clock
  // PB0 = LED
  DDRB = _BV(DDB0);
  // Turn off LED, enable pullups on the input and unused ports.
  PORTB = ~_BV(PB0);

  // Turn off error LED.
  led(0);

  kb_byte = 0;
  kb_state = PS2_START;
  
  disable_keyboard();

  _delay_ms(1000);

  // Enable pin change interrupts on clock pin only.
  PCMSK = _BV(CLK_PCMSK);
  GIMSK = _BV(PCIE);
  GIFR |= _BV(PCIF);
  enable_keyboard();
  sei();

  while (1) {}
}
