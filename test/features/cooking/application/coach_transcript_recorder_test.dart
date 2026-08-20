import 'package:cookpilot/features/cooking/application/coach_transcript_recorder.dart';
import 'package:cookpilot/features/cooking/application/coach_transcript_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cooking_fakes.dart';

void main() {
  const sessionId = '40000000-0000-0000-0000-000000000001';
  // 실제 지연으로 검증한다. 대기 여유를 크게 둬 CI 지터에 흔들리지 않게 한다.
  const debounce = Duration(milliseconds: 100);
  const beforeDebounce = Duration(milliseconds: 20);
  const afterDebounce = Duration(milliseconds: 400);

  CoachTranscriptRecorder buildRecorder(FakeCoachTranscriptStore store) =>
      CoachTranscriptRecorder(
        sessionId: sessionId,
        store: store,
        debounce: debounce,
      );

  test('발화가 멈춘 뒤 한 번만 저장한다', () async {
    final store = FakeCoachTranscriptStore();
    final recorder = buildRecorder(store)
      ..record(const CoachTranscriptTurn.user('타이머 3분 맞춰줘'))
      ..record(const CoachTranscriptTurn.coach('3분 타이머를 시작했어요.'));

    await Future<void>.delayed(beforeDebounce);
    expect(store.saved, isEmpty);

    await Future<void>.delayed(afterDebounce);

    expect(store.saved, hasLength(1));
    expect(store.saved.single.turns, <CoachTranscriptTurn>[
      const CoachTranscriptTurn.user('타이머 3분 맞춰줘'),
      const CoachTranscriptTurn.coach('3분 타이머를 시작했어요.'),
    ]);
    recorder.dispose();
  });

  test('flush는 debounce를 기다리지 않는다', () async {
    final store = FakeCoachTranscriptStore();
    final recorder = buildRecorder(store)
      ..record(const CoachTranscriptTurn.user('불 세기 낮췄어요'));

    await recorder.flush();

    expect(store.saved, hasLength(1));
    expect(store.saved.single.sessionId, sessionId);
    recorder.dispose();
  });

  test('빈 발화는 버리고 앞뒤 공백은 잘라 저장한다', () async {
    final store = FakeCoachTranscriptStore();
    final recorder = buildRecorder(store)
      ..record(const CoachTranscriptTurn.user('   '))
      ..record(const CoachTranscriptTurn.coach('  네, 알겠습니다.  '));

    await recorder.flush();

    expect(store.saved.single.turns, <CoachTranscriptTurn>[
      const CoachTranscriptTurn.coach('네, 알겠습니다.'),
    ]);
    recorder.dispose();
  });

  test('요약은 누적하지 않고 최신 하나만 들고 있는다', () async {
    final store = FakeCoachTranscriptStore();
    final recorder = buildRecorder(store)
      ..recordSummary('양파 대신 대파 사용')
      ..recordSummary('양파 대신 대파 사용, 불 세기 중약불');

    await recorder.flush();

    expect(recorder.summary, '양파 대신 대파 사용, 불 세기 중약불');
    expect(store.saved.single.summary, '양파 대신 대파 사용, 불 세기 중약불');
    recorder.dispose();
  });

  test('재료 대체는 같은 재료를 다시 바꾸면 최신 하나만 남는다', () async {
    final store = FakeCoachTranscriptStore();
    final recorder = buildRecorder(store)
      ..recordSubstitution('갈비', '삼겹살')
      ..recordSubstitution(' 갈비 ', ' 대패 삼겹살 ')
      ..recordSubstitution('양파', '파')
      ..recordSubstitution('', '무시')
      ..recordSubstitution('마늘', '  ');

    await recorder.flush();

    expect(recorder.substitutions, <String, String>{'갈비': '대패 삼겹살', '양파': '파'});
    expect(store.saved.single.substitutions, <String, String>{
      '갈비': '대패 삼겹살',
      '양파': '파',
    });
    recorder.dispose();
  });

  test('재료 대체 상한을 넘으면 새 대체를 무시하고 기존을 지킨다', () async {
    final store = FakeCoachTranscriptStore();
    final recorder = buildRecorder(store);
    for (var i = 0; i < CoachTranscript.maxSubstitutions; i += 1) {
      recorder.recordSubstitution('재료$i', '대체$i');
    }
    recorder.recordSubstitution('마지막 재료', '무시될 대체');

    expect(recorder.substitutions, hasLength(CoachTranscript.maxSubstitutions));
    expect(recorder.substitutions.containsKey('마지막 재료'), isFalse);
    // 상한에 닿아도 이미 확정된 재료를 다시 바꾸는 것은 막지 않는다.
    recorder.recordSubstitution('재료0', '다시 바꾼 대체');
    expect(recorder.substitutions['재료0'], '다시 바꾼 대체');
    recorder.dispose();
  });

  test('recentTurns는 뒤에서 요청한 수만큼만 준다', () async {
    final store = FakeCoachTranscriptStore();
    final recorder = buildRecorder(store);
    for (var index = 0; index < 5; index++) {
      recorder.record(CoachTranscriptTurn.user('$index번째'));
    }

    expect(recorder.recentTurns(2), <CoachTranscriptTurn>[
      const CoachTranscriptTurn.user('3번째'),
      const CoachTranscriptTurn.user('4번째'),
    ]);
    expect(recorder.recentTurns(50), hasLength(5));
    recorder.dispose();
  });

  test('상한을 넘으면 오래된 턴부터 버린다', () async {
    final store = FakeCoachTranscriptStore();
    final recorder = buildRecorder(store);
    for (var index = 0; index < CoachTranscript.maxTurns + 3; index++) {
      recorder.record(CoachTranscriptTurn.user('$index번째'));
    }

    await recorder.flush();

    final saved = store.saved.single.turns;
    expect(saved, hasLength(CoachTranscript.maxTurns));
    expect(saved.first, const CoachTranscriptTurn.user('3번째'));
    recorder.dispose();
  });

  test('같은 세션의 저장 로그를 복원해 앞에 이어 붙인다', () async {
    final store = FakeCoachTranscriptStore(
      stored: const CoachTranscript(
        sessionId: sessionId,
        turns: <CoachTranscriptTurn>[CoachTranscriptTurn.user('지난 발화')],
        summary: '지난 요약',
        substitutions: <String, String>{'양파': '파'},
      ),
    );
    final recorder = buildRecorder(store);
    final restore = recorder.restore();
    recorder.record(const CoachTranscriptTurn.user('복원 중 들어온 발화'));
    await restore;

    expect(recorder.summary, '지난 요약');
    expect(recorder.substitutions, <String, String>{'양파': '파'});
    expect(recorder.recentTurns(10), <CoachTranscriptTurn>[
      const CoachTranscriptTurn.user('지난 발화'),
      const CoachTranscriptTurn.user('복원 중 들어온 발화'),
    ]);
    recorder.dispose();
  });

  test('다른 조리 세션의 로그는 복원하지 않고 지운다', () async {
    final store = FakeCoachTranscriptStore(
      stored: const CoachTranscript(
        sessionId: '40000000-0000-0000-0000-000000000009',
        turns: <CoachTranscriptTurn>[CoachTranscriptTurn.user('지난 조리 발화')],
      ),
    );
    final recorder = buildRecorder(store);

    await recorder.restore();

    expect(recorder.isEmpty, isTrue);
    expect(store.clearCount, 1);
    recorder.dispose();
  });

  test('clear 뒤에는 늦은 발화도 debounce도 로그를 되살리지 못한다', () async {
    final store = FakeCoachTranscriptStore();
    final recorder = buildRecorder(store)
      ..record(const CoachTranscriptTurn.user('조리 중 발화'))
      ..recordSubstitution('갈비', '대패 삼겹살');

    await recorder.clear();
    recorder
      ..record(const CoachTranscriptTurn.coach('완료 뒤 늦게 도착한 발화'))
      ..recordSubstitution('양파', '파');
    await Future<void>.delayed(afterDebounce);
    await recorder.flush();

    expect(store.clearCount, 1);
    expect(store.saved, isEmpty);
    expect(recorder.isEmpty, isTrue);
    expect(recorder.substitutions, isEmpty);
    recorder.dispose();
  });

  test('저장 실패는 삼키고 다음 flush가 다시 시도한다', () async {
    final store = FakeCoachTranscriptStore(failSave: true);
    final recorder = buildRecorder(store)
      ..record(const CoachTranscriptTurn.user('저장 실패 발화'));

    await recorder.flush();
    expect(store.saveAttempts, 1);

    store.failSave = false;
    await recorder.flush();

    expect(store.saveAttempts, 2);
    expect(store.saved.single.turns, <CoachTranscriptTurn>[
      const CoachTranscriptTurn.user('저장 실패 발화'),
    ]);
    recorder.dispose();
  });
}
