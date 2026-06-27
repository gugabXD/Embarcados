/*
 * tuner.S
 * Convertido de .asm (AVRA) para .S (avr-gcc / avr-as)
 *
 * Pinagem:
 *   LED apertar  -> PD5
 *   LED afinado  -> PD6
 *   LED afrouxar -> PD7
 *   Botão "Modo" -> PD2 (INT0, pull-up interno)
 *   Botão "Nota" -> PD3 (INT1, pull-up interno – futuro)
 */

#include <avr/io.h>

/* ------------------------------------------------------------------ */
/*  Constantes                                                          */
/* ------------------------------------------------------------------ */
#define SAMPLE_RATE  2000
#define N            400
#define N_NOTES      6

/* ------------------------------------------------------------------ */
/*  Segmento BSS  (variáveis não-inicializadas em SRAM)               */
/* ------------------------------------------------------------------ */
.section .bss
    .global buffer
    .align 2
buffer:
    .space 800          /* 400 amostras × 2 bytes cada */

buffer_ready:
    .space 1

/* ------------------------------------------------------------------ */
/*  Vetores de interrupção                                             */
/*  O avr-gcc exige que cada vetor seja uma seção própria             */
/* ------------------------------------------------------------------ */

/* Reset */
.section .vectors,"ax",@progbits
.global __vectors
.func __vectors
__vectors:

/* 0x0000 – RESET */
.org 0x0000
    rjmp config

/* 0x0002 – INT0 (External Interrupt Request 0) */
.org 0x0002
    rjmp ISR_ext_int0

/* 0x000E – TIMER2 COMPA */
.org 0x000E
    rjmp adc_buffer

.endfunc

/* ------------------------------------------------------------------ */
/*  Código principal                                                    */
/* ------------------------------------------------------------------ */
.section .text

/* ------------------------------------------------------------------ */
/*  config – inicialização geral                                       */
/* ------------------------------------------------------------------ */
.global config
.func config
config:
    /* Pilha */
    ldi  r16, lo8(RAMEND)
    out  SPL, r16
    ldi  r16, hi8(RAMEND)
    out  SPH, r16

    call conf_pinos
    call conf_pointer       /* aponta X para buffer[] */

    clr  r24                /* contador de amostras (low)  */
    clr  r25                /* contador de amostras (high) */

    /* Timer0 – apenas debounce (modo normal, prescaler 64)
       16 MHz / 64 = 250 kHz → 1 tick = 4 µs → 125 ticks = 500 µs   */
    ldi  r16, 0b00000000
    out  TCCR0A, r16
    ldi  r16, 0b00000011
    out  TCCR0B, r16

    /* Timer2 – cadência de amostragem (CTC, prescaler 64)
       16 MHz / 64 = 250 kHz → OCR2A = 124 → ISR a cada 500 µs = 2 kHz */
    ldi  r16, 0b00000010    /* WGM21 = 1  → modo CTC */
    sts  TCCR2A, r16
    ldi  r16, 0b00000100    /* CS22 = 1   → prescaler 64 */
    sts  TCCR2B, r16
    ldi  r16, 0x7C          /* 124 (conta 0..124 = 125 ciclos) */
    sts  OCR2A, r16

    /* INT0 – falling edge */
    ldi  r16, 0b00000010
    sts  EICRA, r16         /* ISC01=1, ISC00=0 → falling edge */
    ldi  r16, 0b00000001
    out  EIMSK, r16         /* habilita INT0 */
    sei

    /* ADC – Vref = Vcc, resultado right-justified, canal 0,
             prescaler 128 → 125 kHz → ~13 µs/conversão              */
    ldi  r16, 0b01000000
    sts  ADMUX,  r16
    ldi  r16, 0b10000111    /* ADEN=1, auto-trigger off, prescaler 128 */
    sts  ADCSRA, r16
    ldi  r16, 0b00000000
    sts  ADCSRB, r16

    ldi  r17, 1
    rjmp wait_interrupt
.endfunc

/* ------------------------------------------------------------------ */
/*  conf_pinos                                                          */
/* ------------------------------------------------------------------ */
.func conf_pinos
conf_pinos:
    ldi  r16, 0b11100000    /* PD5,PD6,PD7 = saída; PD2,PD3 = entrada */
    out  DDRD, r16
    ldi  r16, 0b00001100    /* LEDs apagados; pull-up em PD2 e PD3    */
    out  PORTD, r16
    ret
.endfunc

/* ------------------------------------------------------------------ */
/*  conf_pointer – inicializa X apontando para buffer[]               */
/* ------------------------------------------------------------------ */
.func conf_pointer
conf_pointer:
    ldi  XL, lo8(buffer)
    ldi  XH, hi8(buffer)
    clr  r16
    sts  buffer_ready, r16  /* limpa flag "buffer pronto" */
    ret
.endfunc

/* ------------------------------------------------------------------ */
/*  wait_interrupt – loop principal aguardando buffer cheio            */
/* ------------------------------------------------------------------ */
.func wait_interrupt
wait_interrupt:
    lds  r16, buffer_ready
    sbrs r16, 0             /* pula próxima instrução se bit 0 = 1 */
    rjmp wait_interrupt
    rjmp goertzel_c
.endfunc

/* ------------------------------------------------------------------ */
/*  ISR INT0 – botão "Modo"                                            */
/* ------------------------------------------------------------------ */
.global ISR_ext_int0
.func ISR_ext_int0
ISR_ext_int0:
    clr  r16
    out  TCNT0, r16         /* zera Timer0 para contar debounce */
    call button_debouncing
    sbic PIND, 2            /* se PD2 = 0 (ainda pressionado), continua */
    reti                    /* PD2 = 1 → era ruído, ignora */
    call enable_timer2
    reti
.endfunc

/* ------------------------------------------------------------------ */
/*  enable_timer2 / disable_timer2                                     */
/* ------------------------------------------------------------------ */
.func enable_timer2
enable_timer2:
    clr  r16
    sts  TCNT2,  r16
    ldi  r16, (1<<OCIE2A)
    sts  TIMSK2, r16
    ret
.endfunc

.func disable_timer2
disable_timer2:
    clr  r16
    sts  TIMSK2, r16
    ret
.endfunc

/* ------------------------------------------------------------------ */
/*  button_debouncing – aguarda 125 ticks de Timer0 ≈ 500 µs         */
/* ------------------------------------------------------------------ */
.func button_debouncing
button_debouncing:
    in   r16, TCNT0
    cpi  r16, 0x7D          /* 125 ticks */
    brne button_debouncing
    ret
.endfunc

/* ------------------------------------------------------------------ */
/*  ISR TIMER2 COMPA – coleta amostras do ADC                         */
/* ------------------------------------------------------------------ */
.global adc_buffer
.func adc_buffer
adc_buffer:
    call leitura_adc
    cpi  r25, hi8(N)
    brne wait_next_tick
    cpi  r24, lo8(N)
    brne wait_next_tick
    call disable_timer2
    ldi  r16, 0x01
    sts  buffer_ready, r16
    reti

wait_next_tick:
    reti
.endfunc

/* ------------------------------------------------------------------ */
/*  leitura_adc – dispara e aguarda conversão, depois armazena        */
/* ------------------------------------------------------------------ */
.func leitura_adc
leitura_adc:
    lds  r16, ADCSRA
    ori  r16, (1<<ADSC)
    sts  ADCSRA, r16        /* inicia conversão */
    call wait_adc
    call store
    ret
.endfunc

/* ------------------------------------------------------------------ */
/*  wait_adc – aguarda ADSC = 0 (conversão concluída)                */
/* ------------------------------------------------------------------ */
.func wait_adc
wait_adc:
    lds  r16, ADCSRA
    sbrc r16, ADSC          /* pula se ADSC = 0 (pronto) */
    rjmp wait_adc
    lds  r16, ADCL          /* lê LSB primeiro (obrigatório) */
    lds  r17, ADCH
    ret
.endfunc

/* ------------------------------------------------------------------ */
/*  store – salva amostra no buffer via ponteiro X                    */
/* ------------------------------------------------------------------ */
.func store
store:
    st   X+, r16
    st   X+, r17
    adiw r24, 1             /* incrementa contador r25:r24 */
    ret
.endfunc

/* ------------------------------------------------------------------ */
/*  clear_variables – reseta contador e ponteiro para próxima janela  */
/* ------------------------------------------------------------------ */
.func clear_variables
clear_variables:
    clr  r24
    clr  r25
    call conf_pointer
    ret
.endfunc

/* ------------------------------------------------------------------ */
/*  goertzel_c – chama função C e atualiza LEDs                       */
/*  identifica_estado() é definida no código C;                        */
/*  retorna o estado em r24 (convenção avr-gcc: retorno de 8 bits)   */
/* ------------------------------------------------------------------ */
.extern identifica_estado

.func goertzel_c
goertzel_c:
    call identifica_estado
    mov  r17, r24           /* salva resultado antes de call */
    call atualiza_leds
    call clear_variables
    rjmp wait_interrupt
.endfunc

/* ------------------------------------------------------------------ */
/*  atualiza_leds                                                       */
/*    0 → apertar  (LED PD5)                                           */
/*    1 → afinado  (LED PD6)                                           */
/*    2 → afrouxar (LED PD7)                                           */
/* ------------------------------------------------------------------ */
.func atualiza_leds
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

led_afrouxar:
    sbi  PORTD, 7
    ret

led_apertar:
    sbi  PORTD, 5
    ret

led_afinado:
    sbi  PORTD, 6
    ret
.endfunc