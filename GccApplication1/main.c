extern void config(void);

int main(void) {
    config();   // never returns, loops internally
    while(1);       // unreachable, just for safety
}