#ifndef FBC_CUDA_TEST_COMMON_HPP_
#define FBC_CUDA_TEST_COMMON_HPP_

#include <cuda_runtime.h> // For the CUDA runtime routines (prefixed with "cuda_")
#include <device_launch_parameters.h>
#include <opencv2/opencv.hpp>

#define checkCudaErrors(val) check_Cuda((val), __FUNCTION__, __FILE__, __LINE__)
#define checkErrors(val) check((val), __FUNCTION__, __FILE__, __LINE__)

#define CHECK(x) { \
	if (x) {} \
	else { fprintf(stderr, "Check Failed: %s, file: %s, line: %d\n", #x, __FILE__, __LINE__); return -1; } \
}

#define PRINT_ERROR_INFO(info) { \
	fprintf(stderr, "Error: %s, file: %s, func: %s, line: %d\n", #info, __FILE__, __FUNCTION__, __LINE__); \
	return -1; }

#define TIME_START_CPU auto start = std::chrono::high_resolution_clock::now();
#define TIME_END_CPU auto end = std::chrono::high_resolution_clock::now(); \
	auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start); \
	*elapsed_time = duration.count() * 1.0e-6;

#define TIME_START_GPU cudaEvent_t start, stop; /* cudaEvent_t: CUDA event types,�ṹ������, CUDA�¼�,���ڲ���GPU��ĳ
	�������ϻ��ѵ�ʱ��,CUDA�е��¼���������һ��GPUʱ���,����CUDA�¼�����
	GPU��ʵ�ֵ�,������ǲ����ڶ�ͬʱ�����豸�������������Ļ�ϴ����ʱ */ \
	cudaEventCreate(&start); /* ����һ���¼�����,�첽���� */ \
	cudaEventCreate(&stop); \
	cudaEventRecord(start, 0); /* ��¼һ���¼�,�첽����,start��¼��ʼʱ�� */
#define TIME_END_GPU cudaEventRecord(stop, 0); /* ��¼һ���¼�,�첽����,stop��¼����ʱ�� */ \
	cudaEventSynchronize(stop); /* �¼�ͬ��,�ȴ�һ���¼����,�첽���� */ \
	cudaEventElapsedTime(elapsed_time, start, stop); /* ���������¼�֮�侭����ʱ��,��λΪ����,�첽���� */ \
	cudaEventDestroy(start); /* �����¼�����,�첽���� */ \
	cudaEventDestroy(stop);

#define EPS_ 1.0e-4 // ��(Epsilon),�ǳ�С����
#define PI 3.1415926535897932f
#define INF 2.e10f

template< typename T > int check_Cuda(T result, const char * const func, const char * const file, const int line);
template< typename T > int check(T result, const char * const func, const char * const file, const int line);
void generator_random_number(float* data, int length, float a = 0.f, float b = 1.f);
template<typename T> void generator_random_number(T* data, int length, T a = (T)0, T b = (T)1);
int save_image(const cv::Mat& mat1, const cv::Mat& mat2, int width, int height, const std::string& name);
template<typename T> int compare_result(const T* src1, const T* src2, int length);
template<typename T> int read_file(const std::string& name, int length, T* data, int mode = 0); // mode = 0: txt; mode = 1: binary
template<typename T> int write_file(const std::string& name, int length, const T* data, int mode = 0); // mode = 0: txt; mode = 1: binary


#endif // FBC_CUDA_TEST_COMMON_HPP_
