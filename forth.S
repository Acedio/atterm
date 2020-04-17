; Need some way of having both SRAM words and PROGMEM words.
; If this is token-based, maybe signify in the LSB what kind of word the token
; is for?

#include <avr/io.h>

; The interpreter pointer is r25:r24
.set IP_LREG, 24
; The data stack pointer is Y (r28)
.set DS_LREG, 28
.set CODEWORD_SIZE, 2

RS0 = 0x100
DS0 = 0x180

LED_PIN = PB4

.text
; Interrupt vectors.
rjmp reset
rjmp reset
rjmp reset
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop

.macro JMP label
  ldi ZL, lo8(pm(\label))
  ldi ZH, hi8(pm(\label))
  ijmp
.endm

reset:
cli
JMP main

; Must use the register number (e.g. 24 instead of r24)
.macro PUSHRSP reg
  push \reg
  push \reg + 1
.endm

.macro POPRSP reg
  pop \reg + 1
  pop \reg
.endm

.macro PUSHDSP reg
  st -Y, \reg
  st -Y, \reg + 1
.endm

.macro POPDSP reg
  ld \reg + 1, Y+
  ld \reg, Y+
.endm

DOCOL:
  PUSHRSP IP_LREG
  ; r23:22 contains the codeword's address.
  movw IP_LREG, r22
  ; Skip past the codeword to get to the first token.
  adiw IP_LREG, CODEWORD_SIZE
; Execute NEXT immediately.
NEXT:
  ; Load the next token, which is an offset into the token table.
  movw ZL, IP_LREG ; load the address of the next token
  adiw IP_LREG, 1 ; increment the IP
  ; Load the token index into ZL. ZH is constant
  lpm ZL, Z
  ldi ZH, hi8(TOKEN_TABLE)

  ; Load the codeword's address from the token table. Keep it in r22 so DOCOL
  ; can read it later.
  lpm r22, Z+
  lpm r23, Z
  movw ZL, r22

  ; The codeword contains the address of the code to run for this word, so we
  ; need to jump to the address stored at the codeword.
  lpm r20, Z+
  lpm r21, Z
  movw ZL, r20
  ; Execute the codeword.
  ijmp

.macro fw name
  .byte T_\name - TOKEN_TABLE
.endm

.macro lit word
  fw LIT
  .word \word
.endm

.global main
main:
  cli
  sbi _SFR_IO_ADDR(DDRB), LED_PIN
  cbi _SFR_IO_ADDR(PORTB), LED_PIN
  ; Intialize return stack
  ldi r16, lo8(RS0)
  out _SFR_IO_ADDR(SPL), r16
  ldi r16, hi8(RS0)
  out _SFR_IO_ADDR(SPH), r16

  ; Initialize data stack
  ldi DS_LREG, lo8(DS0)
  ldi DS_LREG+1, hi8(DS0)

  ; Initialize the interpreter pointer
  ldi IP_LREG, lo8(cold_start)
  ldi IP_LREG+1, hi8(cold_start)
  ; Call NEXT to kick things off.
  JMP NEXT

cold_start:
  ; The default program!
  fw INITRAM
  fw SERINIT

  fw LCDINIT

  fw TRUE
  fw LEDSTORE

  fw LOOP
  fw TRUE
  fw WHILE

.set F_IMMED,0x80
.set F_HIDDEN,0x20
.set F_LENMASK,0x1f
.set link,0

.macro defword name, flags=0, label
  .text
  .balign 2
  .global name_\label
name_\label :
  .word link ; link to the previously defined word
  .set link,name_\label
  .byte \flags|(nameend_\label - . - 3) ; flags + length of the name
  .ascii "\name" ; the name
nameend_\label :
  .balign 2
  .global \label
\label :
  .word pm(DOCOL) ; Codeword
  ; list of word tokens follow
.endm

.macro defcode name, flags=0, label
  .text
  .balign 2
  .global name_\label
name_\label :
  .word link ; link to the previously defined word
  .set link,name_\label
  .byte \flags|(nameend_\label - . - 1) ; flags + length of the name
  .ascii "\name" ; the name
nameend_\label :
  .balign 2
  .global \label
\label :
  .word pm(code_\label) ; Codeword
  .balign 2
  .global code_\label
code_\label :
  ; list of word tokens follow
.endm

defword "WAIT",,WAIT
  ; D: T R:
  fw LOOP ; D: T R: LOOP
  fw DECR ; D: T-1 R: LOOP
  fw DUP  ; D: T-1 T-1 R: LOOP
  fw ZEQU ; D: =0 T-1 R: LOOP
  fw INVERT ; D: !=0 T-1 R: LOOP
  fw WHILE ; D: T-1 R: LOOP
  fw RDROP
  fw DROP ; D: empty R: empty
  fw EXIT

defcode "LED!",,LEDSTORE
  POPDSP 0
  cbi _SFR_IO_ADDR(PORTB), LED_PIN
  or r0, r1
  breq 1f
  sbi _SFR_IO_ADDR(PORTB), LED_PIN
1:
  JMP NEXT

; Blinks the LED if top of stack = 0, holds steady if != 0.
defword "TESTLED",,TESTLED
  fw INVERT ; Blink if false.
  fw LOOP

  fw FALSE
  fw LEDSTORE

  lit 0x0FFF
  fw WAIT

  fw TRUE
  fw LEDSTORE

  lit 0x0FFF
  fw WAIT

  fw DUP
  fw WHILE
  fw RDROP

  fw LOOP
  fw TRUE
  fw WHILE

defword "BLINK",,BLINK
  fw LOOP

  fw LCD_LED
  fw LCD_RW_READ
  fw OR
  fw TOSER
  lit 0x0FFF
  fw WAIT

  fw LCD_RW_READ
  fw OR
  fw TOSER
  lit 0x0FFF
  fw WAIT

  fw TRUE
  fw WHILE

defcode "DROP",,DROP
  adiw Y, 2
  JMP NEXT

defcode "SWAP",,SWAP
  POPDSP 0
  POPDSP 2
  PUSHDSP 0
  PUSHDSP 2
  JMP NEXT

defcode "DUP",,DUP
  ; MSB is top of stack, LSB is next
  ldd r0, Y+1
  ld r1, Y
  PUSHDSP 0
  JMP NEXT

defcode "OVER",,OVER
  ldd r0, Y+3
  ldd r1, Y+2
  PUSHDSP 0
  JMP NEXT

defcode "ROT",,ROT
  ; Bring the third item to the top.
  POPDSP 0
  POPDSP 2
  POPDSP 4
  PUSHDSP 2
  PUSHDSP 0
  PUSHDSP 4
  JMP NEXT

defcode "EXIT",,EXIT
  POPRSP IP_LREG
  JMP NEXT

defword "-ROT",,NROT
  fw ROT
  fw ROT
  fw EXIT

defword "2DROP",,TWODROP
  fw DROP
  fw DROP
  fw EXIT

defword "2DUP",,TWODUP
  fw OVER
  fw OVER
  fw EXIT

defcode "LIT",,LIT
  ; Push the next word onto the data stack.
  movw ZL, IP_LREG
  adiw IP_LREG, 2
  lpm r0, Z+
  lpm r1, Z
  PUSHDSP 0
  JMP NEXT

defcode "+",,ADD
  POPDSP 0
  POPDSP 2
  add r0, r2
  adc r1, r3
  PUSHDSP 0
  JMP NEXT

defcode "-",,SUB
  POPDSP 0
  POPDSP 2
  sub r0, r2
  sbc r1, r3
  PUSHDSP 0
  JMP NEXT

defword "1+",,INCR
  lit 1
  fw ADD
  fw EXIT

defword "1-",,DECR
  lit -1
  fw ADD
  fw EXIT

defcode "AND",,AND
  POPDSP 0
  POPDSP 2
  and r0, r2
  and r1, r3
  PUSHDSP 0
  JMP NEXT

defcode "OR",,OR
  POPDSP 0
  POPDSP 2
  or r0, r2
  or r1, r3
  PUSHDSP 0
  JMP NEXT

defcode "XOR",,XOR
  POPDSP 0
  POPDSP 2
  eor r0, r2
  eor r1, r3
  PUSHDSP 0
  JMP NEXT

defcode "INVERT",,INVERT
  POPDSP 0
  com r0
  com r1
  PUSHDSP 0
  JMP NEXT

; Switch the high and low bytes.
defcode "SWIZZLE",,SWIZZLE
  POPDSP 0
  mov r2, r0
  mov r0, r1
  mov r1, r2
  PUSHDSP 0
  JMP NEXT

defcode "0=",,ZEQU
  POPDSP 30
  ser r16
  adiw r30, 0
  breq 1f 
  clr r16 ; Clear all bits in r16 if the Z flag is cleared.
1:
  mov r17, r16 ; Mirror into r16
  PUSHDSP 16
  JMP NEXT

defcode "0>",,ZGT
  POPDSP 30
  ser r16
  adiw r30, 0
  brlt 1f 
  clr r16 ; Clear all bits in r16 if the Z flag is cleared.
1:
  mov r17, r16 ; Mirror into r16
  PUSHDSP 16
  JMP NEXT

defword "0<",,ZLT
  fw DUP
  fw ZEQU
  fw INVERT
  fw SWAP
  fw ZGT
  fw INVERT
  fw AND
  fw EXIT

defword "=",,EQU
  fw SUB
  fw ZEQU
  fw EXIT

defword ">",,GT
  fw SUB
  fw ZLT
  fw EXIT

defword "<",,LT
  fw SUB
  fw ZGT
  fw EXIT

defcode "C!",,STOREBYTE
  POPDSP 30 ; address
  POPDSP 0 ; data
  st Z, r0
  JMP NEXT

defcode "C@",,FETCHBYTE
  POPDSP 30 ; address
  ld r16, Z
  ldi r17, 0
  PUSHDSP 16
  JMP NEXT

; (addr data -- )
defword "!",,STORE
  ; Store high byte.
  fw OVER
  fw SWIZZLE
  fw OVER
  fw INCR
  fw STOREBYTE
  ; Store low byte.
  fw STOREBYTE
  fw EXIT

; (addr -- data)
defword "@",,FETCH
  fw DUP
  ; Low byte
  fw FETCHBYTE
  fw SWAP
  ; High byte
  fw INCR
  fw FETCHBYTE
  fw SWIZZLE
  ; Combine
  fw OR
  fw EXIT

.macro defvar name, flags=0, label, initial=0
  defcode \name,\flags,\label
  ldi r16, lo8(var_\label)
  ldi r17, hi8(var_\label)
  PUSHDSP 16
  JMP NEXT
  .data
var_\label:
  .word \initial
  .text
.endm

defvar "STATE",,STATE
defvar "HERE",,HERE
defvar "LATEST",,LATEST,name_F_LENMASK  ; TODO: last word in dictionary
defvar "S0",,SZ,DS0
defvar "BASE",,BASE,10

defcode "INITRAM",,INITRAM
  ldi ZL, lo8(__data_load_start)
  ldi ZH, hi8(__data_load_start)
  ldi XL, lo8(__data_start)
  ldi XH, hi8(__data_start)
1:
  lpm r0, Z+
  st X+, r0
  ldi r16, lo8(__data_load_end)
  ldi r17, hi8(__data_load_end)
  sub r16, ZL
  sbc r17, ZH
  or r16, r17
  brne 1b
  JMP NEXT

.macro defconst name, flags=0, label, value
  defcode \name,\flags,\label
  ldi r16, lo8(\value)
  ldi r17, hi8(\value)
  PUSHDSP 16
  JMP NEXT
.endm

defconst "R0",,RZ,RS0
defconst "DOCOL",,__DOCOL,DOCOL
defconst "F_IMMED",,F_IMMED,F_IMMED
defconst "F_HIDDEN",,F_HIDDEN,F_HIDDEN
defconst "F_LENMASK",,F_LENMASK,F_LENMASK
defconst "TRUE",,TRUE,0xFFFF
defconst "FALSE",,FALSE,0x0

defcode ">R",,TOR
  POPDSP 0
  PUSHRSP 0
  JMP NEXT

defcode "R>",,FROMR
  POPRSP 0
  PUSHDSP 0
  JMP NEXT

defcode "RSP@",,RSPFETCH
  in r0, _SFR_IO_ADDR(SPL)
  in r1, _SFR_IO_ADDR(SPH)
  PUSHDSP 0
  JMP NEXT

defcode "RSP!",,RSPSTORE
  POPDSP 0
  out _SFR_IO_ADDR(SPL), r0
  out _SFR_IO_ADDR(SPH), r1
  JMP NEXT

defcode "RDROP",,RDROP
  POPRSP 0
  JMP NEXT

defcode "DSP@",,DSPFETCH
  ; PUSHDSP isn't atomic, so need to buffer it via a different register.
  movw r0, DS_LREG
  PUSHDSP 0
  JMP NEXT

defcode "DSP!",,DSPSTORE
  ; POPDSP isn't atomic, so need to buffer it via a different register.
  POPDSP 0
  movw DS_LREG, r0
  JMP NEXT

; DUPs the return address so that a copy of the LOOP point still exists even
; after EXITing from this word.
defword "LOOP",,LOOP
  fw FROMR
  fw DUP
  fw TOR
  fw TOR
  fw EXIT

; pred a b -- pred ? a : b
defword "TERN",,TERN
  fw DUP
  fw ROT
  fw AND
  fw NROT
  fw INVERT
  fw AND
  fw OR
  fw EXIT

; Calculate the Nth triangle number with some awful stack manipulation.
; n -- the nth triangle number
defword "TRI",,TRI
  lit 0 ; running sum
  fw LOOP ; D: SUM N -- R: LOOP

  fw OVER ; N SUM N
  fw ADD  ; NSUM N
  fw SWAP ; N NSUM
  fw DECR ; N-1 NSUM
  fw SWAP ; NSUM N-1
  fw OVER ; N-1 NSUM N-1
  fw ZEQU  ; ISZERO NSUM N-1
  fw INVERT ; !ISZERO NSUM N-1
  fw WHILE
  fw RDROP

  fw ADD ; Drop the arg (which is 0 now)
  fw EXIT

; Branches to the top of RSP if COND, else exits normally. Caller needs to RDROP
; the loop point after the loop terminates.
defword "WHILE",,WHILE
  ; D: COND R: NORMAL IFTRUE
  fw FROMR ; NORMAL COND
  fw FROMR ; IFTRUE NORMAL COND
  fw DUP
  fw TOR   ; D: IFTRUE NORMAL COND R: IFTRUE
  fw ROT   ; D: COND IFTRUE NORMAL R: IFTRUE
  fw TERN  ; D: next R: IFTRUE
  fw TOR
  ; Maybe conditionally RDROP so the caller doesn't have to?
  fw EXIT

defconst "LCD_E",,LCD_E,0x80
defconst "LCD_RW_READ",,LCD_RW_READ,0x40
defconst "LCD_RS_DR",,LCD_RS_DR,0x20
defconst "LCD_LED",,LCD_LED,0x10

#define LCD_BUSY_PIN 0
#define SER_DATA_PIN 1
#define SER_CLK_PIN 2
#define SER_LATCH_PIN 3

defcode "SERINIT",,SERINIT
  cbi _SFR_IO_ADDR(DDRB), LCD_BUSY_PIN
  sbi _SFR_IO_ADDR(PORTB), LCD_BUSY_PIN

  ; CLK, LATCH, and OUT are always outputs.
  sbi _SFR_IO_ADDR(DDRB), SER_CLK_PIN
  sbi _SFR_IO_ADDR(DDRB), SER_LATCH_PIN
  sbi _SFR_IO_ADDR(DDRB), SER_DATA_PIN
  ; Init all to low.
  cbi _SFR_IO_ADDR(PORTB), SER_CLK_PIN
  cbi _SFR_IO_ADDR(PORTB), SER_LATCH_PIN
  cbi _SFR_IO_ADDR(PORTB), SER_DATA_PIN
  JMP NEXT

defcode "SERLATCH",,SERLATCH
  cbi _SFR_IO_ADDR(PORTB), SER_LATCH_PIN
  sbi _SFR_IO_ADDR(PORTB), SER_LATCH_PIN
  JMP NEXT

; Must set the LCD to LCD_RW_READ first.
defcode "LCDBUSY",,LCDBUSY
  ldi r16, 0
  sbic _SFR_IO_ADDR(PINB), LCD_BUSY_PIN
  ldi r16, 0xFF ; port is busy
  mov r17, r16
  PUSHDSP 16
  JMP NEXT

defcode "B>SER",,BYTETOSER
  POPDSP 0
  ; Load the byte into the data register.
  out _SFR_IO_ADDR(USIDR), r0
  ; Reset the clock counter.
  ldi r16, _BV(USIOIF)
  out _SFR_IO_ADDR(USISR), r16

  ; Pulse clock until sent.
  ldi r16, _BV(USIWM0) | _BV(USICS1) | _BV(USICLK) | _BV(USITC)
1:
  out _SFR_IO_ADDR(USICR), r16
  sbis _SFR_IO_ADDR(USISR), USIOIF
  rjmp 1b

  ; Turn off USI.
  ldi r16, 0
  out _SFR_IO_ADDR(USICR), r16
  JMP NEXT

defword ">SER",,TOSER
  ; High byte (address) first.
  fw DUP
  fw SWIZZLE
  fw BYTETOSER

  ; Then the low byte (flags).
  fw BYTETOSER

  fw SERLATCH
  fw EXIT

defword "LCDWAIT",,LCDWAIT
  fw LOOP
  fw LCD_RW_READ
  fw TOSER
  fw LCD_RW_READ
  fw LCD_E
  fw OR
  fw TOSER
  fw LCDBUSY
  fw WHILE
  fw RDROP

  ; Bring LCD_E low so it's in a consistent state.
  fw LCD_RW_READ
  fw TOSER
  fw EXIT

defword "LCDCMD",,LCDCMD
  fw LCDWAIT ; Wait for free.

  fw DUP
  fw LCD_E
  fw OR
  fw TOSER ; Clock E high first (should already be low).

  fw LCD_E
  fw INVERT
  fw AND
  fw TOSER ; Then low.

  fw EXIT

defword "LCDINIT",,LCDINIT
  lit 0x3800
  fw LCDCMD
  lit 0x0100
  fw LCDCMD
  lit 0x0F00
  fw LCDCMD
  fw EXIT

; High byte is address and is sent first.
.text
.balign 256
TOKEN_TABLE:
.include "token_table.i"
