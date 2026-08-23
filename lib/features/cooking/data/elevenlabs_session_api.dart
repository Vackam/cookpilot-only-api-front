import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/api/api_config.dart';
import '../../user/data/beta_user_repository.dart';

final class ElevenLabsSessionApiException implements Exception {
  const ElevenLabsSessionApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// ElevenLabs 코치 세션용 conversation token을 백엔드에서 발급받는다.
///
/// ElevenLabs API 키와 agent ID는 앱에 포함하지 않는다 — 에이전트는 private이고,
/// 이 어댑터가 받아온 단기 토큰만이 세션 연결 수단이다.
final class ElevenLabsSessionApi {
  ElevenLabsSessionApi({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? cookPilotApiBaseUrl();

  final http.Client _client;
  final String _baseUrl;
  final Duration timeout;

  Future<String> fetchConversationToken() async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl/api/v1/ai-sessions/elevenlabs'),
            headers: BetaUserSession.requestHeaders,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ElevenLabsSessionApiException('서버 응답 시간이 초과되었습니다.');
    } on http.ClientException {
      throw const ElevenLabsSessionApiException('서버에 연결하지 못했습니다.');
    }

    if (response.statusCode != 200) {
      throw ElevenLabsSessionApiException(
        '코치 세션 토큰을 발급받지 못했습니다. (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    return _decodeToken(response.bodyBytes);
  }
}

String _decodeToken(List<int> bodyBytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bodyBytes));
  } on FormatException {
    throw const ElevenLabsSessionApiException('코치 세션 토큰 형식이 올바르지 않습니다.');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const ElevenLabsSessionApiException('코치 세션 토큰 형식이 올바르지 않습니다.');
  }
  final token = decoded['token'];
  if (token is! String || token.trim().isEmpty) {
    throw const ElevenLabsSessionApiException('코치 세션 토큰 형식이 올바르지 않습니다.');
  }
  return token;
}
