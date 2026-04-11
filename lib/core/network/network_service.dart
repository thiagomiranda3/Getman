import 'package:dio/dio.dart';

class NetworkService {
  final Dio _dio;

  NetworkService({Dio? dio}) : _dio = dio ?? Dio();

  Future<Response> request({
    required String url,
    required String method,
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
  }) {
    return _dio.request(
      url,
      data: data,
      queryParameters: queryParameters,
      options: Options(
        method: method,
        headers: headers,
      ),
      cancelToken: cancelToken,
    );
  }
}
