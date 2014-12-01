#ifndef FILE_H
#define FILE_H

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>

#define PAGESIZE 32 
#define PHYSICAL_MEM_SIZE 32768
#define STORAGE_SIZING 131072
#define PT_ENTRIES 1024 

typedef uint32_t u32 ;
typedef unsigned char uchar ;  
extern __shared__ u32 pt[] ;

__device__ u32 paging( uchar *buffer, u32 frame_num, u32 offset ) ;

__device__ void init_pageTable( int pt_entries ) ; 

int load_binaryFile( const char *DATAFILE, uchar *input, int STORAGE_SIZE ) ; 

void write_binaryFile( const char *OUTFILE, uchar *results, int input_size ) ; 

#endif 
