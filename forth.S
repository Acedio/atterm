; Need some way of having both SRAM words and PROGMEM words.
; If this is token-based, maybe signify in the LSB what kind of word the token
; is for?

#include <avr/io.h>

; The interpreter pointer is R25:R24
.set IP_LREG, 24
; The data stack pointer is Y (r28)
.set DS_LREG, 28
.set CODEWORD_SIZE, 2

RS0 = 0x100
DS0 = 0x200

LED_PIN = PB0

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

.macro JMP label
  ldi ZL, lo8(pm(\label))
  ldi ZH, hi8(pm(\label))
  ijmp
.endm

.section .text
DOCOL:
  PUSHRSP IP_LREG
  ; R23:22 contains the codeword's address.
  movw IP_LREG, R22
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

  ; Load the codeword's address from the token table. Keep it in R22 so DOCOL
  ; can read it later.
  lpm R22, Z+
  lpm R23, Z
  movw ZL, R22

  ; The codeword contains the address of the code to run for this word, so we
  ; need to jump to the address stored at the codeword.
  lpm R20, Z+
  lpm R21, Z
  movw ZL, R20
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
  lit 11
  lit 12
  fw GT
  fw TESTLED

.set F_IMMED,0x80
.set F_HIDDEN,0x20
.set F_LENMASK,0x1f
.set link,0

.macro defword name, flags=0, label
  .balign 2
  .global name_\label
name_\label :
  .word link ; link to the previously defined word
  .set link,name_\label
  .byte \flags|(nameend_\label - name_\label - 3) ; flags + length byte
  .ascii "\name" ; the name
nameend_\label :
  .balign 2
  .global \label
\label :
  .word pm(DOCOL) ; Codeword
  ; list of word tokens follow
.endm

.macro defcode name, flags=0, label
  .balign 2
  .global name_\label
name_\label :
  .word link ; link to the previously defined word
  .set link,name_\label
  .byte \flags|(nameend_\label - name_\label - 3) ; flags + length byte
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

; Defines a token in the token table.
.macro token name
  T_\name: .word \name
.endm

.balign 256
TOKEN_TABLE: ; :g/^defword\|^defcode/t /^TOKEN_TABLE
token LT
token GT
token EQU
token ZLT
token ZGT
token ZEQU
token INVERT
token XOR
token OR
token AND
token DECR
token INCR
token SUB
token ADD
token LIT
token TWODUP
token TWODROP
token NROT
token EXIT
token ROT
token OVER
token DUP
token SWAP
token DROP
token LED
token TESTLED
  
.global __vector_default
__vector_default:
  reti
