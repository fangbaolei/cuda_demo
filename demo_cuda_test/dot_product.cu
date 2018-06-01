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
��),�ں˺�������ͨ��__global__���������޶�������);*/
__global__ static void dot_product(const float* A, const float* B, float* partial_C, int elements_num)
{
	/* __shared__: ���������޶�����ʹ��__shared__�޶�����������__device__��
	�������ã���ʱ�����ı���λ��block�еĹ���洢���ռ��У���block������ͬ
	���������ڣ�����ͨ��block�ڵ������̷߳��ʣ�__shared__��__constant__����
	Ĭ��Ϊ�Ǿ�̬�洢����__shared__ǰ���Լ�extern�ؼ��֣�����ʾ���Ǳ�����С
	��ִ�в���ȷ����__shared__����������ʱ���ܳ�ʼ�������Խ�CUDA C�Ĺؼ���
	__shared__��ӵ����������У��⽫ʹ�������פ���ڹ����ڴ��У�CUDA C����
	���Թ����ڴ��еı�������ͨ�������ֱ��ȡ��ͬ�Ĵ���ʽ */
	__shared__ float cache[256]; // == threadsPerBlock

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
	int tid = threadIdx.x + blockIdx.x * blockDim.x;
	int cacheIndex = threadIdx.x;

	float tmp{ 0.f };
	while (tid < elements_num) {
		tmp += A[tid] * B[tid];
		tid += blockDim.x * gridDim.x;
	}

	// ����cache����Ӧλ���ϵ�ֵ
	// �����ڴ滺���е�ƫ�ƾ͵����߳��������߳̿����������ƫ���޹أ���Ϊÿ
	// ���߳̿鶼ӵ�иù����ڴ��˽�и���
	cache[cacheIndex] = tmp;

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

	// ���ڹ�Լ������˵������codeҪ��threadPerBlock������2��ָ��
	int i = blockDim.x / 2;
	while (i != 0) {
		if (cacheIndex < i)
			cache[cacheIndex] += cache[cacheIndex + i];

		// ��ѭ�������и����˹����ڴ����cache��������ѭ������һ�ε�����ʼ֮ǰ��
		// ��Ҫȷ����ǰ�����������̵߳ĸ��²������Ѿ����
		__syncthreads();
		i /= 2;
	}

	// ֻ��cacheIndex == 0���߳�ִ��������������������Ϊֻ��һ��ֵд�뵽
	// ȫ���ڴ棬���ֻ��Ҫһ���߳���ִ�������������Ȼ��Ҳ����ѡ���κ�һ��
	// �߳̽�cache[0]д�뵽ȫ���ڴ�
	if (cacheIndex == 0)
		partial_C[blockIdx.x] = cache[0];
}

static int dot_product_gpu_1(const float* A, const float* B, float* value, int elements_num, float* elapsed_time)
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

	size_t lengthA{ elements_num * sizeof(float) }, lengthB{ elements_num * sizeof(float) };
	float *d_A{ nullptr }, *d_B{ nullptr }, *d_partial_C{ nullptr };

	// cudaMalloc: ���豸�˷����ڴ�
	cudaMalloc(&d_A, lengthA);
	cudaMalloc(&d_B, lengthB);

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

	const int threadsPerBlock{ 256 };
	const int blocksPerGrid = std::min(64, (elements_num + threadsPerBlock - 1) / threadsPerBlock);
	size_t lengthC{ blocksPerGrid * sizeof(float) };
	cudaMalloc(&d_partial_C, lengthC);

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
	dot_product << < blocksPerGrid, threadsPerBlock >> >(d_A, d_B, d_partial_C, elements_num);

	/* cudaDeviceSynchronize: kernel���������첽��, Ϊ�˶�λ���Ƿ����, һ
	����Ҫ����cudaDeviceSynchronize��������ͬ��; ����һֱ��������״̬,ֱ��
	ǰ����������������Ѿ���ȫ��ִ�����,���ǰ��ִ�е�ĳ������ʧ��,����
	����һ�����󣻵��������ж����,������֮����ĳһ����Ҫͨ��ʱ,�Ǿͱ���
	����һ�㴦����ͬ�������,��cudaDeviceSynchronize���첽����
	reference: https://stackoverflow.com/questions/11888772/when-to-call-cudadevicesynchronize */
	//cudaDeviceSynchronize();

	std::unique_ptr<float[]> partial_C(new float[blocksPerGrid]);
	cudaMemcpy(partial_C.get(), d_partial_C, lengthC, cudaMemcpyDeviceToHost);

	*value = 0.f;
	for (int i = 0; i < blocksPerGrid; ++i) {
		(*value) += partial_C[i];
	}

	// cudaFree: �ͷ��豸����cudaMalloc����������ڴ�
	cudaFree(d_A);
	cudaFree(d_B);
	cudaFree(d_partial_C);

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

static int dot_product_gpu_2(const float* A, const float* B, float* value, int elements_num, float* elapsed_time)
{
	// cudaDeviceProp: cuda�豸���Խṹ��
	cudaDeviceProp prop;
	int count;
	// cudaGetDeviceCount: ��ü��������豸������
	cudaGetDeviceCount(&count);
	//fprintf(stderr, "device count: %d\n", count);
	int whichDevice;
	// cudaGetDevice: ��õ�ǰ����ʹ�õ��豸ID���豸ID��0��ʼ���
	cudaGetDevice(&whichDevice);
	// cudaGetDeviceProperties: ��ȡGPU�豸�����Ϣ
	cudaGetDeviceProperties(&prop, whichDevice);
	// cudaDeviceProp::canMapHostMemory: GPU�Ƿ�֧���豸ӳ�������ڴ�
	if (prop.canMapHostMemory != 1) {
		fprintf(stderr, "Device cannot map memory.\n");
		return -1;
	}
	
	// cudaSetDeviceFlags: �����豸Ҫ����ִ�еı�־
	// ���豸�����ܷ����㿽���ڴ��״̬
	cudaSetDeviceFlags(cudaDeviceMapHost);

	cudaEvent_t start, stop;
	cudaEventCreate(&start);
	cudaEventCreate(&stop);
	cudaEventRecord(start, 0);

	const int threadsPerBlock{ 256 };
	const int blocksPerGrid = std::min(64, (elements_num + threadsPerBlock - 1) / threadsPerBlock);

	size_t lengthA{ elements_num * sizeof(float) }, lengthB{ elements_num * sizeof(float) };
	float *d_A{ nullptr }, *d_B{ nullptr }, *d_partial_C{ nullptr };
	float *a{ nullptr }, *b{ nullptr }, *partial_c{ nullptr };

	/* cudaHostAlloc: ���������ڴ档C�⺯��malloc�������׼�ģ���
	��ҳ��(Pagable)�����ڴ棬��cudaHostAlloc������ҳ�����������ڴ档ҳ������
	��Ҳ��Ϊ�̶��ڴ�(Pinned Memory)���߲��ɷ�ҳ�ڴ棬����һ����Ҫ�����ԣ�����ϵ
	ͳ�����������ڴ��ҳ�������������ϣ��Ӷ�ȷ���˸��ڴ�ʼ��פ����������
	���С���ˣ�����ϵͳ�ܹ���ȫ��ʹĳ��Ӧ�ó�����ʸ��ڴ�������ַ����Ϊ
	����ڴ潫���ᱻ�ƻ��������¶�λ������GPU֪���ڴ�������ַ����˿���ͨ
	��"ֱ���ڴ����(Direct Memory Access, DMA)"��������GPU������֮�临�����ݡ�
	�̶��ڴ���һ��˫�н�����ʹ�ù̶��ڴ�ʱ���㽫ʧȥ�����ڴ�����й��ܡ�
	���飺����cudaMemcpy�����е�Դ�ڴ����Ŀ���ڴ棬��ʹ��ҳ�����ڴ棬������
	������Ҫʹ������ʱ�����ͷš�
	�㿽���ڴ棺ͨ��cudaHostAlloc����+cudaHostAllocMapped���������̶��ڴ���
	cudaHostAlloc����+cudaHostAllocDefault������ͨ��cudaHostAllocMapped����
	�������ڴ�Ҳ�ǹ̶��ģ�����ͨ��cudaHostAllocDefault����Ĺ̶��ڴ�������ͬ
	�����ԡ��������ڴ���˿�������������GPU֮����ڴ渴���⣬��������CUDA C��
	������ֱ�ӷ����������͵������ڴ棬������Ҫ���Ƶ�GPU�����Ҳ��Ϊ�㿽���ڴ档
	cudaHostAllocMapped�������־��������ʱ����GPU�з�������ڴ档
	cudaHostAllocWriteCombined�������־��ʾ������ʱӦ�ý��ڴ����Ϊ"�ϲ�ʽд
	��(Write-Combined)"�ڴ档�����־������ı�Ӧ�ó�������ܣ���ȴ����������
	����GPU��ȡ�ڴ�ʱ�����ܡ�Ȼ������CPUҲҪ��ȡ����ڴ�ʱ��"�ϲ�ʽд��"���Ե�
	�ܵ�Ч��
	���ڼ���GPU��ʹ���㿽���ڴ�ͨ���������������������Ϊ�ڴ�����������������
	����ġ�������������Ϊ�㿽���ڴ��Ψһ���þ��Ǳ��ⲻ��Ҫ�����ݸ��ơ���������
	�Ĺ̶��ڴ涼����һ���ľ����ԣ��㿽���ڴ�ͬ�������⣺ÿ���̶��ڴ涼��ռ��ϵͳ
	�Ŀ��������ڴ棬�����ս�����ϵͳ�����ܡ�
	�������ڴ������ڴ涼ֻ��ʹ��һ��ʱ����ô�ڶ���GPU��ʹ���㿽���ڴ潫�������������� */
	// allocate the memory on the CPU
	cudaHostAlloc(&a, lengthA, cudaHostAllocWriteCombined | cudaHostAllocMapped);
	cudaHostAlloc(&b, lengthB, cudaHostAllocWriteCombined | cudaHostAllocMapped);
	cudaHostAlloc(&partial_c, blocksPerGrid * sizeof(float), cudaHostAllocMapped);

	/* cudaHostGetDevicePointer: �����cudaHostAlloc�����ӳ�������ڴ���豸ָ�롣
	����GPU�������ڴ�ռ��ַӳ����CPU��ͬ����cudaHostAlloc���ص���CPU�ϵ�ָ�룬
	�����Ҫ����cudaHostGetDevicePointer�������������ڴ���GPU�ϵ���Чָ�롣��Щָ��
	�������ݸ��˺��������������GPU������ڴ�ִ�ж�ȡ��д��Ȳ��� */
	// find out the GPU pointers
	cudaHostGetDevicePointer(&d_A, a, 0);
	cudaHostGetDevicePointer(&d_B, b, 0);
	cudaHostGetDevicePointer(&d_partial_C, partial_c, 0);

	memcpy(a, A, lengthA);
	memcpy(b, B, lengthB);

	dot_product << < blocksPerGrid, threadsPerBlock >> >(d_A, d_B, d_partial_C, elements_num);

	/* cudaThreadSynchronize: �ȴ������豸���, ��CPU��GPUͬ��*/
	cudaThreadSynchronize();

	*value = 0.f;
	for (int i = 0; i < blocksPerGrid; ++i) {
		(*value) += partial_c[i];
	}

	// cudaFreeHost: �ͷ��豸����cudaHostAlloc����������ڴ�
	cudaFreeHost(d_A);
	cudaFreeHost(d_B);
	cudaFreeHost(d_partial_C);

	cudaEventRecord(stop, 0);
	cudaEventSynchronize(stop);
	cudaEventElapsedTime(elapsed_time, start, stop);
	cudaEventDestroy(start);
	cudaEventDestroy(stop);

	return 0;
}

int dot_product_gpu(const float* A, const float* B, float* value, int elements_num, float* elapsed_time)
{
	int ret{ 0 };
	//ret = dot_product_gpu_1(A, B, value, elements_num, elapsed_time); // ��ͨʵ��
	ret = dot_product_gpu_2(A, B, value, elements_num, elapsed_time); // ͨ���㿽���ڴ�ʵ��

	return ret;
}
