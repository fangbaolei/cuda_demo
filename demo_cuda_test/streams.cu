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
__global__ static void stream_kernel(int* a, int* b, int* c, int length)
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
	int idx = threadIdx.x + blockIdx.x * blockDim.x;
	if (idx < length) {
		int idx1 = (idx + 1) % 256;
		int idx2 = (idx + 2) % 256;
		float as = (a[idx] + a[idx1] + a[idx2]) / 3.0f;
		float bs = (b[idx] + b[idx1] + b[idx2]) / 3.0f;
		c[idx] = (as + bs) / 2;
	}
}

int streams_gpu_1(const int* a, const int* b, int* c, int length, float* elapsed_time)
{
	// cudaDeviceProp: cuda�豸���Խṹ��
	cudaDeviceProp prop;
	// cudaGetDeviceProperties: ��ȡGPU�豸�����Ϣ
	cudaGetDeviceProperties(&prop, 0);
	/* cudaDeviceProp::deviceOverlap: GPU�Ƿ�֧���豸�ص�(Device Overlap)��
	��,֧���豸�ص����ܵ�GPU�ܹ���ִ��һ��CUDA C�˺�����ͬʱ���������豸��
	����֮��ִ�и��ƵȲ��� */
	if (!prop.deviceOverlap) {
		printf("Device will not handle overlaps, so no speed up from streams\n");
		return -1;
	}

	/* cudaEvent_t: CUDA event types,�ṹ������, CUDA�¼�,���ڲ���GPU��ĳ
	�������ϻ��ѵ�ʱ��,CUDA�е��¼���������һ��GPUʱ���,����CUDA�¼�����
	GPU��ʵ�ֵ�,������ǲ����ڶ�ͬʱ�����豸�������������Ļ�ϴ����ʱ */
	cudaEvent_t start, stop;
	// cudaEventCreate: ����һ���¼�����,�첽����
	cudaEventCreate(&start);
	cudaEventCreate(&stop);
	// cudaEventRecord: ��¼һ���¼�,�첽����,start��¼��ʼʱ��
	cudaEventRecord(start, 0);

	/* cudaStream_t: cuda �����ṹ������, CUDA����ʾһ��GPU�������У����Ҹ�
	�����еĲ�������ָ����˳��ִ�С����Խ�ÿ������ΪGPU�ϵ�һ�����񣬲�����
	Щ������Բ���ִ�С� */
	cudaStream_t stream;
	// cudaStreamCreate: ��ʼ����������һ���µ��첽��
	cudaStreamCreate(&stream);

	int *host_a{ nullptr }, *host_b{ nullptr }, *host_c{ nullptr };
	int *dev_a{ nullptr }, *dev_b{ nullptr }, *dev_c{ nullptr };
	const int N{ length / 20 };

	// cudaMalloc: ���豸�˷����ڴ�
	cudaMalloc(&dev_a, N * sizeof(int));
	cudaMalloc(&dev_b, N * sizeof(int));
	cudaMalloc(&dev_c, N * sizeof(int));
	/* cudaHostAlloc: ���������ڴ�(�̶��ڴ�)��C�⺯��malloc�������׼�ģ���
	��ҳ��(Pagable)�����ڴ棬��cudaHostAlloc������ҳ�����������ڴ档ҳ������
	��Ҳ��Ϊ�̶��ڴ�(Pinned Memory)���߲��ɷ�ҳ�ڴ棬����һ����Ҫ�����ԣ�����ϵ
	ͳ�����������ڴ��ҳ�������������ϣ��Ӷ�ȷ���˸��ڴ�ʼ��פ����������
	���С���ˣ�����ϵͳ�ܹ���ȫ��ʹĳ��Ӧ�ó�����ʸ��ڴ�������ַ����Ϊ
	����ڴ潫���ᱻ�ƻ��������¶�λ������GPU֪���ڴ�������ַ����˿���ͨ
	��"ֱ���ڴ����(Direct Memory Access, DMA)"��������GPU������֮�临�����ݡ�
	�̶��ڴ���һ��˫�н�����ʹ�ù̶��ڴ�ʱ���㽫ʧȥ�����ڴ�����й��ܡ�
	���飺����cudaMemcpy�����е�Դ�ڴ����Ŀ���ڴ棬��ʹ��ҳ�����ڴ棬������
	������Ҫʹ������ʱ�����ͷš� */
	// ��������ʹ�õ�ҳ�����ڴ�
	cudaHostAlloc(&host_a, length * sizeof(int), cudaHostAllocDefault);
	cudaHostAlloc(&host_b, length * sizeof(int), cudaHostAllocDefault);
	cudaHostAlloc(&host_c, length * sizeof(int), cudaHostAllocDefault);

	//for (int i = 0; i < length; ++i) {
	//	host_a[i] = a[i];
	//	host_b[i] = b[i];
	//}
	memcpy(host_a, a, length * sizeof(int));
	memcpy(host_b, b, length * sizeof(int));

	for (int i = 0; i < length; i += N) {
		/* cudaMemcpyAsync: ��GPU������֮�临�����ݡ�cudaMemcpy����Ϊ��
		����C�⺯��memcpy�������ǣ������������ͬ����ʽִ�У�����ζ�ţ�
		����������ʱ�����Ʋ������Ѿ���ɣ�����������������а����˸���
		��ȥ�����ݡ��첽��������Ϊ��ͬ�������෴���ڵ���cudaMemcpyAsyncʱ��
		ֻ�Ƿ�����һ�����󣬱�ʾ������ִ��һ���ڴ渴�Ʋ������������ͨ��
		����stream��ָ���ġ�����������ʱ�������޷�ȷ�����Ʋ����Ƿ��Ѿ�
		���������޷���֤�����Ƿ��Ѿ������������ܹ��õ��ı�֤�ǣ����Ʋ����϶�
		�ᵱ��һ�����������еĲ���֮ǰִ�С��κδ��ݸ�cudaMemcpyAsync������
		�ڴ�ָ�붼�����Ѿ�ͨ��cudaHostAlloc������ڴ档Ҳ���ǣ���ֻ�����첽
		��ʽ��ҳ�����ڴ���и��Ʋ��� */
		// �������ڴ����첽��ʽ���Ƶ��豸��
		cudaMemcpyAsync(dev_a, host_a + i, N * sizeof(int), cudaMemcpyHostToDevice, stream);
		cudaMemcpyAsync(dev_b, host_b + i, N * sizeof(int), cudaMemcpyHostToDevice, stream);

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
		stream_kernel << <N / 256, 256, 0, stream >> >(dev_a, dev_b, dev_c, N);

		cudaMemcpyAsync(host_c + i, dev_c, N * sizeof(int), cudaMemcpyDeviceToHost, stream);
	}

	/* cudaStreamSynchronize: �ȴ��������еĲ�����ɣ������ڼ���ִ��֮ǰ��Ҫ
	�ȴ�GPUִ����� */
	cudaStreamSynchronize(stream);

	//for (int i = 0; i < length; ++i)
	//	c[i] = host_c[i];
	memcpy(c, host_c, length * sizeof(int));

	// cudaFreeHost: �ͷ��豸����cudaHostAlloc����������ڴ�
	cudaFreeHost(host_a);
	cudaFreeHost(host_b);
	cudaFreeHost(host_c);
	// cudaFree: �ͷ��豸����cudaMalloc����������ڴ�
	cudaFree(dev_a);
	cudaFree(dev_b);
	cudaFree(dev_c);
	// cudaStreamDestroy: ������
	cudaStreamDestroy(stream);

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

int streams_gpu_2(const int* a, const int* b, int* c, int length, float* elapsed_time)
{
	cudaDeviceProp prop;
	cudaGetDeviceProperties(&prop, 0);
	if (!prop.deviceOverlap) {
		printf("Device will not handle overlaps, so no speed up from streams\n");
		return -1;
	}

	cudaEvent_t start, stop;
	cudaEventCreate(&start);
	cudaEventCreate(&stop);
	cudaEventRecord(start, 0);

	cudaStream_t stream0, stream1;
	cudaStreamCreate(&stream0);
	cudaStreamCreate(&stream1);

	int *host_a{ nullptr }, *host_b{ nullptr }, *host_c{ nullptr };
	int *dev_a0{ nullptr }, *dev_b0{ nullptr }, *dev_c0{ nullptr };
	int *dev_a1{ nullptr }, *dev_b1{ nullptr }, *dev_c1{ nullptr };
	const int N{ length / 20 };

	cudaMalloc(&dev_a0, N * sizeof(int));
	cudaMalloc(&dev_b0, N * sizeof(int));
	cudaMalloc(&dev_c0, N * sizeof(int));
	cudaMalloc(&dev_a1, N * sizeof(int));
	cudaMalloc(&dev_b1, N * sizeof(int));
	cudaMalloc(&dev_c1, N * sizeof(int));
	cudaHostAlloc(&host_a, length * sizeof(int), cudaHostAllocDefault);
	cudaHostAlloc(&host_b, length * sizeof(int), cudaHostAllocDefault);
	cudaHostAlloc(&host_c, length * sizeof(int), cudaHostAllocDefault);

	memcpy(host_a, a, length * sizeof(int));
	memcpy(host_b, b, length * sizeof(int));

	for (int i = 0; i < length; i += N * 2) {
		//cudaMemcpyAsync(dev_a0, host_a + i, N * sizeof(int), cudaMemcpyHostToDevice, stream0);
		//cudaMemcpyAsync(dev_b0, host_b + i, N * sizeof(int), cudaMemcpyHostToDevice, stream0);
		//stream_kernel << <N / 256, 256, 0, stream0 >> >(dev_a0, dev_b0, dev_c0, N);
		//cudaMemcpyAsync(host_c + i, dev_c0, N * sizeof(int), cudaMemcpyDeviceToHost, stream0);

		//cudaMemcpyAsync(dev_a1, host_a + i + N, N * sizeof(int), cudaMemcpyHostToDevice, stream1);
		//cudaMemcpyAsync(dev_b1, host_b + i + N, N * sizeof(int), cudaMemcpyHostToDevice, stream1);
		//stream_kernel << <N / 256, 256, 0, stream1 >> >(dev_a1, dev_b1, dev_c1, N);
		//cudaMemcpyAsync(host_c + i + N, dev_c1, N * sizeof(int), cudaMemcpyDeviceToHost, stream1);

		// �Ƽ����ÿ�����ȷ�ʽ
		cudaMemcpyAsync(dev_a0, host_a + i, N * sizeof(int), cudaMemcpyHostToDevice, stream0);
		cudaMemcpyAsync(dev_a1, host_a + i + N, N * sizeof(int), cudaMemcpyHostToDevice, stream1);

		cudaMemcpyAsync(dev_b0, host_b + i, N * sizeof(int), cudaMemcpyHostToDevice, stream0);
		cudaMemcpyAsync(dev_b1, host_b + i + N, N * sizeof(int), cudaMemcpyHostToDevice, stream1);

		stream_kernel << <N / 256, 256, 0, stream0 >> >(dev_a0, dev_b0, dev_c0, N);
		stream_kernel << <N / 256, 256, 0, stream1 >> >(dev_a1, dev_b1, dev_c1, N);

		cudaMemcpyAsync(host_c + i, dev_c0, N * sizeof(int), cudaMemcpyDeviceToHost, stream0);
		cudaMemcpyAsync(host_c + i + N, dev_c1, N * sizeof(int), cudaMemcpyDeviceToHost, stream1);
	}

	cudaStreamSynchronize(stream0);
	cudaStreamSynchronize(stream1);

	memcpy(c, host_c, length * sizeof(int));

	cudaFreeHost(host_a);
	cudaFreeHost(host_b);
	cudaFreeHost(host_c);
	cudaFree(dev_a0);
	cudaFree(dev_b0);
	cudaFree(dev_c0);
	cudaFree(dev_a1);
	cudaFree(dev_b1);
	cudaFree(dev_c1);
	cudaStreamDestroy(stream0);
	cudaStreamDestroy(stream1);

	cudaEventRecord(stop, 0);
	cudaEventSynchronize(stop);
	cudaEventElapsedTime(elapsed_time, start, stop);
	cudaEventDestroy(start);
	cudaEventDestroy(stop);

	return 0;
}

int streams_gpu(const int* a, const int* b, int* c, int length, float* elapsed_time)
{
	int ret{ 0 };
	//ret = streams_gpu_1(a, b, c, length, elapsed_time); // ʹ�õ�����
	ret = streams_gpu_2(a, b, c, length, elapsed_time); // ʹ�ö����

	return ret;
}
