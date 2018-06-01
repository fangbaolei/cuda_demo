#include "funset.hpp"
#include <iostream>
#include <cuda_runtime.h> // For the CUDA runtime routines (prefixed with "cuda_")
#include <device_launch_parameters.h>
#include "common.hpp"

// reference: C:\ProgramData\NVIDIA Corporation\CUDA Samples\v8.0\0_Simple\matrixMul
/* __global__: ���������޶���;���豸������;�������˵���,��������3.2�����Ͽ�����
�豸�˵���;�����ĺ����ķ���ֵ������void����;�Դ����ͺ����ĵ������첽��,����
�豸��ȫ�����������֮ǰ�ͷ�����;�Դ����ͺ����ĵ��ñ���ָ��ִ������,��������
�豸��ִ�к���ʱ��grid��block��ά��,�Լ���ص���(������<<<   >>>�����);
a kernel,��ʾ�˺���Ϊ�ں˺���(������GPU�ϵ�CUDA���м��㺯����Ϊkernel(�ں˺�
��),�ں˺�������ͨ��__global__���������޶�������);*/
template <int BLOCK_SIZE>
__global__ static void matrix_mul(const float* A, const float* B, float* C, int wA, int wB)
{
	/* gridDim: ���ñ���,���������߳������ά��,���������߳̿���˵,���
	������һ������,���������̸߳�ÿһά�Ĵ�С,��ÿ���̸߳����߳̿������.
	һ��gridΪ��ά,Ϊdim3���ͣ�
	blockDim: ���ñ���,����˵��ÿ��block��ά����ߴ�.Ϊdim3����,����
	��block������ά���ϵĳߴ���Ϣ;���������߳̿���˵,���������һ������,
	��������߳̿���ÿһά���߳�����;
	blockIdx: ���ñ���,�����а�����ֵ���ǵ�ǰִ���豸������߳̿������;��
	��˵����ǰthread���ڵ�block������grid�е�λ��,blockIdx.xȡֵ��Χ��
	[0,gridDim.x-1],blockIdx.yȡֵ��Χ��[0, gridDim.y-1].Ϊuint3����,
	������һ��block��grid�и���ά���ϵ�������Ϣ;
	threadIdx: ���ñ���,�����а�����ֵ���ǵ�ǰִ���豸������߳�����;����
	˵����ǰthread��block�е�λ��;����߳���һά�Ŀɻ�ȡthreadIdx.x,���
	�Ƕ�ά�Ļ��ɻ�ȡthreadIdx.y,�������ά�Ļ��ɻ�ȡthreadIdx.z;Ϊuint3��
	��,������һ��thread��block�и���ά�ȵ�������Ϣ */
	// Block index
	int bx = blockIdx.x;
	int by = blockIdx.y;
	// Thread index
	int tx = threadIdx.x;
	int ty = threadIdx.y;

	// Index of the first sub-matrix of A processed by the block
	int aBegin = wA * BLOCK_SIZE * by;
	// Index of the last sub-matrix of A processed by the block
	int aEnd = aBegin + wA - 1;
	// Step size used to iterate through the sub-matrices of A
	int aStep = BLOCK_SIZE;
	// Index of the first sub-matrix of B processed by the block
	int bBegin = BLOCK_SIZE * bx;
	// Step size used to iterate through the sub-matrices of B
	int bStep = BLOCK_SIZE * wB;
	// Csub is used to store the element of the block sub-matrix that is computed by the thread
	float Csub = 0;

	// Loop over all the sub-matrices of A and B required to compute the block sub-matrix
	for (int a = aBegin, b = bBegin; a <= aEnd; a += aStep, b += bStep) {
		/* __shared__: ���������޶�����ʹ��__shared__�޶�����������__device__��
		�������ã���ʱ�����ı���λ��block�еĹ���洢���ռ��У���block������ͬ
		���������ڣ�����ͨ��block�ڵ������̷߳��ʣ�__shared__��__constant__����
		Ĭ��Ϊ�Ǿ�̬�洢����__shared__ǰ���Լ�extern�ؼ��֣�����ʾ���Ǳ�����С
		��ִ�в���ȷ����__shared__����������ʱ���ܳ�ʼ�������Խ�CUDA C�Ĺؼ���
		__shared__��ӵ����������У��⽫ʹ�������פ���ڹ����ڴ��У�CUDA C����
		���Թ����ڴ��еı�������ͨ�������ֱ��ȡ��ͬ�Ĵ���ʽ */
		// Declaration of the shared memory array As used to store the sub-matrix of A
		__shared__ float As[BLOCK_SIZE][BLOCK_SIZE];
		// Declaration of the shared memory array Bs used to store the sub-matrix of B
		__shared__ float Bs[BLOCK_SIZE][BLOCK_SIZE];

		// Load the matrices from device memory to shared memory; each thread loads one element of each matrix
		As[ty][tx] = A[a + wA * ty + tx];
		Bs[ty][tx] = B[b + wB * ty + tx];

		/* __syncthreads: ���߳̿��е��߳̽���ͬ����CUDA�ܹ���ȷ���������߳̿�
		�е�ÿ���̶߳�ִ����__syncthreads()������û���κ��߳���ִ��
		__syncthreads()֮���ָ��;��ͬһ��block�е��߳�ͨ������洢��(shared
		memory)�������ݣ���ͨ��դ��ͬ��(������kernel��������Ҫͬ����λ�õ���
		__syncthreads()����)��֤�̼߳��ܹ���ȷ�ع������ݣ�ʹ��clock()������ʱ��
		���ں˺�����Ҫ������һ�δ���Ŀ�ʼ�ͽ�����λ�÷ֱ����һ��clock()������
		���������¼���������ڵ���__syncthreads()������һ��block�е�����
		thread��Ҫ��ʱ������ͬ�ģ����ֻ��Ҫ��¼ÿ��blockִ����Ҫ��ʱ������ˣ�
		������Ҫ��¼ÿ��thread��ʱ�� */
		// Synchronize to make sure the matrices are loaded
		__syncthreads();

		/* reference:
			https://devblogs.nvidia.com/parallelforall/new-compiler-features-cuda-8/
			https://stackoverflow.com/questions/22278631/what-does-pragma-unroll-do-exactly-does-it-affect-the-number-of-threads/22279341
		������Ĭ������½�ѭ��չ��С�Ĵ�����#pragma unroll�ܹ�ָ��ѭ��
		�Զ��ٴ�չ��(����Ա���뱣֤�����չ������ȷ��)��pragma unroll ��
		��������Ŵ����ѭ������ѡ��������һ�����֣�ָ������չ�����ٴ�ѭ����
		#pragma unroll 1 ��ʾ��ֹ��������ѭ��չ�������ûָ�����������ڳ���
		�ε�ѭ����ѭ������ȫչ�������ڲ�ȷ��������ѭ����ѭ��������չ����
		*/
#pragma unroll
		// Multiply the two matrices together; each thread computes one element of the block sub-matrix
		for (int k = 0; k < BLOCK_SIZE; ++k) {
			Csub += As[ty][k] * Bs[k][tx];
		}

		// Synchronize to make sure that the preceding computation is done before loading two new
		// sub-matrices of A and B in the next iteration
		__syncthreads();
	}

	// Write the block sub-matrix to device memory; each thread writes one element
	int c = wB * BLOCK_SIZE * by + BLOCK_SIZE * bx;
	C[c + wB * ty + tx] = Csub;
}

__global__ static void matrix_mul(const float* A, const float* B, float* C, int colsA, int rowsA, int colsB, int rowsB)
{
	int x = threadIdx.x + blockIdx.x * blockDim.x;
	int y = threadIdx.y + blockIdx.y * blockDim.y;
	int offset = x + y * blockDim.x * gridDim.x;

	float sum{ 0.f };
	for (int t = 0; t < colsA; ++t) {
		sum += A[y * colsA + t] * B[t * colsB + x];
	}

	C[offset] = sum;
}

int matrix_mul_gpu(const float* A, const float* B, float* C, int colsA, int rowsA, int colsB, int rowsB, float* elapsed_time)
{
	CHECK(colsA == rowsB);

	/* cudaEvent_t: CUDA event types���ṹ������, CUDA�¼������ڲ���GPU��ĳ
	�������ϻ��ѵ�ʱ�䣬CUDA�е��¼���������һ��GPUʱ���������CUDA�¼�����
	GPU��ʵ�ֵģ�������ǲ����ڶ�ͬʱ�����豸�������������Ļ�ϴ����ʱ*/
	cudaEvent_t start, stop;
	// cudaEventCreate: ����һ���¼������첽����
	cudaEventCreate(&start);
	cudaEventCreate(&stop);
	// cudaEventRecord: ��¼һ���¼����첽����,start��¼��ʼʱ��
	cudaEventRecord(start, 0);

	size_t lengthA{ colsA * rowsA * sizeof(float) }, lengthB{ colsB * rowsB * sizeof(float) };
	size_t lengthC{ rowsA * colsB * sizeof(float) };
	float *d_A{ nullptr }, *d_B{ nullptr }, *d_C{ nullptr };

	// cudaMalloc: ���豸�˷����ڴ�
	cudaMalloc(&d_A, lengthA);
	cudaMalloc(&d_B, lengthB);
	cudaMalloc(&d_C, lengthC);

	/* cudaMemcpy: �������˺��豸�˿�������,�˺������ĸ���������������֮һ:
	(1). cudaMemcpyHostToHost: �������ݴ������˵�������
	(2). cudaMemcpyHostToDevice: �������ݴ������˵��豸��
	(3). cudaMemcpyDeviceToHost: �������ݴ��豸�˵�������
	(4). cudaMemcpyDeviceToDevice: �������ݴ��豸�˵��豸��
	(5). cudaMemcpyDefault: ��ָ��ֵ�Զ��ƶϿ������ݷ���,��Ҫ֧��
	ͳһ����Ѱַ(CUDA6.0�����ϰ汾)
	cudaMemcpy��������������ͬ���� */
	cudaMemcpy(d_A, A, lengthA, cudaMemcpyHostToDevice);
	cudaMemcpy(d_B, B, lengthB, cudaMemcpyHostToDevice);
	//cudaMemcpy(d_C, C, lengthC, cudaMemcpyHostToDevice);

	const int block_size{ 32 };
	/* dim3: ����uint3���������ʸ�����ͣ��൱����3��unsigned int������ɵ�
	�ṹ�壬�ɱ�ʾһ����ά���飬�ڶ���dim3���ͱ���ʱ������û�и�ֵ��Ԫ�ض�
	�ᱻ����Ĭ��ֵ1 */
	dim3 dimsA(colsA, rowsA, 1);
	dim3 dimsB(colsB, rowsB, 1);
	CHECK(dimsA.x == dimsB.y);
	//fprintf(stderr, "MatrixA(%d,%d), MatrixB(%d,%d)\n", dimsA.x, dimsA.y, dimsB.x, dimsB.y);

	dim3 threads(block_size, block_size);
	dim3 grid(dimsB.x / threads.x, dimsA.y / threads.y);

	/* <<< >>>: ΪCUDA����������,ָ���߳�������߳̿�ά�ȵ�,����ִ�в�
	����CUDA������������ʱϵͳ,����˵���ں˺����е��߳�����,�Լ��߳������
	��֯��;����������Щ���������Ǵ��ݸ��豸����Ĳ���,���Ǹ�������ʱ���
	�����豸����,���ݸ��豸���뱾��Ĳ����Ƿ���Բ�����д��ݵ�,�����׼�ĺ�
	������һ��;��ͬ�����������豸���̵߳���������֯��ʽ�в�ͬ��Լ��;����
	��Ϊkernel���õ�����������������㹻�Ŀռ�,�ٵ���kernel����,������
	GPU����ʱ�ᷢ������,����Խ���;
	ʹ������ʱAPIʱ,��Ҫ�ڵ��õ��ں˺�����������б�ֱ����<<<Dg,Db,Ns,S>>>
	����ʽ����ִ������,���У�Dg��һ��dim3�ͱ���,��������grid��ά�Ⱥ͸���
	ά���ϵĳߴ�.���ú�Dg��,grid�н���Dg.x*Dg.y*Dg.z��block;Db��
	һ��dim3�ͱ���,��������block��ά�Ⱥ͸���ά���ϵĳߴ�.���ú�Db��,ÿ��
	block�н���Db.x*Db.y*Db.z��thread;Ns��һ��size_t�ͱ���,ָ������Ϊ�˵�
	�ö�̬����Ĺ���洢����С,��Щ��̬����Ĵ洢���ɹ�����Ϊ�ⲿ����
	(extern __shared__)�������κα���ʹ��;Ns��һ����ѡ����,Ĭ��ֵΪ0;SΪ
	cudaStream_t����,�����������ں˺�����������.S��һ����ѡ����,Ĭ��ֵ0. */
	matrix_mul<block_size> <<< grid, threads >>>(d_A, d_B, d_C, dimsA.x, dimsB.x); // ���нϿ�
	//matrix_mul<< < grid, threads >> >(d_A, d_B, d_C, colsA, rowsA, colsB, rowsB);

	/* cudaDeviceSynchronize: kernel���������첽��, Ϊ�˶�λ���Ƿ����, һ
	����Ҫ����cudaDeviceSynchronize��������ͬ��; ����һֱ��������״̬��ֱ��
	ǰ����������������Ѿ���ȫ��ִ����ϣ����ǰ��ִ�е�ĳ������ʧ�ܣ�����
	����һ�����󣻵��������ж������������֮����ĳһ����Ҫͨ��ʱ���Ǿͱ���
	����һ�㴦����ͬ������䣬��cudaDeviceSynchronize���첽����
	reference: https://stackoverflow.com/questions/11888772/when-to-call-cudadevicesynchronize */
	//cudaDeviceSynchronize();

	cudaMemcpy(C, d_C, lengthC, cudaMemcpyDeviceToHost);
	// cudaFree: �ͷ��豸����cudaMalloc����������ڴ�
	cudaFree(d_A);
	cudaFree(d_B);
	cudaFree(d_C);

	// cudaEventRecord: ��¼һ���¼����첽����,stop��¼����ʱ��
	cudaEventRecord(stop, 0);
	// cudaEventSynchronize: �¼�ͬ�����ȴ�һ���¼���ɣ��첽����
	cudaEventSynchronize(stop);
	// cudaEventElapseTime: ���������¼�֮�侭����ʱ�䣬��λΪ���룬�첽����
	cudaEventElapsedTime(elapsed_time, start, stop);
	// cudaEventDestroy: �����¼������첽����
	cudaEventDestroy(start);
	cudaEventDestroy(stop);

	return 0;
}

