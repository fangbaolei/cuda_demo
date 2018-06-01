#include "funset.hpp"
#include <iostream>
#include <cuda_runtime.h> // For the CUDA runtime routines (prefixed with "cuda_")
#include <device_launch_parameters.h>

/* reference:
	C:\ProgramData\NVIDIA Corporation\CUDA Samples\v8.0\1_Utilities\deviceQuery
*/ 
int get_device_info()
{
	int device_count{ 0 };
	// cudaGetDeviceCount: ��ü��������豸������
	cudaGetDeviceCount(&device_count);
	fprintf(stdout, "GPU�豸�������� %d\n", device_count);

	for (int dev = 0; dev < device_count; ++dev) {
		int driver_version{ 0 }, runtime_version{ 0 };

		/* cudaSetDevice: ����GPUִ��ʱʹ�õ��豸��0��ʾ���������ĵ�һ
		���豸�ţ�����ж���豸������Ϊ0,1,2... */
		cudaSetDevice(dev);

		/* cudaDeviceProp: �豸���Խṹ��
		name: �豸���֣���GeForce 940MX
		totalGlobalMem�� �豸�Ͽ��õ�ȫ���ڴ�����(�ֽ�)
		sharedMemPerBlock: ÿһ���߳̿��Ͽ��õĹ����ڴ�����(�ֽ�)
		regsPerBlock: ÿһ���߳̿��Ͽ��õ�32λ�Ĵ�������
		warpSize�� һ���߳����������߳���������ʵ�������У��߳̿�ᱻ�ָ�ɸ�С���߳���(warp)��
		           �߳����е�ÿ���̶߳����ڲ�ͬ������ִ����ͬ������
		memPitch: ���ڴ濽������������pitch��(�ֽ�)
		maxThreadsPerBlock: ÿһ���߳̿���֧�ֵ�����߳�����
		maxThreadsDim[3]: ÿһ���߳̿��ÿ��ά�ȵ�����С(x,y,z)
		maxGridSize: ÿһ���̸߳��ÿ��ά�ȵ�����С(x,y,z)
		clockRate�� GPU���ʱ��Ƶ��(ǧ����)
		totalConstMem: �豸�Ͽ��õĳ����ڴ�����(�ֽ�)
		major: �豸�����������汾�ţ��豸���������İ汾������һ��GPU��CUDA���ܵ�֧�̶ֳ�
		minor: �豸���������ΰ汾��
		textureAlignment: �������Ҫ��
		deviceOverlap: GPU�Ƿ�֧���豸�ص�(Device Overlap)����,֧���豸�ص����ܵ�GPU�ܹ�
		               ��ִ��һ��CUDA C�˺�����ͬʱ���������豸������֮��ִ�и��ƵȲ���,
			       �ѷ�����ʹ��asyncEngineCount����
		multiProcessorCount: �豸�϶ദ����������
		kernelExecTimeoutEnabled: ָ��ִ�к˺���ʱ�Ƿ�������ʱ������
		integrated: �豸�Ƿ���һ������GPU
		canMapHostMemory: �豸�Ƿ�֧��ӳ�������ڴ棬����Ϊ�Ƿ�֧���㿽���ڴ���ж�����
		computeMode: CUDA�豸����ģʽ���ɲο�cudaComputeMode
		maxTexture1D: һά����֧�ֵ�����С
		maxTexture2D[2]����ά����֧�ֵ�����С(x,y)
		maxTexture3D[3]: ��ά����֧�ֵ�����С(x,y,z)
		memoryClockRate: �ڴ�ʱ��Ƶ�ʷ�ֵ(ǧ����)
		memoryBusWidth: ȫ���ڴ����߿��(bits)
		l2CacheSize: L2�����С(�ֽ�)
		maxThreadsPerMultiProcessor�� ÿ���ദ����֧�ֵ�����߳�����
		concurrentKernels: �豸�Ƿ�֧��ͬʱִ�ж���˺���
		asyncEngineCount: �첽��������
		unifiedAddressing: �Ƿ�֧���豸����������һ��ͳһ�ĵ�ַ�ռ�
		*/
		cudaDeviceProp device_prop;
		/* cudaGetDeviceProperties: ��ȡָ����GPU�豸���������Ϣ */
		cudaGetDeviceProperties(&device_prop, dev);

		fprintf(stdout, "\n�豸 %d ����: %s\n", dev, device_prop.name);

		/* cudaDriverGetVersion: ��ȡCUDA�����汾 */
		cudaDriverGetVersion(&driver_version);
		fprintf(stdout, "CUDA�����汾�� %d.%d\n", driver_version/1000, (driver_version%1000)/10);
		/* cudaRuntimeGetVersion: ��ȡCUDA����ʱ�汾 */
		cudaRuntimeGetVersion(&runtime_version);
		fprintf(stdout, "CUDA����ʱ�汾�� %d.%d\n", runtime_version/1000, (runtime_version%1000)/10);

		fprintf(stdout, "�豸���������� %d.%d\n", device_prop.major, device_prop.minor);
		fprintf(stdout, "�豸�Ͽ��õ�ȫ���ڴ������� %f MB, %llu bytes\n",
			(float)device_prop.totalGlobalMem / (1024 * 1024), (unsigned long long)device_prop.totalGlobalMem);
		fprintf(stdout, "ÿһ���߳̿��Ͽ��õĹ����ڴ������� %f KB, %lu bytes\n",
			(float)device_prop.sharedMemPerBlock / 1024, device_prop.sharedMemPerBlock);
		fprintf(stdout, "ÿһ���߳̿��Ͽ��õ�32λ�Ĵ�������: %d\n", device_prop.regsPerBlock);
		fprintf(stdout, "һ���߳����������߳������� %d\n", device_prop.warpSize);
		fprintf(stdout, "���ڴ濽������������pitch��: %d bytes\n", device_prop.memPitch);
		fprintf(stdout, "ÿһ���߳̿���֧�ֵ�����߳�����: %d\n", device_prop.maxThreadsPerBlock);
		fprintf(stdout, "ÿһ���߳̿��ÿ��ά�ȵ�����С(x,y,z): (%d, %d, %d)\n",
			device_prop.maxThreadsDim[0], device_prop.maxThreadsDim[1], device_prop.maxThreadsDim[2]);
		fprintf(stdout, "ÿһ���̸߳��ÿ��ά�ȵ�����С(x,y,z): (%d, %d, %d)\n",
			device_prop.maxGridSize[0], device_prop.maxGridSize[1], device_prop.maxGridSize[2]);
		fprintf(stdout, "GPU���ʱ��Ƶ��: %.0f MHz (%0.2f GHz)\n",
			device_prop.clockRate*1e-3f, device_prop.clockRate*1e-6f);
		fprintf(stdout, "�豸�Ͽ��õĳ����ڴ�����: %lu bytes\n", device_prop.totalConstMem);
		fprintf(stdout, "�������Ҫ��: %lu bytes\n", device_prop.textureAlignment);
		fprintf(stdout, "�Ƿ�֧���豸�ص�����: %s\n", device_prop.deviceOverlap ? "Yes" : "No");
		fprintf(stdout, "�豸�϶ദ����������: %d\n", device_prop.multiProcessorCount);
		fprintf(stdout, "ִ�к˺���ʱ�Ƿ�������ʱ������: %s\n", device_prop.kernelExecTimeoutEnabled ? "Yes" : "No");
		fprintf(stdout, "�豸�Ƿ���һ������GPU: %s\n", device_prop.integrated ? "Yes" : "No");
		fprintf(stdout, "�豸�Ƿ�֧��ӳ�������ڴ�: %s\n", device_prop.canMapHostMemory ? "Yes" : "No");
		fprintf(stdout, "CUDA�豸����ģʽ: %d\n", device_prop.computeMode);
		fprintf(stdout, "һά����֧�ֵ�����С: %d\n", device_prop.maxTexture1D);
		fprintf(stdout, "��ά����֧�ֵ�����С(x,y): (%d, %d)\n", device_prop.maxTexture2D[0], device_prop.maxSurface2D[1]);
		fprintf(stdout, "��ά����֧�ֵ�����С(x,y,z): (%d, %d, %d)\n",
			device_prop.maxTexture3D[0], device_prop.maxSurface3D[1], device_prop.maxSurface3D[2]);
		fprintf(stdout, "�ڴ�ʱ��Ƶ�ʷ�ֵ: %.0f Mhz\n", device_prop.memoryClockRate * 1e-3f);
		fprintf(stdout, "ȫ���ڴ����߿��: %d bits\n", device_prop.memoryBusWidth);
		fprintf(stdout, "L2�����С: %d bytes\n", device_prop.l2CacheSize);
		fprintf(stdout, "ÿ���ദ����֧�ֵ�����߳�����: %d\n", device_prop.maxThreadsPerMultiProcessor);
		fprintf(stdout, "�豸�Ƿ�֧��ͬʱִ�ж���˺���: %s\n", device_prop.concurrentKernels ? "Yes" : "No");
		fprintf(stdout, "�첽��������: %d\n", device_prop.asyncEngineCount);
		fprintf(stdout, "�Ƿ�֧���豸����������һ��ͳһ�ĵ�ַ�ռ�: %s\n", device_prop.unifiedAddressing ? "Yes" : "No");
	}

	return 0;
}
