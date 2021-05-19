; somewhere in strlen hides an error

; Copyright (c) 2021 ozforester. All rights reserved.
; Use of this source code is goverened by a MIT license
; that can be found in the LICENSE file.

; ATmega8 @4MHz internal osc. (H:D9, L:23)
; JHD162A HD44780 via twi extension PCF8574AT
; Voltage divider and four buttons pad connected to adc port.
; If button pressed its adc sample prints on the lcd screen.
; alpha version (copying previous repos to build this one)

#undef __SFR_OFFSET
#define __SFR_OFFSET 0
#include <avr/io.h>

; twi ack
#define START     0x08
#define REP_START 0x10
#define SLAW_ACK  0x18
#define SLAW_NACK 0x20
#define DATA_ACK  0x28
#define DATA_NACK 0x30

; pcf8574 <-> HD44780
; P0 - rs
; P1 - rw
; P2 - e (cs)
; P3 - backlight
; P4 - DB4
; P5 - DB5
; P6 - DB6
; P7 - DB7

; adc input
; buttons - PC3

; pcf8574
#define rs 0
#define rw 1
#define  e 2
#define bl 3
#define p4 4
#define p5 5
#define p6 6
#define p7 7

; registers
accum = 0			; r0
temp  = 16			; good worker (.set)
char  = 17			; msg char
tcntr = 18			; time counter
counter = 19                    ; delay counter reg
 code = 20                       ; blink code reg
address = 21                    ; twi address reg
data = 22                       ; twi data reg
len = 23			; string length

.data				; eeprom preferred

.text

.global main			;
.global TIMER0_OVF_vect		;

main:				;
        rcall timer_init        ;
        rcall delay_20ms        ;
        rcall twi_init          ; 100kHz
        rcall twi_scan          ; downwards 127..0
        cpi address, 0          ; 0 when no answer
        brne main1              ; scan success
        rcall led_on            ; error
        main1:                  ;
        rcall pcf_init          ;
        rcall lcd_init          ;
	;rcall lcd_clear	;
	;rcall lcd_home		;
	;rcall lcd_cur		;
        rcall lcd_print         ;
        ;rcall led_on		; j-tag (:
	loop:			;
	rjmp loop 		;
ret				;

msg1: .asciz "Hi, stranger,"    ; temporarily in prog. space
msg2: .asciz "me ozforester"    ;
ret				;

lcd_cur:			; cursor position
        rcall twi_start         ;
        rcall twi_sla_w         ;
        rcall wait_bf           ;
        andi data, 0x0F         ; clear data bits
        rcall d7_high           ; 1xxx - set dram
        rcall d5_high           ; x100 - address 6:4
        rcall instr_w           ;
        rcall twi_e_pulse       ; take
        ;rcall instr_w          ; 0000 - address 3:0
        rcall twi_e_pulse       ;
        rcall twi_stop          ;
ret				;

lcd_home:			;
        rcall twi_start         ;
        rcall twi_sla_w         ;
        rcall wait_bf           ;
        andi data, 0x0F         ; clear data bits
        rcall instr_w           ; 0000 - display
        rcall twi_e_pulse       ; take
        rcall d5_high           ; 001* - home
        ;rcall instr_w          ;
        rcall twi_e_pulse       ;
        rcall twi_stop          ;
ret				;

lcd_clear:                      ;
        rcall twi_start         ;
        rcall twi_sla_w         ;
        rcall wait_bf           ;
        andi data, 0x0F         ; clear data bits
        rcall instr_w        ; set
        rcall twi_e_pulse       ; take
        rcall d4_high           ; 0001 - clear
        ;rcall instr_w        ;
        rcall twi_e_pulse       ;
	rcall twi_stop		;
ret                             ;


lcd_print:			;
        ldi zh, hi8(msg1)       ; z *-> msg1
        ldi zl, lo8(msg1)       ;
	rcall lcd_msg		;
	rcall lcd_cur		;
        ldi zh, hi8(msg2)       ; z *-> msg2
        ldi zl, lo8(msg2)       ;
        rcall lcd_msg           ;
ret				;

lcd_msg:			;
	rcall twi_start		;
	rcall twi_sla_w		;
        ;ldi zh, hi8(msg1) 	; z *-> msg
        ;ldi zl,	lo8(msg1)	;
	rcall strlen		; length in temp register
	ls1:			;
	lpm			; read msg word into r0
	mov char, accum		; copy word into char register
	rcall lcd_char		; write one 4bit mode char
        inc zl                  ; next 16 bit world of msg
	dec len			; one char less
	brne ls1		; if not Z go next
	rcall twi_stop		;
ret				; or exit

strlen:				; count length of msg
        ;ldi len, 7             ; debugging
	;ret			; debugging
	push zh			; save msg pointer
	push zl			; to stack
	clr len			; clear counter
	sl1:			;
	lpm			; read msg byte into r0
	mov char, accum		; copy r0 into char
	cpi char, 0		; end of string? (seems it always non zero)
	breq sl2		; '\0' string terminator
	inc len			; increment length counter
	inc zl			; increment Z
	rjmp sl1		; and continue read flash
	sl2:			;
	pop zl			; restore flash pointer
	pop zh			; from stack
	;ldi len, 7		; debugging
ret				;

lcd_char:			; write one character
        ; low nibble		;
        rcall wait_bf           ; busy flag
        rcall data_w            ;
	andi data, 0x0F		; clear data bits
	sbrc char, 7		;
	rcall d7_high		;
        sbrc char, 6            ;
        rcall d6_high       	;
        sbrc char, 5            ;
        rcall d5_high       	;
        sbrc char, 4            ;
        rcall d4_high       	;
	rcall twi_data_w	;
        rcall twi_e_pulse       ;
	; high nibble		;
        andi data, 0x0F         ; clear data bits
	swap char		;
        sbrc char, 7            ;
        rcall d7_high       	;
        sbrc char, 6            ;
        rcall d6_high       	;
        sbrc char, 5            ;
        rcall d5_high       	;
        sbrc char, 4            ;
        rcall d4_high       	;
	rcall twi_data_w	;
        rcall twi_e_pulse 	;
ret				;

lcd_init:			; optimize when out of pmem
        rcall delay_20ms        ; >= 40 ms
        rcall delay_20ms        ;
	rcall twi_start		;
	rcall twi_sla_w		;
				; 8-bit mode w/o busy flag check
        rcall bl_low            ; backlight bit
	rcall d4_high		;
	rcall d5_high		; 0011 - init1
	rcall d6_low		;
	rcall d7_low		;
	rcall instr_w		;
	rcall twi_data_w	;
	rcall twi_e_pulse	; 1
				;
        rcall delay_1ms         ;
        rcall delay_1ms         ;
        rcall delay_1ms         ;
	rcall twi_data_w	;
        rcall twi_e_pulse       ; 2
				;
        rcall delay_100us       ;
	rcall twi_data_w	;
	rcall twi_e_pulse	; 3
				;
        rcall delay_100us       ;
        rcall d4_low            ; 0010 - pre function set
	rcall twi_data_w	;
        rcall twi_e_pulse       ; 4
				;
        rcall delay_100us       ; flag chech & 4-bit mode next
				;
        rcall d5_high           ; 0010 - function set
	rcall twi_data_w	;
	rcall twi_e_pulse	; 5
        rcall d7_high           ;
	rcall d5_low		; 1000 - 2 lines, 5x8 font
	rcall twi_data_w	;
        rcall twi_e_pulse       ; 6
				;
        rcall wait_bf           ;
	rcall d7_low		; 0000 - display
	rcall twi_data_w	;
        rcall twi_e_pulse       ; 7
	rcall d7_high		; 1000 - off
	rcall twi_data_w	;
        rcall twi_e_pulse       ; 8
				;
        rcall wait_bf           ;
	rcall d7_low		; 0000 - display
	rcall twi_data_w	;
        rcall twi_e_pulse       ; 9
        rcall d4_high           ; 0001 - clear
	rcall twi_data_w	;
        rcall twi_e_pulse       ; 10
				;
        rcall wait_bf           ;
	rcall d4_low		; 0000 - entry
	rcall twi_data_w	;
        rcall twi_e_pulse       ; 11
        rcall d6_high           ;
        rcall d5_high           ; 0110 - mode
	rcall twi_data_w	;
        rcall twi_e_pulse       ; 12
				;
        rcall wait_bf           ;
	rcall d6_low		;
	rcall d5_low		; 0000 - display
	rcall twi_data_w	;
        rcall twi_e_pulse       ; 13
        rcall d7_high           ;
        rcall d6_high           ; 1100 - on
        rcall d5_high           ; 1110 - cursor
        rcall d4_high           ; 1111 - blink
        rcall bl_high	        ;
	rcall twi_data_w	;
        rcall twi_e_pulse       ; 14
				;
	rcall twi_stop		;
        rcall delay_20ms        ; voila
ret				;

wait_bf:                ; wait until busy flag cleared
       rcall delay_1ms ; debugging
       ;rcall instr_r   ;
       ;rcall e_high    ;
       ;wb1:            ;
	;rcall twi_data_r ; <------- not ready yet
       ;sbic data, p7   ; till bf cleared
       ;rjmp wb1        ;
       ;rcall e_low     ;
       ;nop             ;
       ;rcall twi_e_pulse ; addr
	;nop	       ;
ret                    ;

twi_e_pulse:                    ;
        rcall e_high            ;
	rcall twi_data_w	;
        nop                    ;
        nop                    ;
        nop                    ; about us (microsecond) (:
        nop                    ;
        rcall e_low             ;
	rcall twi_data_w	;
ret                             ;

twi_backlight_on:		;
	rcall bl_high		;
	rcall twi_start		;
	rcall twi_sla_w		;
	rcall twi_data_w	;
	rcall twi_stop		;
ret				;

twi_backlight_off:		;
	rcall bl_low		;
        rcall bl_high           ;
        rcall twi_start         ;
        rcall twi_sla_w         ;
        rcall twi_data_w        ;
        rcall twi_stop          ;
ret				;

instr_w:                    ; instrustion write
        rcall rs_low        ;
        rcall rw_low        ;
ret                         ;

instr_r:                    ; busy flag or a-counter read
        rcall rs_low        ;
        rcall rw_high       ;
ret                         ;

data_w:                     ; data write
        rcall rs_high       ;
        rcall rw_low        ;
ret                         ;

data_r:                     ; data read
        rcall rs_high       ;
        rcall rw_high       ;
ret                         ;

d4_low:                 ;
        cbr data, 1<<p4 ;
ret	                ;

d4_high:                ;
        sbr data, 1<<p4 ;
ret                     ;

d5_low:                 ;
        cbr data, 1<<p5 ;
ret                     ;

d5_high:                ;
        sbr data, 1<<p5 ;
ret                     ;

d6_low:                 ;
        cbr data, 1<<p6 ;
ret                     ;

d6_high:                ;
        sbr data, 1<<p6 ;
ret                     ;

d7_low:                 ;
        cbr data, 1<<p7 ;
ret                     ;

d7_high:                ;
        sbr data, 1<<p7 ;
ret                     ;

rs_low:		        ;
        cbr data, 1<<rs ;
ret			;

rs_high:	        ;
        sbr data, 1<<rs ;
ret			;

rw_low:                 ;
        cbr data, 1<<rw ;
ret			;

rw_high:                ;
        sbr data, 1<<rw ;
ret			;

e_low:                  ;
        cbr data, 1<<e  ;
ret			;

e_high:                 ;
        sbr data, 1<<e  ;
ret			;

bl_high:		;
	sbr data, 1<<bl	;
ret			;

bl_low:		        ;
        cbr data, 1<<bl ;
ret                     ;

delay_20ms:                     ;
        ldi temp, 20            ;
	d20:			;
	rcall delay_1ms		;
	subi temp, 1		;
	brne d20		;
ret 		                ;

delay_100us:                    ;
        ldi tcntr, 4            ;
        du1:                    ;
        cpi tcntr, 0            ;
        brne du1                ;
ret		                ;

delay_1ms:                      ;
        ldi tcntr, 40           ;
        d1:                     ;
	cpi tcntr, 0		;
        brne d1                 ;
ret 		                ;

timer_init:                             ;
        ldi temp, (1<<CS00)             ; prescaler 1, 0.25 us
        out TCCR0, temp                 ;
        ldi temp, 155                   ; 25 us
        out TCNT0, temp                 ;
        ldi temp, (1<<TOIE0)            ;
        out TIMSK, temp                 ;
        sei                             ; go
ret                                     ;

TIMER0_OVF_vect:                ;
	cli			;
        push temp               ; save temp
        in temp, SREG           ; save SREG
	push temp
        ldi temp, 155           ; next 25 us
        out TCNT0, temp         ;
        subi tcntr, 1           ; delay counter--
	pop temp
        out SREG, temp          ; restore SREG
        pop temp                ; restore temp
	sei			;
reti 		                ;

led_init:			;
        sbi DDRD, PD7           ; D7 output
        cbi PORTD, PD7          ; D7 low
ret				;

led_on:				;
	rcall led_init		;
        sbi PORTD, PD7          ; D7 high
ret				;

pcf_init:			;
	nop			;
ret				;

twi_scan:			;
	ldi address, 127	; will step backward
	twscan1:		;
	rcall twi_start		; start/rep_start
	rcall twi_sla_w		; slave addres + w
	cpi temp, 0xFF		; touched?
	brne twscan2		; if not cleared
	clr temp		; (temp=0x00)
	subi address, 1		; else next address
	cpi address, 0		; last address
	breq twscan2		; exit with zero address
	rjmp twscan1		;
	twscan2:		;
	rcall twi_stop		;
	ret			;

twi_data_w:					;
	mov temp, data				;
	out TWDR, temp				; data
	ldi temp, ((1<<TWINT)|(1<<TWEN))	;
	out TWCR, temp				; go
	tdw1:					;
	in temp, TWCR				;
	sbrs temp, TWINT			; sent?
	rjmp tdw1				; no? repeat
	in temp, TWSR				; else, read status
	andi temp, 0xF8				;
	cpi temp, DATA_ACK			; ack?
	breq tdw2				; ok
        rcall led_on                       	; nack
	tdw2:					;
ret					;

twi_sla_w:					;
	mov temp, address			; slave address (e.g. 0x3F as pcf of mine)
	lsl temp				; address<<  + 0, R/W = W
	out TWDR, temp				;
	ldi temp, ((1<<TWINT)|(1<<TWEN))	;
	out TWCR, temp				; go
	slaw1:					;
        in temp, TWCR                           ;
        sbrs temp, TWINT                        ; sent
        rjmp slaw1                              ;
        in temp, TWSR                           ; read status
        andi temp, 0xF8                         ;
        cpi temp, SLAW_ACK                      ;
	breq slaw2				; acked (stay temp untouched)
	;rcall led_on				; uncomment if used w/o autodetect
	ser temp				; else (temp=0xFF)
	slaw2:					;
ret						;

twi_start:						;
	ldi temp, ((1<<TWINT)|(1<<TWSTA)|(1<<TWEN))	;
	out TWCR, temp					; go
	start1:						;
	in temp, TWCR					;
	sbrs temp, TWINT				; sent
        rjmp start1                                     ;
	in temp, TWSR					; read status
	andi temp, 0xF8					;
	cpi temp, START					;
	breq start2					;
        cpi temp, REP_START                             ;
        breq start2                                     ;
	rcall led_on					; error
	start2:						;
ret							; acked

twi_stop:						;
	ldi temp, ((1<<TWINT)|(1<<TWEN)|(1<<TWSTO))	;
        out TWCR, temp                                  ;
ret							;

twi_init:			; 100 kHz clock @4MHz
	ldi temp, 0b00001100	; 4000000 / ( 16 + 2*twbr * 4^twps )
	out TWBR, temp		; 12
        in temp, TWSR	        ; read whole TWSR
	andi temp, 0b11111100	; set prescaler TWPS 1:0 as 00
	out TWSR, temp		;
ret				;

.global __vector_default        ; Note [10] nongnu.org assembly
__vector_default:		;
reti				;

.end
