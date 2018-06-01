#include "funset.hpp"
#include <iostream>
#include <chrono>
#include <cuda_runtime.h>
#include <device_launch_parameters.h>
#include "common.hpp"

/* __global__: ���������޶���;���豸������;�������˵���,��������3.2�����Ͽ�����
�豸�˵���;�����ĺ����ķ���ֵ������void����;�Դ����ͺ����ĵ������첽��,����
�豸��ȫ�����������֮ǰ�ͷ�����;�Դ����ͺ����ĵ��ñ���ָ��ִ������,��������
�豸��ִ�к���ʱ��grid��block��ά��,�Լ���ص���(������<<<   >>>�����);
a kernel,��ʾ�˺���Ϊ�ں˺���(������GPU�ϵ�CUDA���м��㺯����Ϊkernel(�ں˺�
��),�ں˺�������ͨ��__global__���������޶�������);*/
__global__ static void bgr2gray(const unsigned char* src, int B2Y, int G2Y, int R2Y, int shift, int width, int height, unsigned char* dst)
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
	int x = threadIdx.x + blockIdx.x * blockDim.x;
	int y = threadIdx.y + blockIdx.y * blockDim.y;

	//if (x == 0 && y == 0) {
	//	printf("%d, %d, %d, %d, %d, %d\n", width, height, B2Y, G2Y, R2Y, shift);
	//}

	if (x < width && y < height) {
		dst[y * width + x] = (unsigned char)((src[y*width * 3 + 3 * x + 0] * B2Y +
			src[y*width * 3 + 3 * x + 1] * G2Y + src[y*width * 3 + 3 * x + 2] * R2Y) >> shift);
	}
}

int bgr2gray_gpu(const unsigned char* src, int width, int height, unsigned char* dst, float* elapsed_time)
{
	const int R2Y{ 4899 }, G2Y{ 9617 }, B2Y{ 1868 }, yuv_shift{ 14 };
	unsigned char *dev_src{ nullptr }, *dev_dst{ nullptr };
	// cudaMalloc: ���豸�˷����ڴ�
	cudaMalloc(&dev_src, width * height * 3 * sizeof(unsigned char));
	cudaMalloc(&dev_dst, width * height * sizeof(unsigned char));
	/* cudaMemcpy: �������˺��豸�˿�������,�˺������ĸ���������������֮һ:
	(1). cudaMemcpyHostToHost: �������ݴ������˵�������
	(2). cudaMemcpyHostToDevice: �������ݴ������˵��豸��
	(3). cudaMemcpyDeviceToHost: �������ݴ��豸�˵�������
	(4). cudaMemcpyDeviceToDevice: �������ݴ��豸�˵��豸��
	(5). cudaMemcpyDefault: ��ָ��ֵ�Զ��ƶϿ������ݷ���,��Ҫ֧��
	ͳһ����Ѱַ(CUDA6.0�����ϰ汾)
	cudaMemcpy��������������ͬ���� */
	cudaMemcpy(dev_src, src, width * height * 3 * sizeof(unsigned char), cudaMemcpyHostToDevice);
	/* cudaMemset: �洢����ʼ������,��GPU�ڴ���ִ�С���ָ����ֵ��ʼ��������
	�豸�ڴ� */
	cudaMemset(dev_dst, 0, width * height * sizeof(unsigned char));

	TIME_START_GPU

	/* dim3: ����uint3���������ʸ�����ͣ��൱����3��unsigned int������ɵ�
	�ṹ�壬�ɱ�ʾһ����ά���飬�ڶ���dim3���ͱ���ʱ������û�и�ֵ��Ԫ�ض�
	�ᱻ����Ĭ��ֵ1 */
	// Note��ÿһ���߳̿�֧�ֵ�����߳�����Ϊ1024����threads.x*threads.y����С�ڵ���1024
	dim3 threads(32, 32);
	dim3 blocks((width + 31) / 32, (height + 31) / 32);

	/* <<< >>>: ΪCUDA����������,ָ���߳�������߳̿�ά�ȵ�,����ִ�в�
	����CUDA������������ʱϵͳ,����˵���ں˺����е��߳�����,�Լ��߳������
	��֯��;����������Щ���������Ǵ��ݸ��豸����Ĳ���,���Ǹ�������ʱ���
	�����豸����,���ݸ��豸���뱾��Ĳ����Ƿ���Բ�����д��ݵ�,�����׼�ĺ�
	������һ��;��ͬ�����������豸���̵߳���������֯��ʽ�в�ͬ��Լ��;����
	��Ϊkernel���õ�����������������㹻�Ŀռ�,�ٵ���kernel����,������
	GPU����ʱ�ᷢ������,����Խ��� ;
	ʹ������ʱAPIʱ,��Ҫ�ڵ��õ��ں˺�����������б�ֱ����<<<Dg,Db,Ns,S>>>
	����ʽ����ִ������,���У�Dg��һ��dim3�ͱ���,��������grid��ά�Ⱥ͸���
	ά���ϵĳߴ�.���ú�Dg��,grid�н���Dg.x*Dg.y*Dg.z��block;Db��
	һ��dim3�ͱ���,��������block��ά�Ⱥ͸���ά���ϵĳߴ�.���ú�Db��,ÿ��
	block�н���Db.x*Db.y*Db.z��thread;Ns��һ��size_t�ͱ���,ָ������Ϊ�˵�
	�ö�̬����Ĺ���洢����С,��Щ��̬����Ĵ洢���ɹ�����Ϊ�ⲿ����
	(extern __shared__)�������κα���ʹ��;Ns��һ����ѡ����,Ĭ��ֵΪ0;SΪ
	cudaStream_t����,�����������ں˺�����������.S��һ����ѡ����,Ĭ��ֵ0. */
	// Note: �˺�����֧�ִ������Ϊvector��data()ָ�룬��ҪcudaMalloc��cudaMemcpy����Ϊvector���������ڴ���
	bgr2gray << <blocks, threads >> >(dev_src, B2Y, G2Y, R2Y, yuv_shift, width, height, dev_dst);

	/* cudaDeviceSynchronize: kernel���������첽��, Ϊ�˶�λ���Ƿ����, һ
	����Ҫ����cudaDeviceSynchronize��������ͬ��; ����һֱ��������״̬,ֱ��
	ǰ����������������Ѿ���ȫ��ִ�����,���ǰ��ִ�е�ĳ������ʧ��,����
	����һ�����󣻵��������ж����,������֮����ĳһ����Ҫͨ��ʱ,�Ǿͱ���
	����һ�㴦����ͬ�������,��cudaDeviceSynchronize���첽����
	reference: https://stackoverflow.com/questions/11888772/when-to-call-cudadevicesynchronize */
	cudaDeviceSynchronize();

	TIME_END_GPU

	cudaMemcpy(dst, dev_dst, width * height * sizeof(unsigned char), cudaMemcpyDeviceToHost);

	// cudaFree: �ͷ��豸����cudaMalloc����������ڴ�
	cudaFree(dev_dst);
	cudaFree(dev_src);

	return 0;
}
