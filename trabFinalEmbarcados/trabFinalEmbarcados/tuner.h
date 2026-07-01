#ifndef TUNER_H
#define TUNER_H

#include <stdint.h>

#define N_AMOSTRAS 1000
#define FS          2000.0f
#define NUM_CORDAS  6

typedef struct
{
	int8_t string;
	int8_t state;
	float magnitude;
} TunerResult;

TunerResult identifica_estado(const int16_t *samples);

#endif