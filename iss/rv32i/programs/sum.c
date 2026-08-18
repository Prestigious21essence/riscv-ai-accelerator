int main() {
    int sum = 0;
    for (int i = 1; i <= 5; i++) {
        sum += i;
    }
    // Write result to a fixed memory address so the emulator can check it
    volatile int *result = (volatile int *)0x1000;
    *result = sum;

    // Infinite loop to halt cleanly (no OS to return to)
    while (1) {}
    return 0;
}
