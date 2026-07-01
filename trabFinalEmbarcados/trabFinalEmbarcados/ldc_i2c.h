#ifndef LCD_I2C_H
#define LCD_I2C_H
 
#include <stdint.h>
#include "tuner.h"   /* para o tipo TunerResult */
 
void lcd_init(void);
void lcd_clear(void);
void lcd_set_cursor(uint8_t col, uint8_t row);
void lcd_print(const char *str);
 
/* Fun��o de alto n�vel: recebe o TunerResult e atualiza as duas
 * linhas do LCD (corda + estado). N�o mexe em ISRs nem no buffer
 * de amostragem -- s� faz chamadas I2C por polling a partir do
 * loop principal, exatamente como atualiza_leds(). */
void lcd_show_result(TunerResult res);
 
#endif
 