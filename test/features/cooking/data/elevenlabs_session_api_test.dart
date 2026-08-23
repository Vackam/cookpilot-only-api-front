import 'dart:async';
import 'dart:convert';

import 'package:cookpilot/features/cooking/data/elevenlabs_session_api.dart';
import 'package:cookpilot/features/user/data/beta_user_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const baseUrl = 'http://example.test';
  const userId = '90000000-0000-0000-0000-000000000001';

  setUp(() {
    BetaUserSession.setCurrentUser(
      const BetaUser(id: userId, displayName: '베타 사용자', betaNumber: 1),
    );
  });

  tearDown(BetaUserSession.clear);

  test('베타 사용자 헤더로 토큰 엔드포인트를 호출하고 token을 돌려준다', () async {
    final api = ElevenLabsSessionApi(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          '$baseUrl/api/v1/ai-sessions/elevenlabs',
        );
        expect(request.headers[cookPilotUserIdHeader], userId);
        return _jsonResponse('{"token": "convtoken-abc"}');
      }),
    );

    expect(await api.fetchConversationToken(), 'convtoken-abc');
  });

  test('200이 아닌 응답은 상태 코드를 보존한다', () async {
    final api = ElevenLabsSessionApi(
      baseUrl: baseUrl,
      client: MockClient((_) async => http.Response('no key', 409)),
    );

    await expectLater(
      api.fetchConversationToken(),
      throwsA(
        isA<ElevenLabsSessionApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          409,
        ),
      ),
    );
  });

  test('JSON이 아니거나 token이 없으면 형식 오류로 처리한다', () async {
    final responses = <String>['not-json', '{"token": "  "}'];
    var requestIndex = 0;
    final api = ElevenLabsSessionApi(
      baseUrl: baseUrl,
      client: MockClient((_) async => _jsonResponse(responses[requestIndex++])),
    );

    await expectLater(
      api.fetchConversationToken(),
      throwsA(isA<ElevenLabsSessionApiException>()),
    );
    await expectLater(
      api.fetchConversationToken(),
      throwsA(isA<ElevenLabsSessionApiException>()),
    );
  });

  test('응답 시간 초과는 API 예외로 변환한다', () async {
    final pending = Completer<http.Response>();
    final api = ElevenLabsSessionApi(
      baseUrl: baseUrl,
      timeout: const Duration(milliseconds: 1),
      client: MockClient((_) => pending.future),
    );

    await expectLater(
      api.fetchConversationToken(),
      throwsA(
        isA<ElevenLabsSessionApiException>().having(
          (error) => error.message,
          'message',
          contains('초과'),
        ),
      ),
    );
  });
}

http.Response _jsonResponse(String body) {
  return http.Response.bytes(
    utf8.encode(body),
    200,
    headers: const <String, String>{'Content-Type': 'application/json'},
  );
}
