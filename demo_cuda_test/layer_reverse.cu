#include "funset.hpp"
#include <iostream>
#include <cuda_runtime.h> // For the CUDA runtime routines (prefixed with "cuda_")
#include <device_launch_parameters.h>
#include "common.hpp"

/* __device__: ���������޶���,���������εĺ������豸��ִ�У�ֻ�ܴ��豸�ϵ��ã�
��ֻ��������__device__��������__global__�����е��ã�__device__������֧�ֵݹ飻
__device__�����ĺ������ڲ���������̬������__device__�����Ĳ�����Ŀ�ǲ��ɱ仯��;
���ܶ�__device__����ȡָ�� */
__device__ static int min_(int a, int b)
{
	return a > b ? b : a;
}

__device__ static int max_(int a, int b)
{
	return a > b ? a : b;
}

/* __global__: ���������޶���;���豸������;�������˵���,��������3.2�����Ͽ�����
�豸�˵���;�����ĺ����ķ���ֵ������void����;�Դ����ͺ����ĵ������첽��,����
�豸��ȫ�����������֮ǰ�ͷ�����;�Դ����ͺ����ĵ��ñ���ָ��ִ������,��������
�豸��ִ�к���ʱ��grid��block��ά��,�Լ���ص���(������<<<   >>>�����);
a kernel,��ʾ�˺���Ϊ�ں˺���(������GPU�ϵ�CUDA���м��㺯����Ϊkernel(�ں˺�
��),�ں˺�������ͨ��__global__���������޶�������);*/
__global__ static void layer_reverse(const float* src, float* dst, int length, int vec0, int vec1)
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
	auto index = threadIdx.x + blockIdx.x * blockDim.x;

	while (index < length) {
		auto index1 = (index / vec0) % vec1;
		auto index2 = vec0 * (vec1 - 2 * index1 - 1) + index;
		index2 = max_(0, min_(length - 1, index2));
		dst[index2] = src[index];

		index += blockDim.x * gridDim.x;
	}
}

int layer_reverse_gpu(const float* src, float* dst, int length, const std::vector<int>& vec, float* elapsed_time)
{
	/* cudaEvent_t: CUDA event types,�ṹ������, CUDA�¼�,���ڲ���GPU��ĳ
	�������ϻ��ѵ�ʱ��,CUDA�е��¼���������һ��GPUʱ���,����CUDA�¼�����
	GPU��ʵ�ֵ�,������ǲ����ڶ�ͬʱ�����豸�������������Ļ�ϴ����ʱ*/
	cudaEvent_t start, stop;
	// cudaEventCreate: ����һ���¼�����,�첽����
	cudaEventCreate(&start);
	cudaEventCreate(&stop);
	// cudaEventRecord: ��¼һ���¼�,�첽����,start��¼��ʼʱ��
	cudaEventRecord(start, 0);

	float *d_src{ nullptr }, *d_dst{ nullptr };

	// cudaMalloc: ���豸�˷����ڴ�
	cudaMalloc(&d_src, length * sizeof(float));
	cudaMalloc(&d_dst, length * sizeof(float));

	/* cudaMemcpy: �������˺��豸�˿�������,�˺������ĸ���������������֮һ:
	(1). cudaMemcpyHostToHost: �������ݴ������˵�������
	(2). cudaMemcpyHostToDevice: �������ݴ������˵��豸��
	(3). cudaMemcpyDeviceToHost: �������ݴ��豸�˵�������
	(4). cudaMemcpyDeviceToDevice: �������ݴ��豸�˵��豸��
	(5). cudaMemcpyDefault: ��ָ��ֵ�Զ��ƶϿ������ݷ���,��Ҫ֧��
	ͳһ����Ѱַ(CUDA6.0�����ϰ汾)
	cudaMemcpy��������������ͬ���� */
	cudaMemcpy(d_src, src, length * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(d_dst, dst, length * sizeof(float), cudaMemcpyHostToDevice);

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
	layer_reverse << <512, 512 >> >(d_src, d_dst, length, vec[0], vec[1]);

	cudaMemcpy(dst, d_dst, length * sizeof(float), cudaMemcpyDeviceToHost);

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
