#include "funset.hpp"
#include <iostream>
#include <cuda_runtime.h> // For the CUDA runtime routines (prefixed with "cuda_")
#include <device_launch_parameters.h>
#include "common.hpp"

// reference: C:\ProgramData\NVIDIA Corporation\CUDA Samples\v8.0\0_Simple\vectorAdd
/* __global__: ���������޶���;���豸������;�������˵���,��������3.2�����Ͽ�����
�豸�˵���;�����ĺ����ķ���ֵ������void����;�Դ����ͺ����ĵ������첽��,����
�豸��ȫ�����������֮ǰ�ͷ�����;�Դ����ͺ����ĵ��ñ���ָ��ִ������,��������
�豸��ִ�к���ʱ��grid��block��ά��,�Լ���ص���(������<<<   >>>�����);
a kernel,��ʾ�˺���Ϊ�ں˺���(������GPU�ϵ�CUDA���м��㺯����Ϊkernel(�ں˺�
��),�ں˺�������ͨ��__global__���������޶�������);*/
__global__ static void vector_add(const float *A, const float *B, float *C, int numElements)
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
  int i = blockDim.x * blockIdx.x + threadIdx.x;
  if (i < numElements) {
    C[i] = A[i] + B[i];
  }
}

int vector_add_gpu(const float* A, const float* B, float* C, int numElements, float* elapsed_time)
{
  /* Error code to check return values for CUDA calls
  cudaError_t: CUDA Error types, ö������,CUDA������,�ɹ�����
  cudaSuccess(0),���򷵻�����(>0) */
  cudaError_t err{ cudaSuccess };

  /* cudaEvent_t: CUDA event types���ṹ������, CUDA�¼������ڲ���GPU��ĳ
  �������ϻ��ѵ�ʱ�䣬CUDA�е��¼���������һ��GPUʱ���������CUDA�¼�����
  GPU��ʵ�ֵģ�������ǲ����ڶ�ͬʱ�����豸�������������Ļ�ϴ����ʱ*/
  cudaEvent_t start, stop;
  // cudaEventCreate: ����һ���¼������첽����
  cudaEventCreate(&start);
  cudaEventCreate(&stop);
  // cudaEventRecord: ��¼һ���¼����첽����,start��¼��ʼʱ��
  cudaEventRecord(start, 0);

  size_t length{ numElements * sizeof(float) };
  float *d_A{ nullptr }, *d_B{ nullptr }, *d_C{ nullptr };

  // cudaMalloc: ���豸�˷����ڴ�
  err = cudaMalloc(&d_A, length);
  if (err != cudaSuccess) {
    // cudaGetErrorString: ���ش�����������ַ���
    fprintf(stderr, "Failed to allocate device vector A (error code %s)!\n",
      cudaGetErrorString(err));
    return -1;
  }
  err = cudaMalloc(&d_B, length);
  if (err != cudaSuccess) PRINT_ERROR_INFO(cudaMalloc);
  err = cudaMalloc(&d_C, length);
  if (err != cudaSuccess) PRINT_ERROR_INFO(cudaMalloc);

  /* cudaMemcpy: �������˺��豸�˿�������,�˺������ĸ���������������֮һ:
  (1). cudaMemcpyHostToHost: �������ݴ������˵�������
  (2). cudaMemcpyHostToDevice: �������ݴ������˵��豸��
  (3). cudaMemcpyDeviceToHost: �������ݴ��豸�˵�������
  (4). cudaMemcpyDeviceToDevice: �������ݴ��豸�˵��豸��
  (5). cudaMemcpyDefault: ��ָ��ֵ�Զ��ƶϿ������ݷ���,��Ҫ֧��
  ͳһ����Ѱַ(CUDA6.0�����ϰ汾)
  cudaMemcpy��������������ͬ���� */
  err = cudaMemcpy(d_A, A, length, cudaMemcpyHostToDevice);
  if (err != cudaSuccess) PRINT_ERROR_INFO(cudaMemcpy);
  err = cudaMemcpy(d_B, B, length, cudaMemcpyHostToDevice);
  if (err != cudaSuccess) PRINT_ERROR_INFO(cudaMemcpy);

  // Launch the Vector Add CUDA kernel
  const int threadsPerBlock{ 256 };
  const int blocksPerGrid = (numElements + threadsPerBlock - 1) / threadsPerBlock;
  fprintf(stderr, "CUDA kernel launch with %d blocks of %d threads\n", blocksPerGrid, threadsPerBlock);
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
  vector_add << <blocksPerGrid, threadsPerBlock >> >(d_A, d_B, d_C, numElements);
  /* cudaGetLastError: ��ͬһ�������߳���,��������ʱ�����в��������һ��
  ���󲢽�������ΪcudaSuccess;�˺���Ҳ���ܷ�����ǰ�첽�����Ĵ�����;����
  ��������ڶ�cudaGetLastError�ĵ���֮�䷢��ʱ,�����һ������ᱻ����;
  kernel���������첽��,Ϊ�˶�λ���Ƿ����,һ����Ҫ����
  cudaDeviceSynchronize��������ͬ��,Ȼ���ٵ���cudaGetLastError����;*/
  err = cudaGetLastError();
  if (err != cudaSuccess) PRINT_ERROR_INFO(cudaGetLastError);
  // Copy the device result vector in device memory to the host result vector in host memory.
  err = cudaMemcpy(C, d_C, length, cudaMemcpyDeviceToHost);
  if (err != cudaSuccess) PRINT_ERROR_INFO(cudaMemcpy);

  // cudaFree: �ͷ��豸����cudaMalloc����������ڴ�
  err = cudaFree(d_A);
  if (err != cudaSuccess) PRINT_ERROR_INFO(cudaFree);
  err = cudaFree(d_B);
  if (err != cudaSuccess) PRINT_ERROR_INFO(cudaFree);
  err = cudaFree(d_C);
  if (err != cudaSuccess) PRINT_ERROR_INFO(cudaFree);

  // cudaEventRecord: ��¼һ���¼����첽����,stop��¼����ʱ��
  cudaEventRecord(stop, 0);
  // cudaEventSynchronize: �¼�ͬ�����ȴ�һ���¼���ɣ��첽����
  cudaEventSynchronize(stop);
  // cudaEventElapseTime: ���������¼�֮�侭����ʱ�䣬��λΪ���룬�첽����
  cudaEventElapsedTime(elapsed_time, start, stop);
  // cudaEventDestroy: �����¼������첽����
  cudaEventDestroy(start);
  cudaEventDestroy(stop);

  return err;
}
