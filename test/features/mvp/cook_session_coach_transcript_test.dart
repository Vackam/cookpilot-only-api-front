import 'package:cookpilot/features/cooking/application/coach_transcript_store.dart';
import 'package:cookpilot/features/cooking/application/cooking_coach_controller.dart';
import 'package:cookpilot/features/cooking/application/cooking_ports.dart';
import 'package:cookpilot/features/cooking/application/cooking_session_store.dart';
import 'package:cookpilot/features/cooking/domain/cooking_session_state.dart';
import 'package:cookpilot/features/cooking/domain/cooking_setup_snapshot.dart';
import 'package:cookpilot/features/mvp/cook_flow_screens.dart';
import 'package:cookpilot/features/recipe/domain/recipe.dart';
import 'package:cookpilot/features/review/application/pending_review_draft_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/cooking_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sessionId = '40000000-0000-0000-0000-000000000031';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('조리를 완료하면 저장된 코치 대화 전사본을 지운다', (tester) async {
    final transcriptStore = FakeCoachTranscriptStore(
      stored: const CoachTranscript(
        sessionId: sessionId,
        turns: <CoachTranscriptTurn>[
          CoachTranscriptTurn.user('양파 대신 대파 써도 돼요?'),
        ],
        summary: '양파 대신 대파 사용',
      ),
    );

    await _pumpCookSession(tester, transcriptStore: transcriptStore);
    await tester.tap(find.text('조리 완료'));
    await _pumpAsyncWork(tester);

    expect(find.byType(ReviewScreen), findsOneWidget);
    expect(transcriptStore.clearCount, 1);
    expect(transcriptStore.stored, isNull);
  });

  testWidgets('코치를 다시 켜면 현재 상태·요약·직전 대화를 갈라서 재주입한다', (tester) async {
    final transcriptStore = FakeCoachTranscriptStore(
      stored: const CoachTranscript(
        sessionId: sessionId,
        turns: <CoachTranscriptTurn>[
          CoachTranscriptTurn.user('양파 대신 대파 써도 돼요?'),
          CoachTranscriptTurn.coach('네, 단맛이 줄어드니 조금 더 넣으세요.'),
        ],
        summary: '양파 대신 대파 사용. 불 세기를 중약불로 낮춤.',
      ),
    );
    late FakeCoachEngine coach;

    await _pumpCookSession(
      tester,
      transcriptStore: transcriptStore,
      coachFactory: (onStateChanged, buildPrompt) => coach = FakeCoachEngine(
        onStateChanged: onStateChanged,
        buildPrompt: buildPrompt,
      ),
    );
    await _startCoach(tester);

    final prompt = coach.startPrompts.single;
    expect(prompt, contains('[현재 상태 — 이것이 사실이다]'));
    expect(prompt, contains('사용자는 지금 1단계를 진행 중입니다'));
    expect(prompt, contains('타이머: 이 단계에는 타이머가 없음'));
    expect(prompt, contains('[지난 대화 — 참고용, 위 현재 상태와 어긋나면 위를 따른다]'));
    expect(prompt, contains('처음부터 인사하지 말고 바로 이어서 도와주세요'));
    expect(prompt, contains('양파 대신 대파 사용. 불 세기를 중약불로 낮춤.'));
    expect(prompt, contains('사용자: 양파 대신 대파 써도 돼요?'));
    expect(prompt, contains('코치: 네, 단맛이 줄어드니 조금 더 넣으세요.'));
    // 상태가 대화보다 먼저 와야 충돌 시 상태를 따르라는 지시가 성립한다.
    expect(
      prompt.indexOf('[현재 상태 — 이것이 사실이다]'),
      lessThan(prompt.indexOf('[지난 대화')),
    );
  });

  testWidgets('지난 대화가 없으면 재개 블록을 붙이지 않는다', (tester) async {
    late FakeCoachEngine coach;

    await _pumpCookSession(
      tester,
      transcriptStore: FakeCoachTranscriptStore(),
      coachFactory: (onStateChanged, buildPrompt) => coach = FakeCoachEngine(
        onStateChanged: onStateChanged,
        buildPrompt: buildPrompt,
      ),
    );
    await _startCoach(tester);

    final prompt = coach.startPrompts.single;
    expect(prompt, contains('[현재 상태 — 이것이 사실이다]'));
    expect(prompt, isNot(contains('[지난 대화')));
  });

  testWidgets('확정된 재료 대체는 참고용 대화가 아니라 현재 상태의 재료 목록에 들어간다', (tester) async {
    final transcriptStore = FakeCoachTranscriptStore(
      stored: const CoachTranscript(
        sessionId: sessionId,
        substitutions: <String, String>{'갈비': '대패 삼겹살', '다진 마늘': '마늘가루'},
      ),
    );
    late FakeCoachEngine coach;

    await _pumpCookSession(
      tester,
      transcriptStore: transcriptStore,
      coachFactory: (onStateChanged, buildPrompt) => coach = FakeCoachEngine(
        onStateChanged: onStateChanged,
        buildPrompt: buildPrompt,
      ),
    );
    await _startCoach(tester);

    final prompt = coach.startPrompts.single;
    expect(prompt, contains('재료 (이번 조리 확정본):'));
    expect(prompt, contains('- 대패 삼겹살 300g ← 갈비 대체'));
    expect(prompt, contains('- 양파 1개 (선택)'));
    // 레시피 표기와 정확히 맞지 않는 이름으로 온 대체도 빠뜨리지 않는다.
    expect(prompt, contains('- 마늘가루 ← 다진 마늘 대체'));
    // 대체만 있으면 재개 블록이 붙지 않는다 — 대체는 대화가 아니라 상태다.
    expect(prompt, isNot(contains('[지난 대화')));
    expect(
      prompt.indexOf('[현재 상태 — 이것이 사실이다]'),
      lessThan(prompt.indexOf('- 대패 삼겹살 300g')),
    );
  });

  testWidgets('지난 조리 세션의 전사본은 이번 조리로 복원하지 않고 지운다', (tester) async {
    final transcriptStore = FakeCoachTranscriptStore(
      stored: const CoachTranscript(
        sessionId: '40000000-0000-0000-0000-000000000099',
        turns: <CoachTranscriptTurn>[CoachTranscriptTurn.user('지난 조리 발화')],
      ),
    );

    await _pumpCookSession(tester, transcriptStore: transcriptStore);
    await _pumpAsyncWork(tester);

    expect(transcriptStore.clearCount, 1);
    expect(transcriptStore.stored, isNull);
  });
}

Future<void> _pumpCookSession(
  WidgetTester tester, {
  required CoachTranscriptGateway transcriptStore,
  CookingCoachEngine Function(
    CookingCoachStateHandler onStateChanged,
    String Function() buildRecipePrompt,
  )?
  coachFactory,
}) async {
  // 조리 화면은 ListView라 화면 밖 위젯이 element로 만들어지지 않는다. 코치
  // 버튼까지 한 화면에 들어오도록 크게 잡는다.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: CookSessionScreen(
        recipe: _recipe,
        servings: 2,
        setupSnapshot: _snapshot(),
        restoredSession: _restoredSession(),
        pendingReviewDraftStore: PendingReviewDraftStore(),
        cookingSessionStore: const CookingSessionStore(),
        coachTranscriptStore: transcriptStore,
        coachControllerFactory: coachFactory,
        alarm: const SilentTimerAlarm(),
      ),
    ),
  );
  await tester.pump();
}

/// 저장 로그 복원이 끝난 뒤에야 세션이 열린다. 프롬프트를 읽기 전에 비동기
/// 작업을 모두 흘려보낸다.
Future<void> _startCoach(WidgetTester tester) async {
  await _pumpAsyncWork(tester);
  await tester.ensureVisible(find.byKey(const Key('coach-toggle')));
  await tester.tap(find.byKey(const Key('coach-toggle')));
  await _pumpAsyncWork(tester);
}

Future<void> _pumpAsyncWork(WidgetTester tester) async {
  for (var i = 0; i < 5; i += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

PersistedCookingSession _restoredSession() {
  return PersistedCookingSession(
    sessionId: '40000000-0000-0000-0000-000000000031',
    recipeId: _recipe.id,
    recipeTitle: _recipe.title,
    servings: 2,
    setupSnapshot: _snapshot(),
    stepIndex: 0,
    sessionStatus: CookingSessionStatus.cooking.name,
    timerOriginalMs: 0,
    timerEffectiveMs: 0,
    timerRemainingMs: 0,
    timerStatus: TimerStatus.idle.name,
    savedAtEpochMs: 1000000,
  );
}

CookingSetupSnapshot _snapshot() {
  return CookingSetupSnapshot(
    recipeId: '10000000-0000-0000-0000-000000000031',
    title: '코치 대화 로그 테스트',
    description: '조리 완료 시 전사본 정리를 검증한다.',
    imageUrl: '',
    baseServings: 2,
    targetServings: 2,
    source: CookingRecipeSource.base,
    personalVersionId: null,
    ingredients: <CookingSetupIngredient>[],
    steps: const <CookingSetupStep>[
      CookingSetupStep(
        stepIndex: 0,
        instruction: '한 단계를 조리한다.',
        timerSeconds: 0,
        cautionNote: null,
        imageUrl: '',
      ),
    ],
  );
}

const _recipe = Recipe(
  id: '10000000-0000-0000-0000-000000000031',
  title: '코치 대화 로그 테스트',
  description: '조리 완료 시 전사본 정리를 검증한다.',
  baseServings: 2,
  imageUrl: '',
  ingredients: <Ingredient>[
    Ingredient(name: '갈비', amount: 300, unit: 'g', isRequired: true),
    Ingredient(name: '양파', amount: 1, unit: '개', isRequired: false),
  ],
  steps: <CookStep>[
    CookStep(
      stepIndex: 0,
      instruction: '한 단계를 조리한다.',
      timerSeconds: 0,
      cautionNote: null,
      imageUrl: '',
    ),
  ],
  hasPersonalVersion: false,
);
