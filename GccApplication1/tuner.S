/*
 * tuner.S  –  avr-gcc / MPLAB X + avr8-gnu-toolchain
 *
 * Pinagem:
 *   LED apertar  -> PD5
 *   LED afinado  -> PD6
 *   LED afrouxar -> PD7
 *   Botão "Modo" -> PD2  (INT0, pull-up interno)
 *   Botão "Nota" -> PD3  (INT1, pull-up interno – futuro)
 *
 * Compilar junto com goertzel.c e um main.c mínimo (while(1)).
 * Linker flag necessária: -Wl,-e,config
 */

#include <avr/io.h>
#define __SFR_OFFSET 0

/* ------------------------------------------------------------------ */
/*  Constantes                                                          */
/* ------------------------------------------------------------------ */
#define N   400

/* ------------------------------------------------------------------ */
/*  SRAM – buffer de amostras e flag                                   */
/* ------------------------------------------------------------------ */
.section .bss
    .global buffer
    .align 2
buffer:
    .space 800          /* 400 amostras × 2 bytes */
buffer_ready:
    .space 1

/* ================================================================== */
/*  VETORES DE INTERRUPÇÃO                                             */
/*  Cada vetor do ATmega328P ocupa 2 bytes (rjmp = 1 word).           */
/*  O avr-gcc reserva a seção .vectors; basta definir os símbolos     */
/*  __vector_N com .global para o linker preencher a tabela.          */
/*                                                                     */
/*  Tabela de vetores usados:                                         */
/*    __vector_0  = RESET          (0x0000)                           */
/*    __vector_1  = INT0           (0x0002)                           */
/*    __vector_8  = TIMER2 COMPA   (0x000E)                           */
/* ================================================================== */
.section .vectors,"ax",@progbits

.global __vector_0
__vector_0:
    rjmp config             /* RESET → entrada principal */

.global __vector_1
__vector_1:
    rjmp ISR_ext_int0       /* INT0  → botão "Modo"      */

/* preenche vetores 2..7 com rjmp para si mesmo (trap seguro) */
.global __vector_2
__vector_2:  rjmp __vector_2
.global __vector_3
__vector_3:  rjmp __vector_3
.global __vector_4
__vector_4:  rjmp __vector_4
.global __vector_5
__vector_5:  rjmp __vector_5
.global __vector_6
__vector_6:  rjmp __vector_6
.global __vector_7
__vector_7:  rjmp __vector_7

.global __vector_8
__vector_8:
    rjmp adc_buffer         /* TIMER2 COMPA → coleta ADC */

/* ================================================================== */
/*  CÓDIGO                                                             */
/* ================================================================== */
.section .text

/* ------------------------------------------------------------------ */
/*  config – inicialização (entry point real do programa)             */
/* ------------------------------------------------------------------ */
.global config
config:
    /* Pilha */
    ldi  r16, lo8(RAMEND)
    out  SPL, r16
    ldi  r16, hi8(RAMEND)
    out  SPH, r16

    call conf_pinos
    call conf_pointer

    clr  r24                /* r25:r24 = contador de amostras */
    clr  r25

    /* Timer0 – debounce (modo normal, prescaler 64)
       16 MHz / 64 = 250 kHz  →  1 tick = 4 µs  →  125 ticks = 500 µs */
    ldi  r16, 0x00
    out  TCCR0A, r16
    ldi  r16, 0x03          /* CS01|CS00 → prescaler 64 */
    out  TCCR0B, r16

    /* Timer2 – amostragem 2 kHz (CTC, prescaler 64)
       16 MHz / 64 = 250 kHz  →  OCR2A = 124  →  ISR a cada 500 µs */
    ldi  r16, 0x02          /* WGM21 → CTC */
    sts  TCCR2A, r16
    ldi  r16, 0x04          /* CS22  → prescaler 64 */
    sts  TCCR2B, r16
    ldi  r16, 124           /* 0..124 = 125 ciclos */
    sts  OCR2A, r16

    /* INT0 – falling edge (ISC01=1, ISC00=0) */
    ldi  r16, 0x02
    sts  EICRA, r16
    ldi  r16, 0x01
    out  EIMSK, r16

    sei

    /* ADC – Vref=Vcc, right-justified, canal 0, prescaler 128
       125 kHz → ~13 µs por conversão */
    ldi  r16, 0x40
    sts  ADMUX,  r16
    ldi  r16, 0x87          /* ADEN=1, ADSC=0, prescaler=128 */
    sts  ADCSRA, r16
    ldi  r16, 0x00
    sts  ADCSRB, r16

    rjmp wait_interrupt

/* ------------------------------------------------------------------ */
/*  conf_pinos                                                          */
/* ------------------------------------------------------------------ */
conf_pinos:
    ldi  r16, 0b11100000    /* PD7,PD6,PD5 = saída; resto = entrada */
    out  DDRD, r16
    ldi  r16, 0b00001100    /* pull-up em PD3 e PD2; LEDs apagados  */
    out  PORTD, r16
    ret

/* ------------------------------------------------------------------ */
/*  conf_pointer – X aponta para o início de buffer[]                 */
/* ------------------------------------------------------------------ */
conf_pointer:
    ldi  XL, lo8(buffer)
    ldi  XH, hi8(buffer)
    clr  r16
    sts  buffer_ready, r16
    ret

/* ------------------------------------------------------------------ */
/*  wait_interrupt – loop ocioso até buffer estar cheio               */
/* ------------------------------------------------------------------ */
wait_interrupt:
    lds  r16, buffer_ready
    sbrs r16, 0
    rjmp wait_interrupt
    rjmp goertzel_c

/* ------------------------------------------------------------------ */
/*  ISR INT0 – botão "Modo" (falling edge em PD2)                     */
/*  Salva/restaura r16 porque interrompe código que o usa.            */
/* ------------------------------------------------------------------ */
.global ISR_ext_int0
ISR_ext_int0:
    push r16
    in   r16, SREG
    push r16

    clr  r16
    out  TCNT0, r16         /* zera Timer0 para contar debounce */
    call button_debouncing
    sbic PIND, 2            /* PD2=0? (botão ainda pressionado) */
    rjmp int0_sai_ruido     /* PD2=1 → ruído, ignora */
    call enable_timer2
int0_sai_ruido:
    pop  r16
    out  SREG, r16
    pop  r16
    reti

/* ------------------------------------------------------------------ */
/*  ISR TIMER2 COMPA – coleta uma amostra a cada 500 µs              */
/*  Salva r16, r17, r24, r25, XL, XH e SREG.                        */
/* ------------------------------------------------------------------ */
.global adc_buffer
adc_buffer:
    push r16
    in   r16, SREG
    push r16
    push r17
    push r24
    push r25
    push XL
    push XH

    call leitura_adc

    cpi  r25, hi8(N)
    brne tick_sai
    cpi  r24, lo8(N)
    brne tick_sai

    /* buffer cheio */
    call disable_timer2
    ldi  r16, 0x01
    sts  buffer_ready, r16

tick_sai:
    pop  XH
    pop  XL
    pop  r25
    pop  r24
    pop  r17
    pop  r16
    out  SREG, r16
    pop  r16
    reti

/* ------------------------------------------------------------------ */
/*  enable_timer2 / disable_timer2                                     */
/* ------------------------------------------------------------------ */
enable_timer2:
    clr  r16
    sts  TCNT2,  r16
    ldi  r16, (1<<OCIE2A)
    sts  TIMSK2, r16
    ret

disable_timer2:
    clr  r16
    sts  TIMSK2, r16
    ret

/* ------------------------------------------------------------------ */
/*  button_debouncing – espera 125 ticks de Timer0 ≈ 500 µs          */
/* ------------------------------------------------------------------ */
button_debouncing:
    in   r16, TCNT0
    cpi  r16, 125
    brne button_debouncing
    ret

/* ------------------------------------------------------------------ */
/*  leitura_adc – dispara ADC, aguarda, armazena                      */
/* ------------------------------------------------------------------ */
leitura_adc:
    lds  r16, ADCSRA
    ori  r16, (1<<ADSC)
    sts  ADCSRA, r16
    call wait_adc
    call store
    ret

/* ------------------------------------------------------------------ */
/*  wait_adc – aguarda fim da conversão (ADSC → 0)                   */
/* ------------------------------------------------------------------ */
wait_adc:
    lds  r16, ADCSRA
    sbrc r16, ADSC
    rjmp wait_adc
    lds  r16, ADCL          /* LSB primeiro (obrigatório no AVR) */
    lds  r17, ADCH
    ret

/* ------------------------------------------------------------------ */
/*  store – salva r17:r16 no buffer e incrementa contador            */
/* ------------------------------------------------------------------ */
store:
    st   X+, r16
    st   X+, r17
    adiw r24, 1
    ret

/* ------------------------------------------------------------------ */
/*  clear_variables – prepara para a próxima janela de captura        */
/* ------------------------------------------------------------------ */
clear_variables:
    clr  r24
    clr  r25
    call conf_pointer
    ret

/* ------------------------------------------------------------------ */
/*  goertzel_c – chama identifica_estado() (C) e atualiza LEDs       */
/*                                                                     */
/*  Convenção avr-gcc:                                                */
/*    - argumentos:  r24 (1º byte), r25 (2º byte), ...               */
/*    - retorno 8 bits: r24                                           */
/*    - registradores call-clobbered: r18–r27, r30–r31               */
/*    - registradores call-saved:     r2–r17, r28–r29                */
/*                                                                     */
/*  Como r24 é clobbered pela call, salvamos o resultado em r17      */
/*  (call-saved) antes de chamar atualiza_leds.                      */
/* ------------------------------------------------------------------ */
.extern identifica_estado

goertzel_c:
    call identifica_estado  /* retorno em r24 */
    mov  r17, r24
    call atualiza_leds
    call clear_variables
    rjmp wait_interrupt

/* ------------------------------------------------------------------ */
/*  atualiza_leds                                                       */
/*    r17 = 0 → apertar  (PD5)                                        */
/*    r17 = 1 → afinado  (PD6)                                        */
/*    r17 = 2 → afrouxar (PD7)                                        */
/* ------------------------------------------------------------------ */
atualiza_leds:
    cbi  PORTD, 5
    cbi  PORTD, 6
    cbi  PORTD, 7
    cpi  r17, 0
    breq led_apertar
    cpi  r17, 1
    breq led_afinado
    cpi  r17, 2
    breq led_afrouxar
    ret

led_apertar:
    sbi  PORTD, 5
    ret
led_afinado:
    sbi  PORTD, 6
    ret
led_afrouxar:
    sbi  PORTD, 7
    ret
