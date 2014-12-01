vm:main.o file.o
	nvcc -arch=sm_30 main.o file.o -g -G -rdc=true -o vm

main.o:main.cu
	nvcc -arch=sm_30 main.cu -rdc=true -c -g -G

file.o:file.cu
	nvcc -arch=sm_30 file.cu -rdc=true -c -g -G

clean:
	rm vm file.o main.o snapshot.bin a.txt b.txt
	

