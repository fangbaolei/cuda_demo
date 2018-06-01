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
__global__ static void copy_const_kernel(float* iptr, const float* cptr)
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
	// map from threadIdx/BlockIdx to pixel position
	int x = threadIdx.x + blockIdx.x * blockDim.x;
	int y = threadIdx.y + blockIdx.y * blockDim.y;
	int offset = x + y * blockDim.x * gridDim.x;

	if (cptr[offset] != 0) iptr[offset] = cptr[offset];
}

__global__ static void blend_kernel(float* outSrc, const float* inSrc, int width, int height, float speed)
{
	// map from threadIdx/BlockIdx to pixel position
	int x = threadIdx.x + blockIdx.x * blockDim.x;
	int y = threadIdx.y + blockIdx.y * blockDim.y;
	int offset = x + y * blockDim.x * gridDim.x;

	int left = offset - 1;
	int right = offset + 1;
	if (x == 0) ++left;
	if (x == width - 1) --right;

	int top = offset - height;
	int bottom = offset + height;
	if (y == 0) top += height;
	if (y == height - 1) bottom -= height;

	outSrc[offset] = inSrc[offset] + speed * (inSrc[top] + inSrc[bottom] + inSrc[left] + inSrc[right] - inSrc[offset] * 4);
}

/* __device__: ���������޶���,���������εĺ������豸��ִ�У�ֻ�ܴ��豸�ϵ��ã�
��ֻ��������__device__��������__global__�����е��ã�__device__������֧�ֵݹ飻
__device__�����ĺ������ڲ���������̬������__device__�����Ĳ�����Ŀ�ǲ��ɱ仯��;
���ܶ�__device__����ȡָ�� */
__device__ static unsigned char value(float n1, float n2, int hue)
{
	if (hue > 360) hue -= 360;
	else if (hue < 0) hue += 360;

	if (hue < 60)
		return (unsigned char)(255 * (n1 + (n2 - n1)*hue / 60));
	if (hue < 180)
		return (unsigned char)(255 * n2);
	if (hue < 240)
		return (unsigned char)(255 * (n1 + (n2 - n1)*(240 - hue) / 60));
	return (unsigned char)(255 * n1);
}

__global__ static void float_to_color(unsigned char *optr, const float *outSrc)
{
	// map from threadIdx/BlockIdx to pixel position
	int x = threadIdx.x + blockIdx.x * blockDim.x;
	int y = threadIdx.y + blockIdx.y * blockDim.y;
	int offset = x + y * blockDim.x * gridDim.x;

	float l = outSrc[offset];
	float s = 1;
	int h = (180 + (int)(360.0f * outSrc[offset])) % 360;
	float m1, m2;

	if (l <= 0.5f) m2 = l * (1 + s);
	else m2 = l + s - l * s;
	m1 = 2 * l - m2;

	optr[offset * 4 + 0] = value(m1, m2, h + 120);
	optr[offset * 4 + 1] = value(m1, m2, h);
	optr[offset * 4 + 2] = value(m1, m2, h - 120);
	optr[offset * 4 + 3] = 255;
}

static int heat_conduction_gpu_1(unsigned char* ptr, int width, int height, const float* src, float speed, float* elapsed_time)
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

	float* dev_inSrc{ nullptr };
	float* dev_outSrc{ nullptr };
	float* dev_constSrc{ nullptr };
	unsigned char* dev_image{ nullptr };
	const size_t length1{ width * height * sizeof(float) };
	const size_t length2{ width * height * 4 * sizeof(unsigned char) };

	// cudaMalloc: ���豸�˷����ڴ�
	cudaMalloc(&dev_inSrc, length1);
	cudaMalloc(&dev_outSrc, length1);
	cudaMalloc(&dev_constSrc, length1);
	cudaMalloc(&dev_image, length2);

	/* cudaMemcpy: �������˺��豸�˿�������,�˺������ĸ���������������֮һ:
	(1). cudaMemcpyHostToHost: �������ݴ������˵�������
	(2). cudaMemcpyHostToDevice: �������ݴ������˵��豸��
	(3). cudaMemcpyDeviceToHost: �������ݴ��豸�˵�������
	(4). cudaMemcpyDeviceToDevice: �������ݴ��豸�˵��豸��
	(5). cudaMemcpyDefault: ��ָ��ֵ�Զ��ƶϿ������ݷ���,��Ҫ֧��
	ͳһ����Ѱַ(CUDA6.0�����ϰ汾)
	cudaMemcpy��������������ͬ���� */
	cudaMemcpy(dev_constSrc, src, length1, cudaMemcpyHostToDevice);

	const int threads_block{ 16 };
	/* dim3: ����uint3���������ʸ�����ͣ��൱����3��unsigned int������ɵ�
	�ṹ�壬�ɱ�ʾһ����ά���飬�ڶ���dim3���ͱ���ʱ������û�и�ֵ��Ԫ�ض�
	�ᱻ����Ĭ��ֵ1 */
	dim3 blocks(width / threads_block, height / threads_block);
	dim3 threads(threads_block, threads_block);

	for (int i = 0; i < 90; ++i) {
		copy_const_kernel << <blocks, threads >> >(dev_inSrc, dev_constSrc);
		blend_kernel << <blocks, threads >> >(dev_outSrc, dev_inSrc, width, height, speed);
		std::swap(dev_inSrc, dev_outSrc);
	}

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
	float_to_color << <blocks, threads >> >(dev_image, dev_inSrc);

	cudaMemcpy(ptr, dev_image, length2, cudaMemcpyDeviceToHost);

	// cudaFree: �ͷ��豸����cudaMalloc����������ڴ�
	cudaFree(dev_inSrc);
	cudaFree(dev_outSrc);
	cudaFree(dev_constSrc);
	cudaFree(dev_image);

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

static int heat_conduction_gpu_2(unsigned char* ptr, int width, int height, const float* src, float speed, float* elapsed_time)
{
	return 0;
}

static int heat_conduction_gpu_3(unsigned char* ptr, int width, int height, const float* src, float speed, float* elapsed_time)
{
	return 0;
}

int heat_conduction_gpu(unsigned char* ptr, int width, int height, const float* src, float speed, float* elapsed_time)
{
	int ret{ 0 };
	ret = heat_conduction_gpu_1(ptr, width, height, src, speed, elapsed_time); // û�в��������ڴ�
	//ret = heat_conduction_gpu_2(ptr, width, height, src, speed, elapsed_time); // ����һά�����ڴ�
	//ret = heat_conduction_gpu_3(ptr, width, height, src, speed, elapsed_time); // ���ö�ά�����ڴ�

	return ret;
}
