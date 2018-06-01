#include "funset.hpp"
#include <iostream>
#include <algorithm>
#include <memory>
#include <vector>
#include <cuda_runtime.h> // For the CUDA runtime routines (prefixed with "cuda_")
#include <device_launch_parameters.h>
#include "common.hpp"

/* __global__: ���������޶���;���豸������;�������˵���,��������3.2�����Ͽ�����
�豸�˵���;�����ĺ����ķ���ֵ������void����;�Դ����ͺ����ĵ������첽��,����
�豸��ȫ�����������֮ǰ�ͷ�����;�Դ����ͺ����ĵ��ñ���ָ��ִ������,��������
�豸��ִ�к���ʱ��grid��block��ά��,�Լ���ص���(������<<<   >>>�����);
a kernel,��ʾ�˺���Ϊ�ں˺���(������GPU�ϵ�CUDA���м��㺯����Ϊkernel(�ں˺�
��),�ں˺�������ͨ��__global__���������޶�������); */
__global__ static void calculate_histogram(const unsigned char* data, int length, unsigned int* hist)
{
	/* __shared__: ���������޶�����ʹ��__shared__�޶�����������__device__��
	�������ã���ʱ�����ı���λ��block�еĹ���洢���ռ��У���block������ͬ
	���������ڣ�����ͨ��block�ڵ������̷߳��ʣ�__shared__��__constant__����
	Ĭ��Ϊ�Ǿ�̬�洢����__shared__ǰ���Լ�extern�ؼ��֣�����ʾ���Ǳ�����С
	��ִ�в���ȷ����__shared__����������ʱ���ܳ�ʼ�������Խ�CUDA C�Ĺؼ���
	__shared__��ӵ����������У��⽫ʹ�������פ���ڹ����ڴ��У�CUDA C����
	���Թ����ڴ��еı�������ͨ�������ֱ��ȡ��ͬ�Ĵ���ʽ */
	// clear out the accumulation buffer called temp since we are launched with
	// 256 threads, it is easy to clear that memory with one write per thread
	__shared__  unsigned int temp[256]; // �����ڴ滺����
	temp[threadIdx.x] = 0;
	/* __syncthreads: ���߳̿��е��߳̽���ͬ����CUDA�ܹ���ȷ���������߳̿�
	�е�ÿ���̶߳�ִ����__syncthreads()������û���κ��߳���ִ��
	__syncthreads()֮���ָ��;��ͬһ��block�е��߳�ͨ������洢��(shared
	memory)�������ݣ���ͨ��դ��ͬ��(������kernel��������Ҫͬ����λ�õ���
	__syncthreads()����)��֤�̼߳��ܹ���ȷ�ع������ݣ�ʹ��clock()������ʱ��
	���ں˺�����Ҫ������һ�δ���Ŀ�ʼ�ͽ�����λ�÷ֱ����һ��clock()������
	���������¼���������ڵ���__syncthreads()������һ��block�е�����
	thread��Ҫ��ʱ������ͬ�ģ����ֻ��Ҫ��¼ÿ��blockִ����Ҫ��ʱ������ˣ�
	������Ҫ��¼ÿ��thread��ʱ�� */
	__syncthreads();

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
	// calculate the starting index and the offset to the next block that each thread will be processing
	int i = threadIdx.x + blockIdx.x * blockDim.x;
	int stride = blockDim.x * gridDim.x;
	while (i < length) {
		/* atomicAdd: ԭ�Ӳ���,�ײ�Ӳ����ȷ����ִ����Щԭ�Ӳ���ʱ����
		���κ��̶߳������ȡ��д���ַaddr�ϵ�ֵ��ԭ�Ӻ���(atomic
		function)��λ��ȫ�ֻ���洢����һ��32λ��64λ��ִ��
		read-modify-write��ԭ�Ӳ�����Ҳ����˵��������߳�ͬʱ����ȫ�ֻ�
		����洢����ͬһλ��ʱ����֤ÿ���߳��ܹ�ʵ�ֶԹ����д���ݵĻ�
		���������һ���������֮ǰ�������κ��̶߳��޷����ʴ˵�ַ��֮��
		�Խ���һ���̳�Ϊԭ�Ӳ���������Ϊÿ���̵߳Ĳ���������Ӱ�쵽����
		�̡߳����仰˵��ԭ�Ӳ����ܹ���֤��һ����ַ�ĵ�ǰ�������֮ǰ��
		�����̶߳����ܷ��������ַ��
		atomicAdd(addr,y)��������һ��ԭ�ӵĲ������У�����������а�����
		ȡ��ַaddr����ֵ����y���ӵ����ֵ���Լ����������ص�ַaddr�� */
		atomicAdd(&temp[data[i]], 1);
		i += stride;
	}

	// sync the data from the above writes to shared memory then add the shared memory values to the values from
	// the other thread blocks using global memory atomic adds same as before, since we have 256 threads,
	// updating the global histogram is just one write per thread!
	__syncthreads();
	// ��ÿ���߳̿��ֱ��ͼ�ϲ�Ϊ�������յ�ֱ��ͼ
	atomicAdd(&(hist[threadIdx.x]), temp[threadIdx.x]);
}

int calculate_histogram_gpu(const unsigned char* data, int length, unsigned int* hist, unsigned int& value, float* elapsed_time)
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

	unsigned char* dev_buffer{ nullptr };
	unsigned int* dev_hist{ nullptr };

	// cudaMalloc: ���豸�˷����ڴ�
	cudaMalloc(&dev_buffer, length);
	cudaMalloc(&dev_hist, 256 * sizeof(unsigned int));

	/* cudaMemcpy: �������˺��豸�˿�������,�˺������ĸ���������������֮һ:
	(1). cudaMemcpyHostToHost: �������ݴ������˵�������
	(2). cudaMemcpyHostToDevice: �������ݴ������˵��豸��
	(3). cudaMemcpyDeviceToHost: �������ݴ��豸�˵�������
	(4). cudaMemcpyDeviceToDevice: �������ݴ��豸�˵��豸��
	(5). cudaMemcpyDefault: ��ָ��ֵ�Զ��ƶϿ������ݷ���,��Ҫ֧��
	ͳһ����Ѱַ(CUDA6.0�����ϰ汾)
	cudaMemcpy��������������ͬ���� */
	cudaMemcpy(dev_buffer, data, length, cudaMemcpyHostToDevice);

	/* cudaMemset: �洢����ʼ������,��GPU�ڴ���ִ�С���ָ����ֵ��ʼ��������
	�豸�ڴ� */
	cudaMemset(dev_hist, 0, 256 * sizeof(unsigned int));

	// cudaDeviceProp: cuda�豸���Խṹ��
	// kernel launch - 2x the number of mps gave best timing
	cudaDeviceProp prop;
	// cudaGetDeviceProperties: ��ȡGPU�豸�����Ϣ
	cudaGetDeviceProperties(&prop, 0);
	// cudaDeviceProp::multiProcessorCount: �豸�϶ദ����������
	int blocks = prop.multiProcessorCount;
	fprintf(stderr, "multiProcessorCount: %d\n", blocks);

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
	block�н���Db.x*Db.y*Db.z��thread;Ns��һ��unsigned int�ͱ���,ָ������Ϊ�˵�
	�ö�̬����Ĺ���洢����С,��Щ��̬����Ĵ洢���ɹ�����Ϊ�ⲿ����
	(extern __shared__)�������κα���ʹ��;Ns��һ����ѡ����,Ĭ��ֵΪ0;SΪ
	cudaStream_t����,�����������ں˺�����������.S��һ����ѡ����,Ĭ��ֵ0. */
	// ���߳̿������ΪGPU�д�����������2��ʱ�����ﵽ��������
	calculate_histogram << <blocks * 2, 256 >> >(dev_buffer, length, dev_hist);

	cudaMemcpy(hist, dev_hist, 256 * sizeof(unsigned int), cudaMemcpyDeviceToHost);

	value = 0;
	for (int i = 0; i < 256; ++i) {
		value += hist[i];
	}

	// cudaFree: �ͷ��豸����cudaMalloc����������ڴ�
	cudaFree(dev_buffer);
	cudaFree(dev_hist);

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
