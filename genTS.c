#include <stdio.h>
#include <stdlib.h>
int main() {
	FILE *fptr = fopen("ts.bin", "wb");
	int ct = 131072;
	int i = 0;
	unsigned char key;
	while(ct--) {
		key = i;
		i = (i+1) % 128;
		fwrite(&key, sizeof(unsigned char), 1, fptr);
	}
	fclose(fptr);
	return 0;
}
