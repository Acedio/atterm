#include <avr/io.h>
#include <avr/interrupt.h>
#define F_CPU 8000000UL
#include <util/delay.h>
#include <util/parity.h>

#define KB_BUS_DD DDB1
#define KB_BUS_PORT PB1
#define KB_BUS_PIN PINB1

#define KB_CLK_DD DDB4
#define KB_CLK_PORT PB4
#define KB_CLK_PIN PINB4
#define KB_CLK_PCMSK PCINT4

// Keyboard must be disabled (keyboard clock held low) during LCD operations.
void kb_disable() {
  DDRB |= _BV(KB_BUS_DD) | _BV(KB_CLK_DD);
  // Clock low, data high.
  PORTB = (PORTB | _BV(KB_BUS_PORT)) & ~_BV(KB_CLK_PORT);
}

void kb_enable() {
  DDRB &= ~_BV(KB_BUS_DD) & ~_BV(KB_CLK_DD);
  // Enable pullups.
  PORTB |= _BV(KB_BUS_PORT) | _BV(KB_CLK_PORT);
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

// Circular buffer.
#define KB_BUF_LEN 8
#define KB_BUF_LEN_MASK 0x7
unsigned char kb_buf[KB_BUF_LEN];
// The last read byte.
unsigned char kb_cur;
// The last written byte.
unsigned char kb_end;

ISR(PCINT0_vect) {
  // Read bus on the falling clock edge.
  if (!(PINB & _BV(KB_CLK_PIN))) {
    // TODO: Waiting here is necessary but shouldn't hold up everything else on
    // the MCU.
    _delay_us(25);
    unsigned char b = PINB & _BV(KB_BUS_PIN);
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
        if ((parity_even_bit(kb_byte) && b) ||
            (!parity_even_bit(kb_byte) && !b)) {
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
          kb_buf[kb_end] = kb_byte;
          kb_end = (kb_end + 1) & KB_BUF_LEN_MASK;
          kb_state = PS2_START;
        }
        break;
      }
      default:
        kb_state = PS2_ERROR;
        break;
    }
  }

  if (kb_state == PS2_ERROR) {
    kb_disable();
    _delay_us(150);
    kb_enable();
    kb_state = PS2_START;
  }
}

unsigned char kb_bytes_ready() {
  if (kb_cur > kb_end) {
    return kb_end + 8 - kb_cur;
  } else {
    return kb_end - kb_cur;
  }
}

unsigned char kb_read(unsigned char* out) {
  if (!out) {
    return 0;
  } else if (kb_bytes_ready() > 0) {
    *out = kb_buf[kb_cur];
    kb_cur = (kb_cur + 1) & KB_BUF_LEN_MASK;
    return 1;
  } else {
    return 0;
  }
}

void kb_init() {
  kb_byte = 0;
  kb_state = PS2_START;
  kb_cur = 0;
  kb_end = 0;
  
  kb_disable();

  _delay_ms(1000);

  // Enable pin change interrupts on clock pin only.
  PCMSK = _BV(KB_CLK_PCMSK);
  GIMSK = _BV(PCIE);
  GIFR |= _BV(PCIF);
}
