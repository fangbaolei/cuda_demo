#include "funset.hpp"
#include <iostream>
#include <memory>
#include <algorithm>
#include <cmath>
#include <cuda_runtime.h> // For the CUDA runtime routines (prefixed with "cuda_")
#include <device_launch_parameters.h>
#include "common.hpp"

/* __global__: ���������޶���;���豸������;�������˵���,��������3.2�����Ͽ�����
�豸�˵���;�����ĺ����ķ���ֵ������void����;�Դ����ͺ����ĵ������첽��,����
�豸��ȫ�����������֮ǰ�ͷ�����;�Դ����ͺ����ĵ��ñ���ָ��ִ������,��������
�豸��ִ�к���ʱ��grid��block��ά��,�Լ���ص���(������<<<   >>>�����);
a kernel,��ʾ�˺���Ϊ�ں˺���(������GPU�ϵ�CUDA���м��㺯����Ϊkernel(�ں˺�
��),�ں˺�������ͨ��__global__���������޶�������);*/
__global__ static void layer_prior_vbox(float* dst, int layer_width, int layer_height, int image_width, int image_height,
	float offset, float step, int num_priors, float width, const float* height, const float* variance, int channel_size)
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

	if (x < layer_width && y < layer_height) {
		float center_x = (x + offset) * step;
		float center_y = (y + offset) * step;
		int idx = x * num_priors * 4 + y * (layer_width * num_priors * 4);

		for (int s = 0; s < num_priors; ++s) {
			float box_width = width;
			float box_height = height[s];
			int idx1 = idx + s * 4;

			dst[idx1] = (center_x - box_width / 2.) / image_width;
			dst[idx1 + 1] = (center_y - box_height / 2.) / image_height;
			dst[idx1 + 2] = (center_x + box_width / 2.) / image_width;
			dst[idx1 + 3] = (center_y + box_height / 2.) / image_height;

			int idx2 = channel_size + idx + s * 4;
			dst[idx2] = variance[0];
			dst[idx2 + 1] = variance[1];
			dst[idx2 + 2] = variance[2];
			dst[idx2 + 3] = variance[3];
		}
	}
}

int layer_prior_vbox_gpu(float* dst, int length, const std::vector<float>& vec1, const std::vector<float>& vec2,
	const std::vector<float>& vec3, float* elapsed_time)
{
	float *dev_dst{ nullptr }, *dev_vec;
	// cudaMalloc: ���豸�˷����ڴ�
	cudaMalloc(&dev_dst, length * sizeof(float));
	cudaMalloc(&dev_vec, (vec2.size()+vec3.size()) * sizeof(float));
	/* cudaMemcpy: �������˺��豸�˿�������,�˺������ĸ���������������֮һ:
	(1). cudaMemcpyHostToHost: �������ݴ������˵�������
	(2). cudaMemcpyHostToDevice: �������ݴ������˵��豸��
	(3). cudaMemcpyDeviceToHost: �������ݴ��豸�˵�������
	(4). cudaMemcpyDeviceToDevice: �������ݴ��豸�˵��豸��
	(5). cudaMemcpyDefault: ��ָ��ֵ�Զ��ƶϿ������ݷ���,��Ҫ֧��
	ͳһ����Ѱַ(CUDA6.0�����ϰ汾)
	cudaMemcpy��������������ͬ���� */
	cudaMemcpy(dev_dst, dst, length * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dev_vec, vec2.data(), vec2.size() * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dev_vec + vec2.size(), vec3.data(), vec3.size() * sizeof(float), cudaMemcpyHostToDevice);

	int layer_width = (int)vec1[0];
	int layer_height = (int)vec1[1];
	int image_width = (int)vec1[2];
	int image_height = (int)vec1[3];
	float offset = vec1[4];
	float step = vec1[5];
	int num_priors = (int)vec1[6];
	float width = vec1[7];
	int channel_size = layer_width * layer_height * num_priors * 4;

	TIME_START_GPU

	/* dim3: ����uint3���������ʸ�����ͣ��൱����3��unsigned int������ɵ�
	�ṹ�壬�ɱ�ʾһ����ά���飬�ڶ���dim3���ͱ���ʱ������û�и�ֵ��Ԫ�ض�
	�ᱻ����Ĭ��ֵ1 */
	// Note��ÿһ���߳̿�֧�ֵ�����߳�����Ϊ1024����threads.x*threads.y����С�ڵ���1024
	dim3 threads(32, 32);
	dim3 blocks((layer_width + 31) / 32, (layer_height + 31) / 32);

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
	layer_prior_vbox << <blocks, threads>> >(dev_dst, layer_width, layer_height, image_width, image_height,
		offset, step, num_priors, width, dev_vec, dev_vec + vec2.size(), channel_size);

	/* cudaDeviceSynchronize: kernel���������첽��, Ϊ�˶�λ���Ƿ����, һ
	����Ҫ����cudaDeviceSynchronize��������ͬ��; ����һֱ��������״̬,ֱ��
	ǰ����������������Ѿ���ȫ��ִ�����,���ǰ��ִ�е�ĳ������ʧ��,����
	����һ�����󣻵��������ж����,������֮����ĳһ����Ҫͨ��ʱ,�Ǿͱ���
	����һ�㴦����ͬ�������,��cudaDeviceSynchronize���첽����
	reference: https://stackoverflow.com/questions/11888772/when-to-call-cudadevicesynchronize */
	cudaDeviceSynchronize();

	TIME_END_GPU

	cudaMemcpy(dst, dev_dst, length * sizeof(float), cudaMemcpyDeviceToHost);

	// cudaFree: �ͷ��豸����cudaMalloc����������ڴ�
	cudaFree(dev_dst);
	cudaFree(dev_vec);

	return 0;
}
