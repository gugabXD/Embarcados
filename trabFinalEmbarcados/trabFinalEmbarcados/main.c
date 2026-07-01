/*
 * main.c - Afinador de viol�o (ATmega328P) - vers�o 100% C
 *
 * Substitui tuner.S + goertzel.c. Mesmo hardware, mesmos pinos,
 * mesmos timers/prescalers, mesma l�gica de debounce ? s� que
 * tudo em C, usando avr/interrupt.h, ent�o n�o h� mais problema
 * nenhum de conven��o de chamada entre assembly e C.
 *
 * Pinagem:
 *   LED apertar  -> PD5
 *   LED afinado  -> PD5 E PD7
 *   LED afrouxar -> PD7
 *   Bot�o "Modo" -> PD2 (INT0, pull-up interno, borda de descida)
 *   Bot�o "Nota" -> PD3 (reservado para o futuro)
 *
 */

#define AVR_TEST
// Modo de teste (ADC desligado)

#include <avr/io.h>
#include <avr/interrupt.h>
#include <stdint.h>
#include <math.h>
#include "tuner.h"
//#include "lcd_i2c.h"  // LCD

/* ------------------------------------------------------------------ */
/*  Vari�veis globais compartilhadas com as ISRs                       */
/* ------------------------------------------------------------------ */
static volatile int16_t buffer[N_AMOSTRAS];
static volatile uint16_t indice_amostra = 0;
static volatile uint8_t  buffer_ready   = 0;
static volatile uint8_t afinador_ligado = 0;
static uint8_t ultimo_estado = 1;

/* ------------------------------------------------------------------ */
/*  Prot�tipos                                                         */
/* ------------------------------------------------------------------ */
static void    conf_pinos(void);
static void    conf_timer0(void);
static void    conf_timer2(void);
static void    conf_int0(void);
static void    conf_adc(void);
static void    enable_timer2(void);
static void    disable_timer2(void);
static void    clear_buffer_state(void);
static void    atualiza_leds(int8_t estado);

/* ================================================================== */
/*  ISR INT0 - bot�o "Modo" (borda de descida em PD2)                  */
/*  Faz o debounce ocupado (mesmos ~500us do Timer0 no original) e,    */
/*  se o bot�o ainda estiver pressionado de fato, liga o Timer2 para   */
/*  come�ar a coletar as 400 amostras do ADC.                          */
/* ================================================================== */
ISR(INT0_vect)
{
    /* zera Timer0 e espera 125 ticks (16MHz/64 = 250kHz -> 500us) */
    TCNT0 = 0;
    while (TCNT0 != 125) {
        /* aguarda */
    }

    if (!(PIND & (1 << PD2))) {
        /* Inverte o estado do afinador (liga/desliga) */
        afinador_ligado = !afinador_ligado;
        
        if (afinador_ligado) {
            enable_timer2(); // Dispara a primeira amostragem
        } else {
            disable_timer2();
            PORTD &= ~((1 << PD5) | (1 << PD6) | (1 << PD7)); // Apaga os LEDs ao desligar
            buffer_ready = 0;
        }
    }
}

/* ================================================================== */
/*  ISR TIMER2 COMPA - coleta uma amostra do ADC a cada 500us          */
/*  (2 kHz de taxa de amostragem, igual ao original)                   */
/* ================================================================== */
ISR(TIMER2_COMPA_vect)
{
#ifdef AVR_TEST

    static uint16_t sample = 0;
    float freq = 110.0;

    float t = (float)sample / FS;

    buffer[indice_amostra] =
        512 +
        (int16_t)(400*sin(2.0*M_PI*freq*t));

    sample++;

#else

    /* Existing ADC code */

    ADCSRA |= (1 << ADSC);

    while (ADCSRA & (1 << ADSC));

    uint16_t valor = ADCL;
    valor |= ((uint16_t)ADCH)<<8;

    buffer[indice_amostra] = valor;

#endif

    indice_amostra++;

    if(indice_amostra >= N_AMOSTRAS)
    {
        disable_timer2();
        buffer_ready = 1;
    }
}

/* ================================================================== */
/*  main                                                                */
/* ================================================================== */
int main(void)
{
    conf_pinos();
    conf_timer0();
    conf_timer2();
    conf_int0();
    conf_adc();
    clear_buffer_state();
    //lcd_init(); // LCD

    sei();

    while (1) {
        if (buffer_ready) {
            TunerResult res = identifica_estado((const int16_t *)buffer);

            if (res.string != -1)
            {
	            ultimo_estado = res.state;
            }

            atualiza_leds(ultimo_estado);
            //lcd_show_result(res); // LCD
            
            // Em vez de apenas limpar e esperar o bot�o, fazemos isso:
            clear_buffer_state(); 
            
            if (afinador_ligado) {
                enable_timer2(); // Come�a a coletar a pr�xima janela de 400 amostras imediatamente
            }
        }
    }
}

/* ------------------------------------------------------------------ */
/*  conf_pinos                                                          */
/* ------------------------------------------------------------------ */
static void conf_pinos(void)
{
    DDRD  = 0b11100000; /* PD7,PD6,PD5 sa�da; resto entrada */
    PORTD = 0b00001100; /* pull-up em PD3 e PD2; LEDs apagados */
}

/* ------------------------------------------------------------------ */
/*  Timer0 - usado s� para o debounce (modo normal, prescaler 64)      */
/* ------------------------------------------------------------------ */
static void conf_timer0(void)
{
    TCCR0A = 0x00;
    TCCR0B = (1 << CS01) | (1 << CS00); /* prescaler 64 */
}

/* ------------------------------------------------------------------ */
/*  Timer2 - amostragem a 2kHz (CTC, prescaler 64, OCR2A = 124)        */
/*  Come�a desligado (TIMSK2 = 0); s� � habilitado pelo bot�o "Modo".  */
/* ------------------------------------------------------------------ */
static void conf_timer2(void)
{
    TCCR2A = (1 << WGM21);  /* CTC */
    TCCR2B = (1 << CS22);   /* prescaler 64 */
    OCR2A  = 124;           /* 16MHz/64/(124+1) = 2kHz */
    TIMSK2 = 0x00;          /* desabilitado at� apertar o bot�o */
}

static void enable_timer2(void)
{
    TCNT2  = 0;
    TIMSK2 = (1 << OCIE2A);
}

static void disable_timer2(void)
{
    TIMSK2 = 0x00;
}

/* ------------------------------------------------------------------ */
/*  INT0 - borda de descida no bot�o "Modo" (PD2)                      */
/* ------------------------------------------------------------------ */
static void conf_int0(void)
{
    EICRA = (1 << ISC01); /* ISC01=1, ISC00=0 -> falling edge */
    EIMSK = (1 << INT0);
}

/* ------------------------------------------------------------------ */
/*  ADC - Vref=Vcc, ajustado � direita, canal 0, prescaler 128          */
/* ------------------------------------------------------------------ */
static void conf_adc(void)
{
    ADMUX  = (1 << REFS0);                          /* AVcc, canal 0 */
    ADCSRA = (1 << ADEN) | (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0); /* prescaler 128 */
    ADCSRB = 0x00;
}

/* ------------------------------------------------------------------ */
/*  clear_buffer_state - prepara para a pr�xima janela de captura      */
/* ------------------------------------------------------------------ */
static void clear_buffer_state(void)
{
    cli();
    indice_amostra = 0;
    buffer_ready   = 0;
    sei();
}

/* ------------------------------------------------------------------ */
/*  atualiza_leds                                                       */
/*    0 -> apertar  (PD5)                                              */
/*    1 -> afinado  (PD6)                                              */
/*    2 -> afrouxar (PD7)                                              */
/* ------------------------------------------------------------------ */
static void atualiza_leds(int8_t estado)
{
    PORTD &= ~((1 << PD5) | (1 << PD6) | (1 << PD7));
    switch (estado) {
        case 0: PORTD |= (1 << PD6); break;
        case 1: PORTD |= (1 << PD6) | (1 <<PD7) ; break;
        case 2: PORTD |= (1 << PD7); break;
        default: break;
    }
}



