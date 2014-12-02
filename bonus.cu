#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>

// Define constants and data types
#define PAGE_SIZE           32
#define PHYSICAL_MEM_SIZE   32768
#define MEMMORY_SEGMENT		32768
#define STORAGE_SIZE        131072
#define DATAFILE            "./data.bin"
#define OUTPUTFILE          "./snapshot.bin"
typedef unsigned char uchar;
typedef uint32_t u32;
const uint32_t VALID    		= 0 | 1;
const uint32_t INVALID			= 0;
const uint32_t PAGENUMBERMASK	= 0x00003FFE;
const uint32_t LASTTIMEMASK		= 0xFFFFC000;
const uint32_t PIDMASK			= 0xC0000000;
const uint32_t DNE				= 0xFFFFFFFF;

// Lock & Unlock
#define __LOCK();	for(int p = 0; p < 4; p++) {if(threadIdx.x == p) {
#define __UNLOCK();	} __syncthreads(); }
#define __GET_BASE() p*MEMMORY_SEGMENT
// Declare variables
__device__ __managed__ int PAGE_ENTRIES = 0;
__device__ __managed__ int PAGEFAULT = 0;
__device__ __managed__ int CURRENTTIME = 0;
__device__ __managed__ uchar storage[STORAGE_SIZE];
__device__ __managed__ uchar results[STORAGE_SIZE];
__device__ __managed__ uchar input[STORAGE_SIZE];
extern __shared__ u32 pageTable[];

// Function
// ******************************************************************
// Initialize
__device__ void initPageTable(int entries) {
    for (int i = 0; i < entries; i++) {
        pageTable[i] = INVALID;
    }
}
// ******************************************************************

// ******************************************************************
// File I/O
int loadBinaryFile(char *fileName, uchar *input, int storageSize) {
    FILE *fptr = fopen(fileName, "rb");
    // Get size
    fseek(fptr, 0, SEEK_END);
    int size = ftell(fptr);
    rewind(fptr);
    // Read data from input file
    fread(input, sizeof(unsigned char), size, fptr);
    if (storageSize < size) {
        printf("ERROR: Storage size is too small to store input data!\n");
    }
	fclose(fptr);
    return size;
}

void writeBinaryFile(char *fileName, uchar *input, int storageSize) {
    FILE *fptr = fopen(fileName, "wb");
    // Read data from input file
    fwrite(input, sizeof(unsigned char), storageSize, fptr);
	fclose(fptr);
}
// ******************************************************************

// ******************************************************************
// Read/Write
__device__ u32 getPid(u32 PTE) {
	return (PTE & PIDMASK) >> 30;
}
__device__ u32 isValid(u32 PTE) {
	return PTE & VALID;
}
__device__ u32 getPageNumber(u32 PTE) {
	return (PTE & PAGENUMBERMASK) >> 1;
}
__device__ u32 getLastUsedTime(u32 PTE) {
	return (PTE & LASTTIMEMASK) >> 14;
}
__device__ u32 makePTE(u32 pid, u32 time, u32 pageNumber, u32 validbit) {
	return (pid << 30) | (time << 14) | (pageNumber << 1) | validbit;
}
__device__ u32 paging(uchar *memory, u32 pageNumber, u32 pageOffset) {
	// ******************************************************************** //
	// How I store infomation in a PTE:										//
	// |--|----------------|-------------|-|								//
	// |33|2222222222111111|1111-8-6-4-2-|0|								//
	// |10|9876543210987654|32109-7-5-3-1|-|								//
	// |--|----------------|-------------|-|								//
	// |  |Last used time  | Page Number | | <-- last one bit is valid bit	//
	// |--|----------------|-------------|-|								//
	// ******************************************************************** //

	CURRENTTIME++;
	// Find if the target page exists
	for (u32 i = 0; i < PAGE_ENTRIES; i++) {
		if (isValid(pageTable[i]) 
			&& threadIdx.x == getPid(pageTable[i]) 
			&& pageNumber == getPageNumber(pageTable[i])) {
			// Update time
			pageTable[i] = makePTE(threadIdx.x, CURRENTTIME, pageNumber, VALID);
			return i * PAGE_SIZE + pageOffset;
		}
	}

	// Find if there is a empty entry to place
	for (u32 i = 0; i < PAGE_ENTRIES; i++) {
		if (isValid(pageTable[i]) == 0) {
			// Because of a empty hole, it must be a pagefault
			PAGEFAULT++;
			// Update PTE
			pageTable[i] = makePTE(threadIdx.x, CURRENTTIME, pageNumber, VALID);
			return i * PAGE_SIZE + pageOffset;
		}
	}

	// Find a place for swaping in by the RULE of LRU
	u32 leastEntry = DNE;
	u32 leastTime  = DNE;
	for (u32 i = 0; i < PAGE_ENTRIES; i++) {
		if (leastTime > getLastUsedTime(pageTable[i]) && threadIdx.x == getPid(pageTable[i])) {
			leastTime = getLastUsedTime(pageTable[i]);
			leastEntry = i;
		}
	}
	// Replace & update infos
	PAGEFAULT++;
	for (u32 j = 0;
			j < PAGE_SIZE;
			j++) {
		u32 memoryAddress = leastEntry * PAGE_SIZE + j;
		u32 storageAddress = pageNumber * PAGE_SIZE + j;
		u32 toStorageAddress = getPageNumber(pageTable[leastEntry]) * PAGE_SIZE + j;
		storage[toStorageAddress] = memory[memoryAddress];
		memory[memoryAddress] = storage[storageAddress];
	}
	pageTable[leastEntry] = makePTE(threadIdx.x, CURRENTTIME, pageNumber, VALID);
	return leastEntry * PAGE_SIZE + pageOffset;
}

__device__ uchar Gread(uchar *memory, u32 address) {
	u32 pageNumber = address/PAGE_SIZE;
	u32 pageOffset = address%PAGE_SIZE;

	u32 reMappingAddress = paging(memory, pageNumber, pageOffset);
	return memory[reMappingAddress];
}

__device__ void Gwrite(uchar *memory, u32 address, uchar writeValue) {
	u32 pageNumber = address/PAGE_SIZE;
	u32 pageOffset = address%PAGE_SIZE;

	u32 reMappingAddress = paging(memory, pageNumber, pageOffset);
	memory[reMappingAddress] = writeValue;
}

__device__ void snapshot(uchar *result, uchar *memory, int offset, int input_size) {
	for (int i = 0; i < input_size; i++) {
		result[i] = Gread(memory, i+offset);
	}
}
// ******************************************************************

// ******************************************************************
// Kernel function
__global__ void mykernel(int input_size) {
    __shared__ uchar data[PHYSICAL_MEM_SIZE];
    PAGE_ENTRIES = PHYSICAL_MEM_SIZE/PAGE_SIZE;
	if (threadIdx.x == 0)
    	initPageTable(PAGE_ENTRIES);
	
	//##Gwrite / Gread code section start###
	__LOCK();
		for(int i = 0; i < input_size; i++) {
			Gwrite(data, i+__GET_BASE(), input[i+__GET_BASE()]);
		}
	__UNLOCK();
	for(int i = input_size - 1; i >= input_size - 10; i--) {
		__LOCK();
			int value = Gread(data, i+__GET_BASE());
		__UNLOCK();
	}
	//the last line of Gwrite/Gread code section should be snapshot ()
	__LOCK();
		snapshot(results+__GET_BASE(), data, __GET_BASE(), input_size);
	__UNLOCK();
	//###Gwrite/Gread code section end### 
}
// ******************************************************************

int main() {
    int input_size = loadBinaryFile(DATAFILE, input, STORAGE_SIZE);
    cudaSetDevice(4);
    mykernel<<<1, 4, 16384>>>(input_size/4);
    cudaDeviceSynchronize();
    cudaDeviceReset();

    writeBinaryFile(OUTPUTFILE, results, input_size);
    printf("pagefault times = %d\n", PAGEFAULT);
    return 0;
}
