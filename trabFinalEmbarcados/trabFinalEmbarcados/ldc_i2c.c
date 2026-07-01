#include <avr/io.h>
#include <util/delay.h>
#include <stdio.h>
#include "lcd_i2c.h"
#include "twi.h"

/* Endere�o I2C mais comum do m�dulo PCF8574 � 0x27 (alguns s�o 0x3F).
 * Se o LCD n�o responder, rode um scanner I2C rapido pra confirmar. */
#define LCD_ADDR      0x27
#define LCD_BACKLIGHT 0x08
#define LCD_EN        0x04
#define LCD_RW        0x02
#define LCD_RS        0x01

/* Precisa estar na mesma ordem de freqCordas[] em tuner.c */
static const char *nomesCordas[NUM_CORDAS] = {
    "E2", "A2", "D3", "G3", "B3", "E4"
};

/* ---- baixo nivel ---- */
static void lcd_write4(uint8_t nibble, uint8_t rs)
{
    uint8_t data = (nibble & 0xF0) | LCD_BACKLIGHT | (rs ? LCD_RS : 0);

    twi_start((LCD_ADDR << 1) | 0);
    twi_write(data | LCD_EN);   /* EN alto  -> HD44780 detecta borda de subida */
    twi_write(data);            /* EN baixo -> completa o pulso de clock       */
    twi_stop();
    _delay_us(50);
}

static void lcd_send(uint8_t value, uint8_t rs)
{
    lcd_write4(value & 0xF0, rs);
    lcd_write4((value << 4) & 0xF0, rs);
}

static void lcd_cmd(uint8_t cmd)  { lcd_send(cmd, 0); }
static void lcd_data(uint8_t d)   { lcd_send(d, 1); }

void lcd_init(void)
{
    twi_init();
    _delay_ms(50);

    /* sequ�ncia padr�o de inicializa��o do HD44780 em modo 4 bits */
    lcd_write4(0x30, 0); _delay_ms(5);
    lcd_write4(0x30, 0); _delay_us(150);
    lcd_write4(0x30, 0);
    lcd_write4(0x20, 0);           /* entra em modo 4 bits */

    lcd_cmd(0x28);   /* 4 bits, 2 linhas, fonte 5x8 */
    lcd_cmd(0x0C);   /* display on, cursor off, blink off */
    lcd_cmd(0x06);   /* modo de entrada: incrementa cursor */
    lcd_clear();
}

void lcd_clear(void)
{
    lcd_cmd(0x01);
    _delay_ms(2);
}

void lcd_set_cursor(uint8_t col, uint8_t row)
{
    static const uint8_t offsets[] = { 0x00, 0x40 };
    lcd_cmd(0x80 | (offsets[row & 1] + col));
}

void lcd_print(const char *str)
{
    while (*str) {
        lcd_data((uint8_t)*str++);
    }
}

/* ---- fun��o de alto nivel usada pelo main.c ---- */
void lcd_show_result(TunerResult res)
{
    char linha1[17];
    char linha2[17];

    if (res.string < 0) {
        snprintf(linha1, sizeof(linha1), "Aguardando...");
        linha2[0] = '\0';
    } else {
        snprintf(linha1, sizeof(linha1), "Corda: %s", nomesCordas[res.string]);

        const char *estadoTxt;
        switch (res.state) {
            case 0: estadoTxt = "Apertar  >>>"; break;
            case 1: estadoTxt = "Afinado   OK"; break;
            case 2: estadoTxt = "Afrouxar <<<"; break;
            default: estadoTxt = "?"; break;
        }
        snprintf(linha2, sizeof(linha2), "%s", estadoTxt);
    }

    lcd_set_cursor(0, 0);
    lcd_print("                ");  /* limpa a linha (mais rapido que lcd_clear) */
    lcd_set_cursor(0, 0);
    lcd_print(linha1);

    lcd_set_cursor(0, 1);
    lcd_print("                ");
    lcd_set_cursor(0, 1);
    lcd_print(linha2);
}