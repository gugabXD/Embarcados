#ifndef TWI_H
#define TWI_H
 
#include <stdint.h>
 
/* Driver TWI (I2C) minimalista, por polling, s� para uso do LCD.
 * N�o usa interrup��es -> n�o interfere em nada do Timer0/Timer2/INT0. */
 
void    twi_init(void);
uint8_t twi_start(uint8_t address_rw);  /* address_rw = (endereco<<1) | (0=write,1=read) */
void    twi_stop(void);
uint8_t twi_write(uint8_t data);        /* retorna 1 se ACK recebido */
 
#endif
 