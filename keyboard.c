#include <avr/io.h>
#include <avr/interrupt.h>
#define F_CPU 8000000UL
#include <util/delay.h>
#include <util/parity.h>

#define KB_BUS_PIN 0
#define KB_CLK_PIN 4
#define KB_CLK_PCMSK PCINT4

// Keyboard must be disabled (keyboard clock held low) during LCD operations.
void kb_disable() {
  PCMSK = 0;
  GIMSK = 0;
  GIFR |= _BV(PCIF);

  DDRB |= _BV(KB_CLK_PIN);
  // Clock low disables the keyboard.
  PORTB &= ~_BV(KB_CLK_PIN);
  // Wait a bit to ensure the keyboard releases the bus pin.
  _delay_us(100);
}

void kb_enable() {
  DDRB &= ~_BV(KB_CLK_PIN);
  // Enable pullups.
  PORTB |= _BV(KB_CLK_PIN);

  // Enable pin change interrupts on clock pin only.
  PCMSK = _BV(KB_CLK_PCMSK);
  GIMSK = _BV(PCIE);
  GIFR |= _BV(PCIF);
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

unsigned char ps2_state;
unsigned char ps2_byte;

#define KB_NORMAL 0
#define KB_BREAK 1
#define KB_EXTENDED 2
#define KB_EXTENDED_BREAK 3
unsigned char kb_state;

#define KB_LSHIFT 0x01
#define KB_RSHIFT 0x02
#define KB_LCTL 0x04
#define KB_RCTL 0x08
#define KB_LALT 0x10
#define KB_RALT 0x20
#define KB_LWIN 0x40
#define KB_RWIN 0x80
#define KB_SHIFT (KB_LSHIFT | KB_RSHIFT)
#define KB_CTL (KB_LCTL | KB_RCTL)
#define KB_ALT (KB_LALT | KB_RALT)
#define KB_WIN (KB_LWIN | KB_RWIN)
unsigned char kb_mods;

// Circular buffer.
#define KB_BUF_LEN 8
#define KB_BUF_LEN_MASK 0x7
unsigned char kb_buf[KB_BUF_LEN];
// The last read byte.
unsigned char kb_cur;
// The last written byte.
unsigned char kb_end;

const unsigned char shift_char_map[] =
  "\0\0\0\0\0\0\0\0\0\0\0\0\0\0~\0"
  "\0\0\0\0\0Q!\0\0\0ZSAW@\0"
  "\0CXDE$#\0\0 VFTR%\0"
  "\0NBHGY^\0\0\0MJU&*\0"
  "\0<KIO)(\0\0>?L:P_\0"
  "\0\0\"\0{+\0\0\0\0\0}\0|\0\0";

const unsigned char char_map[] =
  "\0\0\0\0\0\0\0\0\0\0\0\0\0\0`\0"
  "\0\0\0\0\0q1\0\0\0zsaw2\0"
  "\0cxde43\0\0 vftr5\0"
  "\0nbhgy6\0\0\0mju78\0"
  "\0,kio09\0\0./l;p-\0"
  "\0\0'\0[=\0\0\0\0\0]\0\\\0\0";

void kb_process_byte() {
  if (kb_state == KB_NORMAL) {
    if (ps2_byte == 0xF0) {
      kb_state = KB_BREAK;
    } else if (ps2_byte == 0xE0) {
      kb_state = KB_EXTENDED;
    } else {
      // kb_state stays normal.
      if (ps2_byte < sizeof(char_map)) {
        unsigned char c;
        if (kb_mods & KB_SHIFT) {
          c = shift_char_map[ps2_byte];
        } else {
          c = char_map[ps2_byte];
        }
        if (c != 0) {
          kb_buf[kb_end] = c;
          kb_end = (kb_end + 1) & KB_BUF_LEN_MASK;
          return;
        }
      }
      switch (ps2_byte) {
        case 0x11:
          kb_mods |= KB_LALT;
          break;
        case 0x12:
          kb_mods |= KB_LSHIFT;
          break;
        case 0x14:
          kb_mods |= KB_LCTL;
          break;
        case 0x59:
          kb_mods |= KB_RSHIFT;
          break;
        case 0x76:
          kb_buf[kb_end] = 0;  // ESC
          kb_end = (kb_end + 1) & KB_BUF_LEN_MASK;
        default:
          break;
      }
    }
  } else if (kb_state == KB_BREAK) {
    switch (ps2_byte) {
      case 0x11:
        kb_mods &= ~KB_LALT;
        break;
      case 0x12:
        kb_mods &= ~KB_LSHIFT;
        break;
      case 0x14:
        kb_mods &= ~KB_LCTL;
        break;
      case 0x59:
        kb_mods &= ~KB_RSHIFT;
        break;
      default:
        break;
    }
    kb_state = KB_NORMAL;
  } else if (kb_state == KB_EXTENDED) {
    if (ps2_byte == 0xF0) {
      kb_state = KB_EXTENDED_BREAK;
    } else {
      switch (ps2_byte) {
        case 0x11:
          kb_mods |= KB_RALT;
          break;
        case 0x14:
          kb_mods |= KB_RCTL;
          break;
        case 0x1F:
          kb_mods |= KB_LWIN;
          break;
        case 0x27:
          kb_mods |= KB_RWIN;
          break;
        default:
          break;
      }
      kb_state = KB_NORMAL;
    }
  } else if (kb_state == KB_EXTENDED_BREAK) {
    switch (ps2_byte) {
      case 0x11:
        kb_mods &= ~KB_RALT;
        break;
      case 0x14:
        kb_mods &= ~KB_RCTL;
        break;
      case 0x1F:
        kb_mods &= ~KB_LWIN;
        break;
      case 0x27:
        kb_mods &= ~KB_RWIN;
        break;
      default:
        break;
    }
    kb_state = KB_NORMAL;
  }
}

ISR(PCINT0_vect) {
  // Read bus on the falling clock edge.
  if (!(PINB & _BV(KB_CLK_PIN))) {
    // TODO: Waiting here is necessary but shouldn't hold up everything else on
    // the MCU.
    _delay_us(25);
    unsigned char b = PINB & _BV(KB_BUS_PIN);
    switch (ps2_state) {
      case PS2_START: {
        if (b) {
          ps2_state = PS2_ERROR;
        } else {
          ps2_byte = 0;
          ps2_state = PS2_BIT0;
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
        ps2_byte >>= 1;
        if (b) {
          ps2_byte |= 0x80;
        }
        ++ps2_state;
        break;
      }
      case PS2_PARITY: {
        // Parity + parity bit should be odd.
        unsigned char expected_parity_bit = !parity_even_bit(ps2_byte);
        // Wacky XOR.
        if (!expected_parity_bit != !b) {
          ps2_state = PS2_ERROR;
        } else {
          ps2_state = PS2_STOP;
        }
        break;
      }
      case PS2_STOP: {
        if (!b) {
          ps2_state = PS2_ERROR;
        } else {
          kb_process_byte();
          ps2_state = PS2_START;
        }
        break;
      }
      default:
        ps2_state = PS2_ERROR;
        break;
    }
  }

  if (ps2_state == PS2_ERROR) {
    kb_disable();
    _delay_us(150);
    kb_enable();
    ps2_state = PS2_START;
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
  // Bus is always input.
  DDRB &= ~_BV(KB_BUS_PIN);
  // Enable pull-up.
  PORTB |= _BV(KB_BUS_PIN);
  ps2_state = PS2_START;
  ps2_byte = 0;
  
  kb_state = KB_NORMAL;
  kb_mods = 0;
  kb_cur = 0;
  kb_end = 0;
  
  kb_disable();

  _delay_ms(1000);
}
