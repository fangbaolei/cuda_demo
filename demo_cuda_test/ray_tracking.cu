#include "funset.hpp"
#include <iostream>
#include <algorithm>
#include <memory>
#include <vector>
#include <cuda_runtime.h> // For the CUDA runtime routines (prefixed with "cuda_")
#include <device_launch_parameters.h>
#include "common.hpp"

// ͨ��һ�����ݽṹ�����潨ģ
struct Sphere {
	float r, b, g;
	float radius;
	float x, y, z;
	/* __device__: ���������޶���,���������εĺ������豸��ִ�У�ֻ�ܴ��豸�ϵ��ã�
	��ֻ��������__device__��������__global__�����е��ã�__device__������֧�ֵݹ飻
	__device__�����ĺ������ڲ���������̬������__device__�����Ĳ�����Ŀ�ǲ��ɱ仯��;
	���ܶ�__device__����ȡָ�� */
	__device__ float hit(float ox, float oy, float *n)
	{
		float dx = ox - x;
		float dy = oy - y;
		if (dx*dx + dy*dy < radius*radius) {
			float dz = sqrtf(radius*radius - dx*dx - dy*dy);
			*n = dz / sqrtf(radius * radius);
			return dz + z;
		}
		return -INF;
	}
};

// method2: ʹ�ó����ڴ�
/* __constant__: ���������޶�����������__device__�޶������ã����������ı�������
���ڳ����洢���ռ䣻��Ӧ�ó��������ͬ���������ڣ�����ͨ������ʱ��������˷��ʣ�
�豸�˵������߳�Ҳ�ɷ��ʡ�__constant__����Ĭ��Ϊ�Ǿ�̬�洢��__constant__������
extern�ؼ�������Ϊ�ⲿ������__constant__����ֻ�����ļ��������������������ٺ���
����������__constant__�������ܴ�device�и�ֵ��ֻ�ܴ�host��ͨ��host����ʱ������
ֵ��__constant__���ѱ����ķ�������Ϊֻ�������ȫ���ڴ��ж�ȡ������ȣ��ӳ�����
���ж�ȡ��ͬ�����ݿ��Խ�Լ�ڴ���������ڴ����ڱ����ں˺���ִ���ڼ䲻�ᷢ����
�������ݡ�
�����ڴ棺���ڱ����ں˺���ִ���ڼ䲻�ᷢ���仯�����ݡ�NVIDIAӲ���ṩ��64KB�ĳ�
���ڴ棬���ҶԳ����ڴ��ȡ�˲�ͬ�ڱ�׼ȫ���ڴ�Ĵ���ʽ����ĳЩ����У��ó���
�ڴ����滻ȫ���ڴ�����Ч�ؼ����ڴ���� ��ĳЩ����£�ʹ�ó����ڴ潫����Ӧ�ó�
������� */
__constant__ Sphere dev_spheres[20]; // �����ڴ�, = sphere_num

/* __global__: ���������޶���;���豸������;�������˵���,��������3.2�����Ͽ�����
�豸�˵���;�����ĺ����ķ���ֵ������void����;�Դ����ͺ����ĵ������첽��,����
�豸��ȫ�����������֮ǰ�ͷ�����;�Դ����ͺ����ĵ��ñ���ָ��ִ������,��������
�豸��ִ�к���ʱ��grid��block��ά��,�Լ���ص���(������<<<   >>>�����);
a kernel,��ʾ�˺���Ϊ�ں˺���(������GPU�ϵ�CUDA���м��㺯����Ϊkernel(�ں˺�
��),�ں˺�������ͨ��__global__���������޶�������); */
__global__ static void ray_tracking(unsigned char* ptr_image, Sphere* ptr_sphere, int width, int height, int sphere_num)
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
	float ox{ (x - width / 2.f) };
	float oy{ (y - height / 2.f) };

	float r{ 0 }, g{ 0 }, b{ 0 };
	float maxz{ -INF };

	for (int i = 0; i < sphere_num; ++i) {
		float n;
		float t = ptr_sphere[i].hit(ox, oy, &n);
		if (t > maxz) {
			float fscale = n;
			r = ptr_sphere[i].r * fscale;
			g = ptr_sphere[i].g * fscale;
			b = ptr_sphere[i].b * fscale;
			maxz = t;
		}
	}

	ptr_image[offset * 4 + 0] = static_cast<unsigned char>(r * 255);
	ptr_image[offset * 4 + 1] = static_cast<unsigned char>(g * 255);
	ptr_image[offset * 4 + 2] = static_cast<unsigned char>(b * 255);
	ptr_image[offset * 4 + 3] = 255;
}

__global__ static void ray_tracking(unsigned char* ptr_image, int width, int height, int sphere_num)
{
	int x = threadIdx.x + blockIdx.x * blockDim.x;
	int y = threadIdx.y + blockIdx.y * blockDim.y;
	int offset = x + y * blockDim.x * gridDim.x;
	float ox{ (x - width / 2.f) };
	float oy{ (y - height / 2.f) };

	float r{ 0 }, g{ 0 }, b{ 0 };
	float maxz{ -INF };

	for (int i = 0; i < sphere_num; ++i) {
		float n;
		float t = dev_spheres[i].hit(ox, oy, &n);
		if (t > maxz) {
			float fscale = n;
			r = dev_spheres[i].r * fscale;
			g = dev_spheres[i].g * fscale;
			b = dev_spheres[i].b * fscale;
			maxz = t;
		}
	}

	ptr_image[offset * 4 + 0] = static_cast<unsigned char>(r * 255);
	ptr_image[offset * 4 + 1] = static_cast<unsigned char>(g * 255);
	ptr_image[offset * 4 + 2] = static_cast<unsigned char>(b * 255);
	ptr_image[offset * 4 + 3] = 255;
}

int ray_tracking_gpu(const float* a, const float* b, const float* c, int sphere_num, unsigned char* ptr, int width, int height, float* elapsed_time)
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
	unsigned char* dev_image{ nullptr };

	std::unique_ptr<Sphere[]> spheres(new Sphere[sphere_num]);
	for (int i = 0, t = 0; i < sphere_num; ++i, t += 3) {
		spheres[i].r = a[t];
		spheres[i].g = a[t + 1];
		spheres[i].b = a[t + 2];
		spheres[i].x = b[t];
		spheres[i].y = b[t + 1];
		spheres[i].z = b[t + 2];
		spheres[i].radius = c[i];
	}

	// cudaMalloc: ���豸�˷����ڴ�
	cudaMalloc(&dev_image, length);

	// method1: û��ʹ�ó����ڴ�
	//Sphere* dev_spheres{ nullptr };
	//cudaMalloc(&dev_spheres, sizeof(Sphere) * sphere_num);
	/* cudaMemcpy: �������˺��豸�˿�������,�˺������ĸ���������������֮һ:
	(1). cudaMemcpyHostToHost: �������ݴ������˵�������
	(2). cudaMemcpyHostToDevice: �������ݴ������˵��豸��
	(3). cudaMemcpyDeviceToHost: �������ݴ��豸�˵�������
	(4). cudaMemcpyDeviceToDevice: �������ݴ��豸�˵��豸��
	(5). cudaMemcpyDefault: ��ָ��ֵ�Զ��ƶϿ������ݷ���,��Ҫ֧��
	ͳһ����Ѱַ(CUDA6.0�����ϰ汾)
	cudaMemcpy��������������ͬ���� */
	//cudaMemcpy(dev_spheres, spheres.get(), sizeof(Sphere) * sphere_num, cudaMemcpyHostToDevice);

	// method2: ʹ�ó����ڴ�
	/* cudaMemcpyToSymbol: cudaMemcpyToSymbol��cudaMemcpy����Ϊ
	cudaMemcpyHostToDeviceʱ��Ψһ��������cudaMemcpyToSymbol�Ḵ�Ƶ�������
	�棬��cudaMemcpy�Ḵ�Ƶ�ȫ���ڴ� */
	cudaMemcpyToSymbol(dev_spheres, spheres.get(), sizeof(Sphere)* sphere_num);

	const int threads_block{ 16 };
	/* dim3: ����uint3���������ʸ�����ͣ��൱����3��unsigned int������ɵ�
	�ṹ�壬�ɱ�ʾһ����ά���飬�ڶ���dim3���ͱ���ʱ������û�и�ֵ��Ԫ�ض�
	�ᱻ����Ĭ��ֵ1 */
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
	//ray_tracking << <blocks, threads >> >(dev_image, dev_spheres, width, height, sphere_num); // method1, ��ʹ�ó����ڴ�
	ray_tracking << <blocks, threads >> >(dev_image, width, height, sphere_num); // method2, ʹ�ó����ڴ�

	cudaMemcpy(ptr, dev_image, length, cudaMemcpyDeviceToHost);

	// cudaFree: �ͷ��豸����cudaMalloc����������ڴ�
	cudaFree(dev_image);
	//cudaFree(dev_spheres); // ʹ��method1ʱ��Ҫ�ͷ�, ���ʹ�ó����ڴ漴method2����Ҫ�ͷ�

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
