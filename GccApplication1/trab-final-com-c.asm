; pinos
; led apertar PD5 (pino 5)
; led afinado PD6 (pino 6)
; led afrouxar PD7 (pino 7)
; botao "Modo" PD2 (pino 2) = INT0, com pull-up interno
; botao "Nota" PD3 (pino 3) = INT1, com pull-up interno upgrade futuro, nao usado ainda

.include "m328Pdef.inc"
.global buffer

.org 0x0000
rjmp config

.org 0x0002 ; vetor da interrupcao INT0
rjmp ISR_ext_int0

.org 0x000E ; vetor da interrupção TIMER2 COMPA
rjmp adc_buffer

.extern identifica_estado

.dseg
.align 2
buffer:
.byte 800      ; 400 samples × 2 bytes
buffer_ready:
.byte 1

.equ SAMPLE_RATE = 2000 ; Hz
.equ N = 400 ; samples por janela de analise
.equ N_NOTES = 6 ; numero de cordas

config:
;pilha
ldi r16, low(RAMEND)
out SPL, r16
ldi r16, high(RAMEND)
out SPH, r16

call conf_pinos
call conf_pointer ; seta o buffer onde ficarão as amostras do adc

clr r24 ; contador de samples
clr r25 ; overflow

;configura timer0 so para medir o tempo de debounce apos o INT0 disparar
ldi r16, 0b00000000
out TCCR0A, r16 ; modo normal
ldi r16, 0b00000011 ; Com PS64
out TCCR0B, r16 ; e clock de 16MHz, 125 ciclos = 500us
; que e o valor comparado mais abaixo

;configura timer2 para medir sample_rate (2khz)
ldi r16, 0b000000_10 ;ativa modo CTC
sts TCCR2A, r16
ldi r16, 0b00000_100 ; prescaler de 64 -> 125 ciclos = 500us
sts TCCR2B, r16
ldi r16, 0x7C ; 125 ciclos (0-124)
sts OCR2A, r16

;configura interrupt INT0
ldi r16, 0b00000010
sts EICRA, r16 ; INT0 como falling edge (ISC01=1, ISC00=0)
ldi r16, 0b00000001
out EIMSK, r16 ; habilita a interrupcao INT0
sei
;configura ADC
ldi R16, 0b01000000 ; Vref = Vcc, Justificado para a Direita (10 bits), Mux Canal 0
sts ADMUX, R16 ;
ldi R16, 0b10000111 ; ADC ligado (ADEN=1), Auto-trigger DESLIGADO, Prescaler = 128 (16MHz/128 = 125kHz)
; conversão = 125k/13 = 104 micro segundos
sts ADCSRA, R16
ldi R16, 0b00000000 ;
sts ADCSRB, R16
ldi r17, 1
rjmp wait_interrupt

conf_pinos:
; bits 5,6,7 em 1 = saida (LEDs); bits 2 e 3 ficam em 0 = entrada (botoes)
ldi r16, 0b11100000 ;
out DDRD, r16
; LEDs comecam apagados (bits 5,6,7 = 0) e ativa o pull-up
ldi r16, 0b00001100
out PORTD, r16
ret

conf_pointer:
ldi XL, low(buffer)
ldi XH, high(buffer)
clr r16
sts buffer_ready, r16 ; desliga a flag de buffer ready
ret

wait_interrupt:
lds r16, buffer_ready
sbrs r16, 0
rjmp wait_interrupt
rjmp goertzel_c

ISR_ext_int0:
clr r16
out TCNT0, r16 ; zera o timer0 para comecar a contagem
call button_debouncing
sbic PIND, 2 ; o botao ainda esta pressionado (PD2 = 0)?
reti ; nao esta mais -> era ruido, ignora e retorna
call enable_timer2
reti

enable_timer2:
clr r16
sts TCNT2,r16
ldi r16, (1<<OCIE2A) ; ativa interrupção em OCF2A
sts TIMSK2, r16
ret

disable_timer2:
clr r16
sts timsk2, r16
ret

button_debouncing:
in r16, TCNT0
cpi r16, 0x7D ; 125 ciclos de timer = 500us (PS64 @ 16MHz)
brne button_debouncing
ret

adc_buffer:
call leitura_adc
cpi r25, high(N)
brne wait_next_tick  ; espera o proximo interrupt do timer2 em 500us
cpi r24, low(N)
brne wait_next_tick
call disable_timer2
ldi r16, 0x01 ; indica que o buffer esta pronto
sts buffer_ready, r16
reti

wait_next_tick:
reti

leitura_adc: ;realiza uma leitura
lds r16, ADCSRA
ori r16, (1<<ADSC)
sts adcsra, r16 ; ativa adc
call wait_adc ;espera o adc converter
call store
ret

wait_adc:
lds r16, adcsra
sbrc r16, adsc
rjmp wait_adc
lds r16, adcl
lds r17, adch
ret

store: ;guarda no buffer as samples
st X+, r16
st X+, r17
adiw r24,1 ; ADIW adiciona à palavra r25:r24
ret

clear_variables:
clr r24 ; reseta o contador (tudo ja foi guardado no buffer)
clr r25
call conf_pointer
ret

goertzel_c:
call identifica_estado
mov r17, r24
call atualiza_leds
call clear_variables ; limpa as variaveis para proxima execucao
rjmp wait_interrupt

atualiza_leds:
cbi PORTD,5
cbi PORTD,6
cbi PORTD,7
cpi r17,0
breq led_apertar
cpi r17,1
breq led_afinado
cpi r17, 2
breq led_afrouxar
ret

led_afrouxar:
sbi PORTD,7
ret

led_apertar:
sbi PORTD,5
ret

led_afinado:
sbi PORTD,6
ret

