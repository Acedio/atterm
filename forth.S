; Need some way of having both SRAM words and PROGMEM words.
; If this is token-based, maybe signify in the LSB what kind of word the token
; is for?

#include <avr/io.h>

; The interpreter pointer is r25:r24
.set IP_LREG, 24
; The data stack pointer is Y (r28)
.set DS_LREG, 28
.set CODEWORD_SIZE, 2

.set PS2_STATE_REG, 8
.set PS2_DATA_REG, 9

RS0 = 0x100
DS0 = 0x180

#define KB_BUS_PIN 0
#define KB_CLK_PIN 4

#define LCD_BUSY_PIN 0
#define SER_DATA_PIN 1
#define SER_CLK_PIN 2
#define SER_LATCH_PIN 3

.text
; Interrupt vectors.
rjmp reset ; RESET
rjmp reset ; INT0
rjmp pcint0 ; PCINT0
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
  rjmp \label
.endm

reset:
JMP main

; == KEYBOARD ROUTINES ==

#define PS2_ERROR 0
#define PS2_START 1
; 2-9 are data bits
#define PS2_PARITY 10
#define PS2_STOP 11

#define KBUF_SIZE 0x08
#define KBUF_MASK 0x07

; Interrupt called whenever the PS2 clock pin changes.
pcint0:
  ; We read the data pin when the clock falls, so return if it's high.
  sbic _SFR_IO_ADDR(PINB), KB_CLK_PIN
  reti

  push r30
  push r31
  in r30, _SFR_IO_ADDR(SREG)
  push r30

  rcall kb_clk_fall

  pop r30
  out _SFR_IO_ADDR(SREG), r30
  pop r31
  pop r30
  reti

kb_clk_fall:
  ; Wait ~25us because we should read the data line in between clock pulses.
  ; TODO: Waiting is necessary but should probably let other processes continue.
  ldi r30, 67
1:
  dec r30  ; 1 clk
  brne 1b ; 2 clk on loop

  ; Read bus pin
  in r31, _SFR_IO_ADDR(PINB)

  mov r30, PS2_STATE_REG

  ; <= 0 is Error
  tst r30
  brlt ps2_error
  breq ps2_error
  cpi r30, PS2_START
  breq ps2_start
  cpi r30, PS2_PARITY
  ; If > START and < PARITY, this is a data bit.
  brlt ps2_data
  breq ps2_parity
  cpi r30, PS2_STOP
  breq ps2_stop
  ; Fall through to ps2_error if >PS2_STOP
  
ps2_error:
  ; hold clk low for ~100us
  sbi _SFR_IO_ADDR(DDRB), KB_CLK_PIN
  cbi _SFR_IO_ADDR(PORTB), KB_CLK_PIN
  clr r30
1:
  dec r30  ; 1 clk
  brne 1b ; 2 clk on loop
  ; release clk, enable pullup
  cbi _SFR_IO_ADDR(DDRB), KB_CLK_PIN
  sbi _SFR_IO_ADDR(PORTB), KB_CLK_PIN

  ; reset status register
  ldi r30, PS2_START
  mov PS2_STATE_REG, r30
  ret
ps2_start:
  ; Start bit is low.
  andi r31, _BV(KB_BUS_PIN)
  brne ps2_error ; nz = error
  clr PS2_DATA_REG
  inc PS2_STATE_REG
  ret
ps2_data: ; low bit first
  ; Put bit into carry
  clc
  sbrc r31, KB_BUS_PIN
  sec
  ror PS2_DATA_REG ; rotate carry into high bit of data register
  inc PS2_STATE_REG
  ret
ps2_parity:
  andi r31, _BV(KB_BUS_PIN)
  ; This could probably be more efficient.
  ; Basically, if we EOR all bits together we should get a 1 (odd parity).
  eor r31, PS2_DATA_REG ; Combine the parity bit into the data register.
  mov r30, r31
  swap r30     ; swap nibbles
  eor r31, r30 ; eor high nibble into low nibble
  mov r30, r31
  lsr r30
  lsr r30
  eor r31, r30 ; eor bits 2-3 into bits 0-1
  mov r30, r31
  lsr r30
  eor r31, r30 ; eor bit 1 into bit 0
  sbrs r31, 0  ; Lowest bit should be 1 now (with the parity bit parity is odd)
  rjmp ps2_error
  inc PS2_STATE_REG
  ret
ps2_stop:
  ; Stop bit is high.
  andi r31, _BV(KB_BUS_PIN)
  breq ps2_error ; zero = error

  ; KBIN is an index and only uses the lo8.
  ldi r30, lo8(var_KBIN)
  ldi r31, hi8(var_KBIN)
  ; Using PS2_STATE_REG as temporary storage here since it will be reset later.
  ld PS2_STATE_REG, Z+
  ldi r30, lo8(var_KBUF)
  ldi r31, hi8(var_KBUF)
  add r30, PS2_STATE_REG
  st Z+, PS2_DATA_REG ; KBUF[KBIN] = PS2_DATA_REG

  ; Now determine the new KBIN. It's .balign 8'd, so just mask the bottom 3 bits
  andi r30, KBUF_MASK
  mov PS2_STATE_REG, r30
  ldi r30, lo8(var_KBIN)
  ldi r31, hi8(var_KBIN)
  st Z, PS2_STATE_REG
  
  ldi r30, PS2_START
  mov PS2_STATE_REG, r30
  ret

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

.global main
main:
  cli
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

.macro fw name
  .byte T_\name - TOKEN_TABLE
.endm

.macro lit word
  fw LIT
  .word \word
.endm

.macro zbranch rel
  fw ZBRANCH
  .word \rel - . - 2
.endm

; The default program!
cold_start:
  ; Wait because the keyboard is noisy on the busy line (TODO: I think?)
  lit 0x3FFF
  fw WAIT
  fw RAMINIT
  fw SERINIT
  fw LCDINIT
  fw KBINIT

1:
  fw TRUE
  fw LEDSTORE

  fw LCDDISABLE
  fw KBENABLE
  fw KEY
  fw KBDISABLE
  fw LCDCHAR

  fw FALSE
  fw LEDSTORE

  fw FALSE
  zbranch 1b

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

; D: T R:
defword "WAIT",,WAIT
1:
  fw DECR ; D: T-1
  fw DUP  ; D: T-1 T-1
  fw ZEQU ; D: =0 T-1
  zbranch 1b ; D: T-1
  fw DROP ; D: empty
  fw EXIT

defword "LED!",,LEDSTORE
  fw LCD_RW_READ
  fw SWAP
  zbranch 1f
  fw LCD_LED
  fw OR
1:
  fw TOSER
  fw EXIT

; Blinks the LED if top of stack = 0, holds steady if != 0.
defword "TESTLED",,TESTLED
1:
  fw FALSE
  fw LEDSTORE

  lit 0x0FFF
  fw WAIT

  fw TRUE
  fw LEDSTORE

  lit 0x0FFF
  fw WAIT

  fw DUP
  zbranch 1b

1:
  fw FALSE
  zbranch 1b

; Blink indefinitely.
defword "BLINK",,BLINK
1:
  fw LCD_LED
  fw LCD_RW_READ
  fw OR
  fw TOSER
  lit 0x0FFF
  fw WAIT

  fw LCD_RW_READ
  fw TOSER
  lit 0x0FFF
  fw WAIT

  fw FALSE
  zbranch 1b

; Blink latch pin indefinitely.
; Useful to call from ASM when the kernel might be dead.
defcode "LATCHBLINK",,LATCHBLINK
  ldi r26, 0
  ldi r27, 0
  ldi r18, 0
1:
  adiw r26, 1
  brne 1b ; loop if not 0
  inc r18
  sbrs r18, 3
  rjmp 2f
  sbi _SFR_IO_ADDR(PORTB), SER_LATCH_PIN
  rjmp 1b
2:
  cbi _SFR_IO_ADDR(PORTB), SER_LATCH_PIN
  rjmp 1b

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

defcode "ROMC@",,CFROMROM
  POPDSP 30
  lpm r16, Z
  ldi r17, 0
  PUSHDSP 16
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

defcode "2*",,ASL
  POPDSP 0
  lsl r0 ; shift into carry
  rol r1 ; shifts carry into low bit
  PUSHDSP 0
  JMP NEXT

defcode "2/",,ASR
  POPDSP 0
  asr r1 ; leave high bit, shift rest, shift into carry
  ror r0 ; shifts carry into high bit
  PUSHDSP 0
  JMP NEXT

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

defcode "0<",,ZLT
  POPDSP 30
  ser r16
  adiw r30, 0
  brlt 1f 
  clr r16 ; Clear all bits in r16 if the Z flag is cleared.
1:
  mov r17, r16 ; Mirror into r16
  PUSHDSP 16
  JMP NEXT

defword "0>",,ZGT
  fw DUP
  fw ZEQU
  fw ZEQU
  fw SWAP
  fw ZLT
  fw ZEQU
  fw AND
  fw EXIT

defword "=",,EQU
  fw SUB
  fw ZEQU
  fw EXIT

defword "<>",,NEQU
  fw EQU
  fw ZEQU
  fw EXIT

defword ">",,GT
  fw SUB
  fw ZGT
  fw EXIT

defword "<",,LT
  fw SUB
  fw ZLT
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

; KBUF is a ring buffer that stores keyboard input. KBIN and KBOUT are indices
; into the buffer. KBIN is where the next byte will be written, KBOUT is where
; the next byte should be read. The buffer is empty when KBIN = KBOUT.
; TODO: Could store these together in the same word.
defvar "KBIN",,KBIN,0
defvar "KBOUT",,KBOUT,0

defcode "KBUF",,KBUF
  ldi r16, lo8(var_KBUF)
  ldi r17, hi8(var_KBUF)
  PUSHDSP 16
  JMP NEXT
.data
.balign KBUF_SIZE
var_KBUF:
.fill KBUF_SIZE, 1, 0
.text

defcode "RAMINIT",,RAMINIT
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

.macro defstring name, flags=0, label, value
  defconst "\name",\flags,\label,string_\label
string_\label :
  .string "\value"
.endm

defstring "GREETING",,GREETING,"Hello, world!"

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

defcode "KBINIT",,KBINIT
  ; Set bus pin as input and enable pull-up.
  cbi _SFR_IO_ADDR(DDRB), KB_BUS_PIN
  sbi _SFR_IO_ADDR(PORTB), KB_BUS_PIN
  ; Initialize the state machine.
  ldi r16, PS2_START
  mov PS2_STATE_REG, r16
  JMP KBDISABLE

defcode "KBDISABLE",,KBDISABLE
  cli
  clr r16
  out _SFR_IO_ADDR(GIMSK), r16
  out _SFR_IO_ADDR(PCMSK), r16
  ; Clear the interrupt flag by writing one to it.
  ldi r16, _BV(PCIF)
  out _SFR_IO_ADDR(GIFR), r16
  ; Holding the clock low disables the keyboard.
  sbi _SFR_IO_ADDR(DDRB), KB_CLK_PIN
  cbi _SFR_IO_ADDR(PORTB), KB_CLK_PIN
  ; Wait ~100us to ensure the keyboard isn't sending other commands
  ; (1/8000000 seconds * 256 loops * 3 clocks per loop = 96us)
  ldi r16, 0
1:
  dec r16 ; 1 clk
  brne 1b ; 2 clk on loop
  JMP NEXT

defcode "KBENABLE",,KBENABLE
  ; Set CLK as input and enable pullups.
  cbi _SFR_IO_ADDR(DDRB), KB_CLK_PIN
  sbi _SFR_IO_ADDR(PORTB), KB_CLK_PIN
  ; Clear any pending interrupts.
  ldi r16, _BV(PCIF)
  out _SFR_IO_ADDR(GIFR), r16
  ; Enable pin change interrupts on CLK pin.
  sbi _SFR_IO_ADDR(PCMSK), KB_CLK_PIN
  ldi r16, _BV(PCIE)
  out _SFR_IO_ADDR(GIMSK), r16
  sei
  JMP NEXT

defword "KB@",,KBFETCH
  fw KBOUT
  fw FETCH
1:
  fw DUP
  fw KBIN
  fw FETCH
  fw SUB
  zbranch 1b

  ; Increment KBOUT
  fw DUP
  fw INCR
  lit KBUF_MASK
  fw AND
  fw KBOUT
  fw STORE

  ; Read the input
  fw KBUF
  fw ADD
  fw FETCHBYTE

  fw EXIT

KB_MAP:
.ascii \
  "\0\0\0\0\0\0\0\0\0\0\0\0\0\0`\0",\
  "\0\0\0\0\0q1\0\0\0zsaw2\0",\
  "\0cxde43\0\0 vftr5\0",\
  "\0nbhgy6\0\0\0mju78\0",\
  "\0,kio09\0\0./l;p-\0",\
  "\0\0'\0[=\0\0\0\0\0]\0\\\0\0"
.set KB_MAP_LEN, . - KB_MAP

KB_MAP_SHIFT:
.ascii \
  "\0\0\0\0\0\0\0\0\0\0\0\0\0\0~\0",\
  "\0\0\0\0\0Q!\0\0\0ZSAW@\0",\
  "\0CXDE$#\0\0 VFTR%\0",\
  "\0NBHGY^\0\0\0MJU&*\0",\
  "\0<KIO)(\0\0>?L:P_\0",\
  "\0\0\"\0{+\0\0\0\0\0}\0|\0\0"

defvar "KBSTATUS",,KBSTATUS,0
defconst "KBS_BREAK",,KBS_BREAK,0x0001
defconst "KBS_EXTENDED",,KBS_EXTENDED,0x0002
defconst "KBS_LSHIFT",,KBS_LSHIFT,0x0004

; FLAGVAR FLAG --
defword "SETFLAG",,SETFLAG
  fw SWAP
  fw OVER
  fw FETCH
  fw OR
  fw SWAP
  fw STORE
  fw EXIT

; FLAGVAR FLAG
defword "CHECKFLAG",,CHECKFLAG
  fw FETCH
  fw AND
  fw ZEQU
  fw ZEQU
  fw EXIT

defword "KEY",,KEY
key_top:
  fw KBFETCH

  fw DUP
  lit 0xF0 ; break codes
  fw EQU
  zbranch 1f
  fw DROP
  fw KBS_BREAK
  fw KBSTATUS
  fw SETFLAG
  fw FALSE
  zbranch key_top
1:

  fw DUP
  lit 0xE0 ; extended keys
  fw EQU
  zbranch 1f
  fw DROP
  fw KBS_EXTENDED
  fw KBSTATUS
  fw SETFLAG
  fw FALSE
  zbranch key_top
1:

  fw DUP
  lit 0x12 ; left shift
  fw EQU
  zbranch 1f
  fw DROP

  fw KBS_LSHIFT ; The eventual status register value.

  fw KBS_BREAK
  fw KBSTATUS
  fw CHECKFLAG
  zbranch 2f
  ; break shift and clear other flags
  ; NOTE: This assumes there are only three status flags.
  fw DROP
  fw FALSE
2:

  fw KBSTATUS
  fw STORE
  fw FALSE
  zbranch key_top
1:

  ; Past this point, we're always matching a real key (even though we might not
  ; handle it).
  fw KBS_BREAK
  fw KBSTATUS
  fw CHECKFLAG
  fw KBS_EXTENDED
  fw KBSTATUS
  fw CHECKFLAG
  fw OR ; Store for below, but clear the status flags first.

  fw KBSTATUS
  fw FETCH
  fw KBS_LSHIFT
  fw AND
  fw KBSTATUS
  fw STORE

  zbranch 1f
  fw DROP ; Throw out the break codes.
  fw FALSE
  zbranch key_top
1:

  ; Verify it's within the map size.
  fw DUP
  lit KB_MAP_LEN
  fw GT
  fw ZEQU
  zbranch 1f ; if KB_MAP_LEN <= keycode
  fw DROP
  fw FALSE
  zbranch key_top
1:

  ; Determine which map to use.
  lit KB_MAP
  fw KBS_LSHIFT
  fw KBSTATUS
  fw CHECKFLAG
  zbranch 1f
  fw DROP
  lit KB_MAP_SHIFT
1:

  fw ADD
  fw CFROMROM ; KB_MAP[keycode]
  fw DUP
  fw ZEQU
  zbranch 1f
  ; Char is zero in the map and isn't handled.
  zbranch key_top
1:
  fw EXIT

defconst "LCD_E",,LCD_E,0x80
defconst "LCD_RW_READ",,LCD_RW_READ,0x40
defconst "LCD_RS_DR",,LCD_RS_DR,0x20
defconst "LCD_LED",,LCD_LED,0x10

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

; Writes a word to the shift registers.
defword ">SER",,TOSER
  ; High byte first.
  fw DUP
  fw SWIZZLE
  fw BYTETOSER

  ; Then the low byte.
  fw BYTETOSER

  fw SERLATCH
  fw EXIT

defword "LCDWAIT",,LCDWAIT
1:
  fw LCD_RW_READ
  fw TOSER
  fw LCD_RW_READ
  fw LCD_E
  fw OR
  fw TOSER
  fw LCDBUSY
  fw ZEQU
  zbranch 1b

  ; Bring LCD_E low so it's in a consistent state.
  fw LCD_RW_READ
  fw TOSER
  fw EXIT

; Writes an LCD command to the shift register and handles the clocking of E.
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
  ; 8 bits, 2 lines, 5x8
  lit 0x3800
  fw LCDCMD
  ; clear the screen
  lit 0x0100
  fw LCDCMD
  ; Enable screen, cursor, and blinking
  lit 0x0F00
  fw LCDCMD
  fw LCDDISABLE
  fw EXIT

defword "LCDCHAR",,LCDCHAR
  fw SWIZZLE   ; Put char in high byte.
  fw LCD_RS_DR ; Data register.
  fw OR
  fw LCDCMD
  fw EXIT

; Hold the address lines high so the busy pin can be used by other devices.
defword "LCDDISABLE",,LCDDISABLE
  lit 0xFF00
  fw TOSER
  fw EXIT

defword "LCDCLEAR",,LCDCLEAR
  lit 0x0100
  fw LCDCMD
  fw EXIT

; Lowest 4 bits to hex digit
defword "TOHEX",,TOHEX
  lit 0x000F
  fw AND
  fw DUP
  lit 10
  fw GT
  zbranch 1f
  lit '0'
  fw ADD
  fw EXIT
1:
  lit 'A' - 10
  fw ADD
  fw EXIT

defword "WRITEWORD",,WRITEWORD
  lit '0'
  fw LCDCHAR
  lit 'x'
  fw LCDCHAR
  lit 4
1:
  fw SWAP
  fw DUP
  ; Move to bottom nibble
  fw SWIZZLE
  fw ASR
  fw ASR
  fw ASR
  fw ASR
  fw TOHEX
  fw LCDCHAR
  ; Shift left 4 bits to move to the next digit.
  fw ASL
  fw ASL
  fw ASL
  fw ASL
  fw SWAP
  fw DECR
  fw DUP
  fw ZEQU
  zbranch 1b
  fw DROP
  fw DROP
  fw EXIT

defword "LCDSTR",,LCDSTR
1:
  fw DUP  ; ADDR ADDR
  fw CFROMROM ; CHAR ADDR
  fw DUP      ; CHAR CHAR ADDR
  fw LCDCHAR  ; CHAR ADDR
  fw SWAP     ; ADDR CHAR
  fw INCR     ; ADDR+1 CHAR
  fw SWAP     ; CHAR ADDR+1
  fw ZEQU     ; ZERO ADDR+1
  zbranch 1b
  fw EXIT

; Relative branch.
defcode "0BRANCH",,ZBRANCH
  ; Push the next word onto the data stack.
  movw ZL, IP_LREG
  ; TODO: This could just be a byte, but would require extending the byte into a
  ; word.
  lpm r0, Z+
  lpm r1, Z+
  POPDSP 2
  or r2, r3
  brne 1f  ; If top of stack is 0, we'll modify Z to branch.
  add ZL, r0
  adc ZH, r1
1:
  movw IP_LREG, ZL
  JMP NEXT

; High byte is address and is sent first.
.text
.balign 256
TOKEN_TABLE:
.include "token_table.i"
