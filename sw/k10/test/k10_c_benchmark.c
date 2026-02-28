#include "k10.h"

uint32_t trap_handler(uint32_t mcause, uint32_t mepc) {
    (void)mcause;
    return mepc + 4; // Just return to next instruction
}

// Matrix Multiplication Benchmark
#define MATRIX_SIZE 16

uint32_t a[MATRIX_SIZE][MATRIX_SIZE];
uint32_t b[MATRIX_SIZE][MATRIX_SIZE];
uint32_t c[MATRIX_SIZE][MATRIX_SIZE];

void init_matrices() {
    uint32_t val = 1;
    for (int i = 0; i < MATRIX_SIZE; i++) {
        for (int j = 0; j < MATRIX_SIZE; j++) {
            a[i][j] = val++;
            b[i][j] = (i == j) ? 2 : 1; // Diagonal 2, rest 1
            c[i][j] = 0;
        }
    }
}

void multiply_matrices() {
    for (int i = 0; i < MATRIX_SIZE; i++) {
        for (int j = 0; j < MATRIX_SIZE; j++) {
            uint32_t sum = 0;
            for (int k = 0; k < MATRIX_SIZE; k++) {
                sum += a[i][k] * b[k][j];
            }
            c[i][j] = sum;
        }
    }
}

int main(void) {
    k10_puts("=== K10 CPI Performance Benchmark ===\n");
    
    init_matrices();

    uint32_t start_cycles = read_csr(mcycle);
    uint32_t start_instret = read_csr(minstret);

    k10_puts("Running 16x16 Matrix Multiplication...\n");
    multiply_matrices();

    uint32_t end_cycles = read_csr(mcycle);
    uint32_t end_instret = read_csr(minstret);

    uint32_t delta_cycles = end_cycles - start_cycles;
    uint32_t delta_instret = end_instret - start_instret;

    k10_puts("\n--- Results ---\n");
    k10_puts("Total Cycles      : "); k10_put_dec(delta_cycles); k10_puts("\n");
    k10_puts("Total Instructions: "); k10_put_dec(delta_instret); k10_puts("\n");

    uint32_t cpi_x1000 = (delta_cycles * 1000) / delta_instret;
    uint32_t cpi_int = cpi_x1000 / 1000;
    uint32_t cpi_frac = cpi_x1000 % 1000;

    k10_puts("CPI               : "); 
    k10_put_dec(cpi_int);
    k10_puts(".");
    if (cpi_frac < 10) k10_puts("00");
    else if (cpi_frac < 100) k10_puts("0");
    k10_put_dec(cpi_frac);
    k10_puts("\n");
    k10_puts("-----------------\n");

    sim_pass();
    return 0;
}
