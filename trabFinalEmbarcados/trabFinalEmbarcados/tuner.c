#include "tuner.h"

#include <math.h>

#define PI_F 3.14159265358979f

static float goertzelMag(const int16_t *amostras, int n, float freqAlvo, float fs);

/* Frequências fundamentais da afinação padrão (corda 6 a 1) */
static const float freqCordas[NUM_CORDAS] = {
    82.41f,   /* E2 - 6a corda (mais grave) */
    110.00f,  /* A2 - 5a corda              */
    146.83f,  /* D3 - 4a corda              */
    196.00f,  /* G3 - 3a corda              */
    246.94f,  /* B3 - 2a corda              */
    329.63f   /* E4 - 1a corda (mais aguda) */
};

/* Desvio relativo usado para os bins "abaixo"/"acima" do alvo
 * (proporcional à frequência, equivalente a ~ +-25-30 cents) */
#define DESVIO_REL    0.018f

/* Limiar mínimo de energia para considerar que há sinal real de
 * corda tocando, e não apenas ruído de fundo. */
#define LIMIAR_RUIDO  200.0f

TunerResult identifica_estado(const int16_t *samples)
{
	TunerResult r;
    /* tira uma cópia local não-volátil para o Goertzel trabalhar
     * (o buffer não muda mais nesse ponto, pois Timer2 está parado) */
    int16_t amostras[N_AMOSTRAS];
    long soma = 0;
    for (int i = 0; i < N_AMOSTRAS; i++) {
        amostras[i] = samples[i];
        soma += amostras[i];
    }

    /* remove o nível DC (MAX4466 centra a saída em ~Vcc/2) */
    int16_t media = (int16_t)(soma / N_AMOSTRAS);
    for (int i = 0; i < N_AMOSTRAS; i++) {
        amostras[i] -= media;
    }

    /* 1) identifica a corda mais provável: maior energia entre as 6
     *    frequências fundamentais */
    float melhorMag   = -1.0f;
    int8_t melhorCorda = -1;
    for (int c = 0; c < NUM_CORDAS; c++) {
        float mag = goertzelMag(amostras, N_AMOSTRAS, freqCordas[c], FS);
        if (mag > melhorMag) {
            melhorMag   = mag;
            melhorCorda = c;
        }
    }

    if (melhorCorda < 0 || melhorMag < LIMIAR_RUIDO) {
	    TunerResult r;

	    r.string = -1;
	    r.state = -1;
	    r.magnitude = melhorMag;

	    return r;
    }

    /* 2) refinamento fino: compara energia em 3 bins ao redor da
     *    frequência alvo da corda identificada */
    float fAlvo = freqCordas[melhorCorda];
    float delta = fAlvo * DESVIO_REL;
    float magGrave = goertzelMag(amostras, N_AMOSTRAS, fAlvo - delta, FS);
    float magAlvo  = goertzelMag(amostras, N_AMOSTRAS, fAlvo,         FS);
    float magAguda = goertzelMag(amostras, N_AMOSTRAS, fAlvo + delta, FS);

    if (magAlvo >= magGrave && magAlvo >= magAguda) {
        r.state = 1;   /* afinado */
    } else if (magGrave > magAguda) {
        r.state = 0;   /* grave demais -> apertar a corda */
    } else {
        r.state = 2;   /* agudo demais -> afrouxar a corda */
    }

    r.string = melhorCorda;
    r.magnitude = melhorMag;
	
	return r;
}

static float goertzelMag(const int16_t *amostras, int n, float freqAlvo, float fs)
{
    int   k       = (int)(0.5f + (n * freqAlvo) / fs);
    float w       = (2.0f * PI_F / n) * k;
    float cosseno = cosf(w);
    float seno    = sinf(w);
    float coef    = 2.0f * cosseno;
    float q0, q1 = 0.0f, q2 = 0.0f;

    for (int i = 0; i < n; i++) {
        q0 = coef * q1 - q2 + (float)amostras[i];
        q2 = q1;
        q1 = q0;
    }

    float real = q1 - q2 * cosseno;
    float imag = q2 * seno;
    return sqrtf(real * real + imag * imag);
}