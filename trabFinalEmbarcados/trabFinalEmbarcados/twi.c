#include <avr/io.h>
#include <util/twi.h>
#include "twi.h"

#ifndef F_CPU
#define F_CPU 16000000UL
#endif

#define TWI_FREQ 100000UL   /* 100 kHz, padr�o para PCF8574 */

void twi_init(void)
{
    TWSR = 0x00;                                  /* prescaler = 1 */
    TWBR = ((F_CPU / TWI_FREQ) - 16) / 2;
    TWCR = (1 << TWEN);
}

static uint8_t twi_wait(void)
{
    uint32_t timeout = 100000UL;
    while (!(TWCR & (1 << TWINT)) && --timeout) {
        /* aguarda TWINT ou timeout (evita travar se o LCD n�o responder) */
    }
    return (timeout != 0);
}

uint8_t twi_start(uint8_t address_rw)
{
    TWCR = (1 << TWINT) | (1 << TWSTA) | (1 << TWEN);
    if (!twi_wait()) return 0;

    uint8_t status = TW_STATUS;
    if (status != TW_START && status != TW_REP_START) return 0;

    TWDR = address_rw;
    TWCR = (1 << TWINT) | (1 << TWEN);
    if (!twi_wait()) return 0;

    return (TW_STATUS == TW_MT_SLA_ACK);
}

void twi_stop(void)
{
    TWCR = (1 << TWINT) | (1 << TWSTO) | (1 << TWEN);
    while (TWCR & (1 << TWSTO)) {
        /* aguarda o STOP ser efetivado */
    }
}

uint8_t twi_write(uint8_t data)
{
    TWDR = data;
    TWCR = (1 << TWINT) | (1 << TWEN);
    if (!twi_wait()) return 0;

    return (TW_STATUS == TW_MT_DATA_ACK);
}