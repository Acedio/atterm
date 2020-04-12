; X, Y, and Z registers have nice functions for stack manipulation and
; instruction pointers.

; Z should be used for the instruction pointer since it's used for the LPM (load
; program memory) instruction.

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

.macro JMP label
  ldi ZL, lo8(pm(\label))
  ldi ZH, hi8(pm(\label))
  ijmp
.endm

.section .text
DOCOL:
  PUSHRSP IP_LREG
  adiw IP_LREG, CODEWORD_SIZE ; skip to the first token in the word
; Execute NEXT immediately.
NEXT:
  ; Load the next token, which is an offset into the token table.
  movw ZL, IP_LREG ; load the address of the next token
  adiw IP_LREG, 1 ; increment the IP
  ; Load the token index into ZL. ZH is constant
  lpm ZL, Z
  ldi ZH, hi8(TOKEN_TABLE)

  ; Load the codeword's address from the token table
  lpm R22, Z+
  lpm R23, Z
  movw ZL, R22

  ; The codeword contains the address of the code to run for this word, so we
  ; need to jump to the address stored at the codeword.
  lpm R22, Z+
  lpm R23, Z
  movw ZL, R22
  ; Execute the codeword.
  ijmp

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
  ; TODO sts hi8(var_S0), DS_LREG+1

  ; Initialize the interpreter pointer
  ldi IP_LREG, lo8(cold_start)
  ldi IP_LREG+1, hi8(cold_start)
  ; Call NEXT to kick things off.
  JMP NEXT
cold_start:
  ; The default program!
  .byte T_LED - TOKEN_TABLE

.set F_IMMED,0x80
.set F_HIDDEN,0x20
.set F_LENMASK,0x1f
.set link,0

.macro defword name, namelen, flags=0, label
  .balign 2
  .global name_\label
name_\label :
  .word link ; link to the previously defined word
  .set link,name_\label
  .byte \flags|\namelen ; flags + length byte
  .ascii "\name" ; the name
  .balign 2
  .global \label
\label :
  .word pm(DOCOL) ; Codeword
  ; list of word tokens follow
.endm

.macro defcode name, namelen, flags=0, label
  .balign 2
  .global name_\label
name_\label :
  .word link ; link to the previously defined word
  .set link,name_\label
  .byte \flags|\namelen ; flags + length byte
  .ascii "\name" ; the name
  .balign 2
  .global \label
\label :
  .word pm(code_\label) ; Codeword
  .balign 2
  .global code_\label
code_\label :
  ; list of word tokens follow
.endm

defcode "LED",3,,LED
  JMP blink

defcode "DROP",4,,DROP
  adiw DS_LREG, 2
  JMP NEXT

blink:
  sbi _SFR_IO_ADDR(PORTB), LED_PIN
  ldi r26, 0
  ldi r27, 0
  ldi r18, 0
wait:
  adiw r26, 1
  brne wait ; loop if not 0
  cbi _SFR_IO_ADDR(PORTB), LED_PIN
  inc r18
  sbrs r18, 3
  rjmp off
  sbi _SFR_IO_ADDR(PORTB), LED_PIN
  rjmp wait
off:
  cbi _SFR_IO_ADDR(PORTB), LED_PIN
  rjmp wait

.balign 256
TOKEN_TABLE:
T_DROP: .word DROP
T_LED: .word LED

.global __vector_default
__vector_default:
  reti
