import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'settings.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

String errorMessage(Object error) {
  if (error is ApiException) return error.message;
  return 'Une erreur est survenue';
}

/// JWT kept in memory and persisted in Keychain / Keystore.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'bgi_token';
  final FlutterSecureStorage _storage;
  String? _token;
  bool _loaded = false;

  Future<String?> read() async {
    if (!_loaded) {
      _token = await _storage.read(key: _key);
      _loaded = true;
    }
    return _token;
  }

  Future<void> write(String token) async {
    _token = token;
    _loaded = true;
    await _storage.write(key: _key, value: token);
  }

  Future<void> clear() async {
    _token = null;
    _loaded = true;
    await _storage.delete(key: _key);
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// Holds the callback run when the API answers 401 (set by the auth notifier).
class UnauthorizedHandler {
  void Function()? callback;
  void call() => callback?.call();
}

final unauthorizedHandlerProvider = Provider<UnauthorizedHandler>(
  (ref) => UnauthorizedHandler(),
);

class DownloadedFile {
  DownloadedFile(this.bytes, this.filename);
  final Uint8List bytes;
  final String filename;
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.tokens,
    required this.onUnauthorized,
  }) : dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 120),
            sendTimeout: const Duration(seconds: 60),
          ),
        ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokens.read();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
      ),
    );
  }

  final Dio dio;
  final TokenStore tokens;
  final void Function() onUnauthorized;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => dio.get<dynamic>(path, queryParameters: _clean(query)));

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) =>
      _send(
        () => dio.post<dynamic>(
          path,
          data: body ?? <String, dynamic>{},
          queryParameters: _clean(query),
        ),
      );

  Future<dynamic> patch(String path, {Object? body}) =>
      _send(() => dio.patch<dynamic>(path, data: body ?? <String, dynamic>{}));

  Future<dynamic> delete(String path) =>
      _send(() => dio.delete<dynamic>(path));

  Future<dynamic> upload(
    String path, {
    required String filePath,
    required String fileName,
    Map<String, dynamic>? query,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    return _send(
      () => dio.post<dynamic>(path, data: form, queryParameters: _clean(query)),
    );
  }

  Future<DownloadedFile> download(
    String path, {
    Map<String, dynamic>? query,
    required String fallbackName,
  }) async {
    final res = await _raw(
      () => dio.get<List<int>>(
        path,
        queryParameters: _clean(query),
        options: Options(responseType: ResponseType.bytes),
      ),
    );
    final cd = res.headers.value('content-disposition') ?? '';
    final match = RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
    return DownloadedFile(
      Uint8List.fromList(res.data ?? const []),
      match?.group(1) ?? fallbackName,
    );
  }

  Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    final out = <String, dynamic>{};
    query.forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) out[k] = v.toString();
    });
    return out;
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() call) async {
    final res = await _raw(call);
    return res.data;
  }

  Future<Response<T>> _raw<T>(Future<Response<T>> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  ApiException _toApiException(DioException e) {
    final res = e.response;
    if (res == null) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown) {
        return ApiException(
          'Serveur injoignable. Vérifiez la connexion VPN et l’adresse du serveur.',
        );
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        return ApiException('Le serveur met trop de temps à répondre.');
      }
      return ApiException(e.message ?? 'Erreur réseau');
    }
    final status = res.statusCode;
    if (status == 401) {
      onUnauthorized();
      return ApiException('Session expirée, reconnectez-vous.', status: 401);
    }
    return ApiException(_bodyMessage(res.data) ?? 'Erreur HTTP $status',
        status: status);
  }

  String? _bodyMessage(Object? data) {
    if (data is Map && data['message'] != null) {
      final m = data['message'];
      if (m is List) return m.join(', ');
      return m.toString();
    }
    if (data is String && data.isNotEmpty && data.length < 300) return data;
    return null;
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl = ref.watch(apiUrlProvider);
  return ApiClient(
    baseUrl: baseUrl,
    tokens: ref.watch(tokenStoreProvider),
    onUnauthorized: ref.watch(unauthorizedHandlerProvider).call,
  );
});
