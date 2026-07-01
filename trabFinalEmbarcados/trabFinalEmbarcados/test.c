#include <stdio.h>
#include <stdint.h>
#include <math.h>

#include "tuner.h"

#define ADC_OFFSET     512
#define TEST_AMPLITUDE 400

static int16_t samples[N_AMOSTRAS];

static const double testFreqs[NUM_CORDAS] =
{
	82.41,
	110.00,
	146.83,
	196.00,
	246.94,
	329.63
};

void generateSine(double freq)
{
	for (int i = 0; i < N_AMOSTRAS; i++)
	{
		double t = (double)i / FS;

		samples[i] = ADC_OFFSET +
		(int16_t)(TEST_AMPLITUDE *
		sin(2.0 * M_PI * freq * t));
	}
}

int main(void)
{
	for (int i = 0; i < NUM_CORDAS; i++)
	{
		double target = testFreqs[i];

		double tests[] =
		{
			target * 0.985,   // flat
			target,          // in tune
			target * 1.02    // sharp
		};

		for (int j = 0; j < 3; j++)
		{
			generateSine(tests[j]);

			TunerResult res = identifica_estado(samples);

			if (res.string >= 0)
			{
				printf("Input: %.2f Hz -> String %d (target = %.2f Hz), State %d, Magnitude %.2f\n",
					tests[j],
					res.string,
					testFreqs[res.string],
					res.state,
					res.magnitude);
			}
			else
			{
				printf("Input: %.2f Hz -> No string detected, State %d, Magnitude %.2f\n",
					tests[j],
					res.state,
					res.magnitude);
			}
		}

		printf("\n");
	}

	while (1);

	return 0;
}