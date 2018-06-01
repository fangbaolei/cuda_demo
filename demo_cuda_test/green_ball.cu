#include "funset.hpp"
#include <iostream>
#include <algorithm>
#include <memory>
#include <cuda_runtime.h> // For the CUDA runtime routines (prefixed with "cuda_")
#include <device_launch_parameters.h>
#include "common.hpp"

/* __global__: ���������޶���;���豸������;�������˵���,��������3.2�����Ͽ�����
�豸�˵���;�����ĺ����ķ���ֵ������void����;�Դ����ͺ����ĵ������첽��,����
�豸��ȫ�����������֮ǰ�ͷ�����;�Դ����ͺ����ĵ��ñ���ָ��ִ������,��������
�豸��ִ�к���ʱ��grid��block��ά��,�Լ���ص���(������<<<   >>>�����);
a kernel,��ʾ�˺���Ϊ�ں˺���(������GPU�ϵ�CUDA���м��㺯����Ϊkernel(�ں˺�
��),�ں˺�������ͨ��__global__���������޶�������); */
__global__ static void green_ball(unsigned char* ptr, int width, int height)
{
	/* gridDim: ���ñ���,���������߳������ά��,���������߳̿���˵,���
	������һ������,���������̸߳�ÿһά�Ĵ�С,��ÿ���̸߳����߳̿������.
	Ϊdim3���ͣ�
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
	// map from threadIdx/BlockIdx to pixel position
	int x = threadIdx.x + blockIdx.x * blockDim.x;
	int y = threadIdx.y + blockIdx.y * blockDim.y;
	int offset = x + y * blockDim.x * gridDim.x;

	/* __shared__: ���������޶�����ʹ��__shared__�޶�����������__device__��
	�������ã���ʱ�����ı���λ��block�еĹ���洢���ռ��У���block������ͬ
	���������ڣ�����ͨ��block�ڵ������̷߳��ʣ�__shared__��__constant__����
	Ĭ��Ϊ�Ǿ�̬�洢����__shared__ǰ���Լ�extern�ؼ��֣�����ʾ���Ǳ�����С
	��ִ�в���ȷ����__shared__����������ʱ���ܳ�ʼ�������Խ�CUDA C�Ĺؼ���
	__shared__��ӵ����������У��⽫ʹ�������פ���ڹ����ڴ��У�CUDA C����
	���Թ����ڴ��еı�������ͨ�������ֱ��ȡ��ͬ�Ĵ���ʽ */
	__shared__ float shared[16][16]; // == threads_block

	// now calculate the value at that position
	const float period = 128.0f;

	shared[threadIdx.x][threadIdx.y] = 255 * (sinf(x*2.0f*PI / period) + 1.0f) *(sinf(y*2.0f*PI / period) + 1.0f) / 4.0f;

	/* __syncthreads: ���߳̿��е��߳̽���ͬ����CUDA�ܹ���ȷ���������߳̿�
	�е�ÿ���̶߳�ִ����__syncthreads()������û���κ��߳���ִ��
	__syncthreads()֮���ָ��;��ͬһ��block�е��߳�ͨ������洢��(shared
	memory)�������ݣ���ͨ��դ��ͬ��(������kernel��������Ҫͬ����λ�õ���
	__syncthreads()����)��֤�̼߳��ܹ���ȷ�ع������ݣ�ʹ��clock()������ʱ��
	���ں˺�����Ҫ������һ�δ���Ŀ�ʼ�ͽ�����λ�÷ֱ����һ��clock()������
	���������¼���������ڵ���__syncthreads()������һ��block�е�����
	thread��Ҫ��ʱ������ͬ�ģ����ֻ��Ҫ��¼ÿ��blockִ����Ҫ��ʱ������ˣ�
	������Ҫ��¼ÿ��thread��ʱ�� */
	// removing this syncthreads shows graphically what happens
	// when it doesn't exist.this is an example of why we need it.
	__syncthreads();

	ptr[offset * 4 + 0] = 0;
	ptr[offset * 4 + 1] = shared[/*15 - */threadIdx.x][/*15 - */threadIdx.y];
	ptr[offset * 4 + 2] = 0;
	ptr[offset * 4 + 3] = 255;
}

int green_ball_gpu(unsigned char* ptr, int width, int height, float* elapsed_time)
{
	/* cudaEvent_t: CUDA event types,�ṹ������, CUDA�¼�,���ڲ���GPU��ĳ
	�������ϻ��ѵ�ʱ��,CUDA�е��¼���������һ��GPUʱ���,����CUDA�¼�����
	GPU��ʵ�ֵ�,������ǲ����ڶ�ͬʱ�����豸�������������Ļ�ϴ����ʱ */
	cudaEvent_t start, stop;
	// cudaEventCreate: ����һ���¼�����,�첽����
	cudaEventCreate(&start);
	cudaEventCreate(&stop);
	// cudaEventRecord: ��¼һ���¼�,�첽����,start��¼��ʼʱ��
	cudaEventRecord(start, 0);

	const size_t length{ width * height * 4 * sizeof(unsigned char) };
	unsigned char* dev{ nullptr };
	// cudaMalloc: ���豸�˷����ڴ�
	cudaMalloc(&dev, length);

	const int threads_block{ 16 };
	dim3 blocks(width / threads_block, height / threads_block);
	dim3 threads(threads_block, threads_block);
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
	green_ball << <blocks, threads >> >(dev, width, height);

	/* cudaMemcpy: �������˺��豸�˿�������,�˺������ĸ���������������֮һ:
	(1). cudaMemcpyHostToHost: �������ݴ������˵�������
	(2). cudaMemcpyHostToDevice: �������ݴ������˵��豸��
	(3). cudaMemcpyDeviceToHost: �������ݴ��豸�˵�������
	(4). cudaMemcpyDeviceToDevice: �������ݴ��豸�˵��豸��
	(5). cudaMemcpyDefault: ��ָ��ֵ�Զ��ƶϿ������ݷ���,��Ҫ֧��
	ͳһ����Ѱַ(CUDA6.0�����ϰ汾)
	cudaMemcpy��������������ͬ���� */
	cudaMemcpy(ptr, dev, length, cudaMemcpyDeviceToHost);

	// cudaFree: �ͷ��豸����cudaMalloc����������ڴ�
	cudaFree(dev);

	// cudaEventRecord: ��¼һ���¼�,�첽����,stop��¼����ʱ��
	cudaEventRecord(stop, 0);
	// cudaEventSynchronize: �¼�ͬ��,�ȴ�һ���¼����,�첽����
	cudaEventSynchronize(stop);
	// cudaEventElapseTime: ���������¼�֮�侭����ʱ��,��λΪ����,�첽����
	cudaEventElapsedTime(elapsed_time, start, stop);
	// cudaEventDestroy: �����¼�����,�첽����
	cudaEventDestroy(start);
	cudaEventDestroy(stop);

	return 0;
}