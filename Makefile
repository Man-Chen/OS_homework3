all:
	nvcc -arch=sm_30 main.cu -o vm

bonus:
	nvcc -arch=sm_30 bonus.cu -o mvm

debug:
	nvcc -arch=sm_30 main.cu -g -G -o vm-debug
clean:
	rm vm mvm vm-bonus
