import 'dart:convert';

import 'package:cookpilot/features/cooking/application/coach_transcript_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CoachTranscriptStore', () {
    const store = CoachTranscriptStore();
    const sessionId = '40000000-0000-0000-0000-000000000001';

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('저장한 대화 로그와 요약을 그대로 되돌려준다', () async {
      await store.save(
        const CoachTranscript(
          sessionId: sessionId,
          turns: <CoachTranscriptTurn>[
            CoachTranscriptTurn.user('양파 대신 대파 써도 돼요?'),
            CoachTranscriptTurn.coach('네, 단맛이 줄어드니 조금 더 넣으세요.'),
          ],
          summary: '양파 대신 대파 사용',
        ),
      );

      final loaded = await store.load();

      expect(loaded, isNotNull);
      expect(loaded!.sessionId, sessionId);
      expect(loaded.summary, '양파 대신 대파 사용');
      expect(loaded.turns, <CoachTranscriptTurn>[
        const CoachTranscriptTurn.user('양파 대신 대파 써도 돼요?'),
        const CoachTranscriptTurn.coach('네, 단맛이 줄어드니 조금 더 넣으세요.'),
      ]);
    });

    test('확정된 재료 대체도 함께 왕복한다', () async {
      await store.save(
        const CoachTranscript(
          sessionId: sessionId,
          substitutions: <String, String>{'갈비': '대패 삼겹살', '양파': '파'},
        ),
      );

      final loaded = await store.load();

      expect(loaded!.substitutions, <String, String>{
        '갈비': '대패 삼겹살',
        '양파': '파',
      });
    });

    test('재료 대체 항목이 손상되면 로그 전체를 버린다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CoachTranscriptStore.storageKey: jsonEncode(<String, Object>{
          'sessionId': sessionId,
          'turns': <Object>[],
          'substitutions': <String, Object>{'갈비': 3},
        }),
      });

      expect(await store.load(), isNull);
    });

    test('재료 대체 상한을 넘긴 저장값은 복원하지 않는다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CoachTranscriptStore.storageKey: jsonEncode(<String, Object>{
          'sessionId': sessionId,
          'turns': <Object>[],
          'substitutions': <String, String>{
            for (var i = 0; i <= CoachTranscript.maxSubstitutions; i += 1)
              '재료$i': '대체$i',
          },
        }),
      });

      expect(await store.load(), isNull);
    });

    test('저장값이 없으면 null이다', () async {
      expect(await store.load(), isNull);
    });

    test('손상된 JSON은 null로 읽고 함께 정리한다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CoachTranscriptStore.storageKey: '{not json',
      });

      expect(await store.load(), isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get(CoachTranscriptStore.storageKey), isNull);
    });

    test('턴 하나가 손상되면 로그 전체를 버린다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CoachTranscriptStore.storageKey: jsonEncode(<String, Object>{
          'sessionId': sessionId,
          'turns': <Object>[
            <String, Object>{'isUser': true, 'text': '불 세기 낮췄어요'},
            <String, Object>{'isUser': true},
          ],
        }),
      });

      expect(await store.load(), isNull);
    });

    test('상한을 넘긴 저장값은 복원하지 않는다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CoachTranscriptStore.storageKey: jsonEncode(<String, Object>{
          'sessionId': sessionId,
          'turns': List<Object>.generate(
            CoachTranscript.maxTurns + 1,
            (index) => <String, Object>{'isUser': true, 'text': '$index'},
          ),
        }),
      });

      expect(await store.load(), isNull);
    });

    test('clear 뒤에는 남는 값이 없다', () async {
      await store.save(
        const CoachTranscript(
          sessionId: sessionId,
          turns: <CoachTranscriptTurn>[CoachTranscriptTurn.user('센 불로 갈게요')],
        ),
      );

      await store.clear();

      expect(await store.load(), isNull);
    });
  });
}
