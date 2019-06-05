 #include <openssl/crypto.h>

int main(void) {
    uint a;
    a = OpenSSL_version_num();
    printf("0x0%x\n", a);
    return 0;
}
