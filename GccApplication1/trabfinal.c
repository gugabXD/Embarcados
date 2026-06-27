#include <avr/io.h>
#include <stdint.h>
#include <math.h>

#define FS          2000.0
#define N_AMOSTRAS  400
#define NUM_CORDAS  6

/* Frequ?ncias fundamentais da afina??o padr?o (corda 6 a 1) */
static const double freqCordas[NUM_CORDAS] = {
    82.41,   /* E2 - 6a corda (mais grave)  */
    110.00,  /* A2 - 5a corda                */
    146.83,  /* D3 - 4a corda                */
    196.00,  /* G3 - 3a corda                */
    246.94,  /* B3 - 2a corda                */
    329.63   /* E4 - 1a corda (mais aguda)   */
};

/* Deslocamento relativo usado para os bins "abaixo"/"acima" do
 * alvo (proporcional ? frequ?ncia, equivalente a ~ +-25-30 cents) */
#define DESVIO_REL   0.018

/* Limiar m?nimo de energia para considerar que h? sinal real de
 * corda tocando. Quando o afinador est? ligado ele fica captando ondas de 
 * fundo; se a energia m?xima encontrada for menor que LIMIAR_RUIDO, 
 * o c?digo entende que ? s? barulho e aborta mantendo o ?ltimo LED. */
#define LIMIAR_RUIDO 200.0

extern int16_t buffer[N_AMOSTRAS];

static double   goertzelMag(const int16_t *amostras, int n, double freqAlvo, double fs);


// identifica_estado: roda a captura + Goertzel e devolve o estado
 // (0 = apertar, 1 = afinado, 2 = afrouxar) para o assembly.

int8_t identifica_estado(void) {
    static int8_t ultimo_estado = 1; /* come?a como "afinado" */


    /* Remove o n?vel DC do sinal (o MAX4466 centra a sa?da em
     * aproximadamente Vcc/2) antes de aplicar o Goertzel */
    long soma = 0;
    for (int i = 0; i < N_AMOSTRAS; i++) {
        soma += buffer[i];
    }
    int16_t media = (int16_t)(soma / N_AMOSTRAS);
    for (int i = 0; i < N_AMOSTRAS; i++) {
        buffer[i] -= media;
    }

    /* 1) Identifica a corda mais prov?vel: maior energia entre as
     * 6 frequ?ncias fundamentais */
    double melhorMag   = -1.0;
    int8_t melhorCorda = -1;

    for (int c = 0; c < NUM_CORDAS; c++) {
        double mag = goertzelMag(buffer, N_AMOSTRAS, freqCordas[c], FS);
        if (mag > melhorMag) {
            melhorMag   = mag;
            melhorCorda = c;
        }
    }

    if (melhorCorda < 0 || melhorMag < LIMIAR_RUIDO) {
        /* Sem sinal confi?vel: mant?m o ?ltimo estado conhecido,
         * em vez de apagar/trocar o LED ? toa por causa de ru?do */
        return ultimo_estado;
    }

    /* 2) Refinamento fino: compara a energia em 3 bins ao redor da
     * frequ?ncia alvo da corda identificada */
    double fAlvo = freqCordas[melhorCorda];
    double delta = fAlvo * DESVIO_REL;

    double magGrave = goertzelMag(buffer, N_AMOSTRAS, fAlvo - delta, FS);
    double magAlvo  = goertzelMag(buffer, N_AMOSTRAS, fAlvo,         FS);
    double magAguda = goertzelMag(buffer, N_AMOSTRAS, fAlvo + delta, FS);

    if (magAlvo >= magGrave && magAlvo >= magAguda) {
        ultimo_estado = 1;   /* afinado */
    } else if (magGrave > magAguda) {
        ultimo_estado = 0;   /* som mais grave que o alvo -> apertar a corda */
    } else {
        ultimo_estado = 2;   /* som mais agudo que o alvo -> afrouxar a corda */
    }

    return ultimo_estado;
}

/* ------------------------------------------------------------------
 * goertzelMag: calcula a magnitude do sinal em uma ?nica frequ?ncia
 * (freqAlvo), equivalente a um bin da DFT, com custo computacional
 * muito menor que uma FFT completa.
 * --------------------------------------------------------------- */
static double goertzelMag(const int16_t *amostras, int n, double freqAlvo, double fs) {
    int    k       = (int)(0.5 + (n * freqAlvo) / fs);
    double w       = (2.0 * M_PI / n) * k;
    double cosseno = cos(w);
    double seno    = sin(w);
    double coef    = 2.0 * cosseno;

    double q0, q1 = 0.0, q2 = 0.0;

    for (int i = 0; i < n; i++) {
        q0 = coef * q1 - q2 + (double)amostras[i];
        q2 = q1;
        q1 = q0;
    }

    double real = q1 - q2 * cosseno;
    double imag = q2 * seno;

    return sqrt(real * real + imag * imag);
}