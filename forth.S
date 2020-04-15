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

LED_PIN = PB0

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

; TODO: Make sure this is where we wind up on RESET
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
  ; TODO sts lo8(var_S0), DS_LREG
  ; TODO sts hi8(var_S0), DS_LREG

  ; Initialize the interpreter pointer
  ldi IP_LREG, lo8(cold_start)
  ldi IP_LREG+1, hi8(cold_start)
  ; Call NEXT to kick things off.
  JMP NEXT
cold_start:
  ; The default program!
  fw INITRAM
  lit 10
  fw TRI
  lit 55
  fw EQU
  fw TESTLED

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

; Blinks the LED if top of stack = 0, holds steady if != 0.
defcode "TESTLED",,TESTLED
  POPDSP 16
  or r16, r17
  ser r17
  tst r16
  breq blink
  sbi _SFR_IO_ADDR(PORTB), LED_PIN
1:
  jmp 1b

defcode "LED",,LED
blink:
  ldi r26, 0
  ldi r27, 0
  ldi r18, 0
wait:
  adiw r26, 1
  brne wait ; loop if not 0
  inc r18
  sbrs r18, 3
  rjmp off
  sbi _SFR_IO_ADDR(PORTB), LED_PIN
  rjmp wait
off:
  cbi _SFR_IO_ADDR(PORTB), LED_PIN
  rjmp wait

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

; Pushes the return address onto the data stack.
defword "LOOP",,LOOP
  fw FROMR
  fw DUP
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
defword "TRIINT",,TRIINT
  lit 0 ; running sum
  fw LOOP ; D: LOOP SUM N -- R: EXIT
  fw TOR ; D: SUM N -- R: LOOP EXIT

  fw OVER ; N SUM N
  fw ADD  ; NSUM N
  fw SWAP ; N NSUM
  fw DECR ; N-1 NSUM
  fw SWAP ; NSUM N-1
  fw OVER ; N-1 NSUM N-1
  lit 0   ; 0 N-1 NSUM N-1
  fw EQU  ; ISDONE NSUM N-1

  fw FROMR ; D: LOOP ISDONE args -- R: EXIT
  fw SWAP  ; D: ISDONE LOOP args -- R: EXIT
  fw OVER  ; D: LOOP ISDONE LOOP args -- R: EXIT
  fw FROMR ; D: EXIT LOOP ISDONE LOOP args -- R: empty
  fw DUP
  fw TOR   ; R: EXIT

  fw ROT   ; D: ISDONE EXIT LOOP LOOP args
  fw TERN    ; D: next LOOP args
  fw TOR   ; D: LOOP NSUM N-1 -- R: next EXIT
  fw EXIT  ; D: LOOP NSUM N-1 -- R: EXIT

defword "TRI",,TRI
  fw TRIINT
  fw DROP
  fw SWAP
  fw DROP
  fw FROMR
  fw DROP
  fw EXIT

.text
.balign 256
TOKEN_TABLE:
.include "token_table.i"
