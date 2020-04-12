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

.macro fw name
  .byte T_\name - TOKEN_TABLE
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
  fw LED

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
  adiw Y, 2
  JMP NEXT

defcode "SWAP",4,,SWAP
  POPDSP 0
  POPDSP 2
  PUSHDSP 0
  PUSHDSP 2
  JMP NEXT

defcode "DUP",3,,DUP
  ; MSB is top of stack, LSB is next
  ldd r0, Y+1
  ld r1, Y
  PUSHDSP 0
  JMP NEXT

defcode "OVER",4,,OVER
  ldd r0, Y+3
  ldd r1, Y+2
  PUSHDSP 0
  JMP NEXT

defcode "ROT",3,,ROT
  ; Bring the third item to the top.
  POPDSP 0
  POPDSP 2
  POPDSP 4
  PUSHDSP 2
  PUSHDSP 0
  PUSHDSP 4
  JMP NEXT

defcode "EXIT",4,,EXIT
  POPRSP IP_LREG
  JMP NEXT

defword "-ROT",4,,NROT
  fw ROT
  fw ROT
  fw EXIT

defword "2DROP",5,,TWODROP
  fw DROP
  fw DROP
  fw EXIT

; Defines a token in the token table.
.macro token name
  T_\name: .word \name
.endm
  
.balign 256
TOKEN_TABLE:
token DROP
token LED
token ROT
token EXIT

.global __vector_default
__vector_default:
  reti
