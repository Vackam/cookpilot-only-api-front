import 'package:cookpilot/features/cooking/application/cooking_coach_controller.dart';
import 'package:cookpilot/features/cooking/application/timer_controller.dart';
import 'package:cookpilot/features/cooking/presentation/cooking_voice_session_controller.dart';
import 'package:cookpilot/features/mvp/cook_layouts/cook_layout.dart';
import 'package:cookpilot/features/mvp/cook_layouts/cook_layout_catalog.dart';
import 'package:cookpilot/features/mvp/cook_layouts/cook_session_view_model.dart';
import 'package:cookpilot/features/mvp/cook_layouts/layout_one_control.dart';
import 'package:cookpilot/features/mvp/mvp_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LocalTimerController timer;

  setUp(() {
    // autoTick을 끄면 테스트가 실제 초를 기다리지 않는다.
    timer = LocalTimerController(autoTick: false)
      ..reset(const Duration(minutes: 5), autoStart: false);
  });

  tearDown(() => timer.dispose());

  CookSessionViewModel buildViewModel({
    VoidCallback? onToggleSpeech,
    VoidCallback? onToggleTimer,
    VoidCallback? onToggleCoach,
    CookingCoachPhase coachPhase = CookingCoachPhase.idle,
    String? coachMessage,
    String? helpAnswer,
    String? finishError,
    String stepImageUrl = '',
  }) => CookSessionViewModel(
    recipeTitle: '배치 테스트 레시피',
    servings: 2,
    stepNumber: 2,
    stepCount: 3,
    stepTitle: '김치 볶기',
    stepDescription: '돼지고기가 익으면 김치를 넣고 센 불에서 5분간 더 볶아요.',
    stepImageUrl: stepImageUrl,
    timer: timer,
    hasTimer: true,
    timerActionLabel: () => '타이머 시작',
    speechPhase: CookingVoiceSpeechPhase.idle,
    speechIcon: Icons.mic_rounded,
    speechTitle: '음성으로 조리하기',
    speechBody: '단계 이동, 현재 안내, 타이머 조작을 말로 할 수 있어요.',
    speechButtonLabel: '말하기',
    coachPhase: coachPhase,
    coachMessage: coachMessage,
    helpLoading: false,
    helpAnswer: helpAnswer,
    helpRequestInFlight: false,
    finishing: false,
    locked: false,
    finishError: finishError,
    onClose: () {},
    onToggleTimer: onToggleTimer ?? () {},
    onAddMinute: () {},
    onResetTimer: () {},
    onToggleSpeech: onToggleSpeech ?? () {},
    onAskHelp: () {},
    onToggleCoach: onToggleCoach ?? () {},
    onAdvance: () {},
    onPrevStep: () {},
  );

  Future<void> pumpLayout(
    WidgetTester tester,
    CookLayout layout,
    CookSessionViewModel vm, {
    // 기본 배치는 세로 목록이라 좁고 짧은 화면에서는 아래쪽 버튼이 아예
    // 만들어지지 않고, 원 컨트롤은 가로 2단이라 폭이 필요하다. 계약 검증이
    // 화면 크기에 좌우되지 않도록 둘 다 넉넉한 상자를 기본값으로 둔다.
    Size size = const Size(1400, 2400),
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) => layout.build(context, vm)),
      ),
    );
  }

  // 배치를 갈아끼워도 지켜야 하는 계약. 조리 화면 위젯 테스트 전부가 이 키와
  // 문구에 걸려 있어서, 새 배치가 하나라도 빠뜨리면 여기서 먼저 걸린다.
  group('모든 배치가 지키는 계약', () {
    for (final layout in cookLayoutCatalog) {
      testWidgets('${layout.label}은 음성·도움·코치 조작과 단계 표시를 모두 노출한다', (
        tester,
      ) async {
        await pumpLayout(tester, layout, buildViewModel());

        expect(find.byKey(const Key('voice-input-toggle')), findsOneWidget);
        expect(find.byKey(const Key('voice-input-status')), findsOneWidget);
        expect(find.byKey(const Key('help-request')), findsOneWidget);
        expect(find.byKey(const Key('coach-toggle')), findsOneWidget);
        expect(find.byKey(const Key('ai-data-disclosure')), findsOneWidget);
        expect(find.text('2 / 3 단계'), findsOneWidget);
        expect(find.text('다음 단계'), findsOneWidget);
      });
    }

    test('배치 id가 겹치지 않는다', () {
      final ids = cookLayoutCatalog.map((layout) => layout.id).toSet();
      expect(ids.length, cookLayoutCatalog.length);
    });

    test('기본 배치는 카탈로그에 들어 있다', () {
      expect(cookLayoutCatalog, contains(defaultCookLayout));
    });
  });

  group('원 컨트롤 배치', () {
    // Galaxy A52s를 가로로 눕혔을 때의 논리 크기.
    const landscape = Size(892, 412);

    testWidgets('원을 탭하면 코치 토글, 길게 누르면 타이머가 움직인다', (tester) async {
      var coachToggles = 0;
      var timerToggles = 0;
      await pumpLayout(
        tester,
        const OneControlCookLayout(),
        buildViewModel(
          onToggleCoach: () => coachToggles++,
          onToggleTimer: () => timerToggles++,
        ),
        size: landscape,
      );

      final ring = find.byKey(const Key('coach-toggle'));
      await tester.tap(ring);
      await tester.pump();
      expect(coachToggles, 1);
      expect(timerToggles, 0);

      await tester.longPress(ring);
      await tester.pump();
      expect(coachToggles, 1);
      expect(timerToggles, 1);
    });

    // 코치가 살아 있는 동안에는 STT가 코치 음성을 받아 적으므로, 조리 화면도
    // 말하기를 잠근다. 잠그지 않으면 코치와 마이크가 서로를 먹는다.
    testWidgets('코치가 켜져 있으면 말하기 버튼을 잠근다', (tester) async {
      await pumpLayout(
        tester,
        const OneControlCookLayout(),
        buildViewModel(coachPhase: CookingCoachPhase.live),
        size: landscape,
      );

      final speech = tester.widget<InkWell>(
        find.byKey(const Key('voice-input-toggle')),
      );
      expect(speech.onTap, isNull);
    });

    testWidgets('코치가 꺼져 있으면 말하기 버튼이 살아 있다', (tester) async {
      var speechToggles = 0;
      await pumpLayout(
        tester,
        const OneControlCookLayout(),
        buildViewModel(onToggleSpeech: () => speechToggles++),
        size: landscape,
      );

      await tester.tap(find.byKey(const Key('voice-input-toggle')));
      await tester.pump();
      expect(speechToggles, 1);
    });

    testWidgets('남은 시간이 조작 원 안에 함께 나온다', (tester) async {
      await pumpLayout(
        tester,
        const OneControlCookLayout(),
        buildViewModel(),
        size: landscape,
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('coach-toggle')),
          matching: find.text('05:00'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('크게 보기를 누르면 확대 화면이 열린다', (tester) async {
      // 원본이 칸보다 작은 사진이 있어서, 조리 화면에서는 작게 놓인다.
      // 확대 경로가 없으면 그 사진은 끝까지 작게만 보인다.
      await pumpLayout(
        tester,
        const OneControlCookLayout(),
        buildViewModel(stepImageUrl: 'https://example.test/step.png'),
        size: landscape,
      );

      await tester.tap(find.byKey(const Key('photo-zoom')));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);

      await tester.tap(find.byKey(const Key('photo-zoom-close')));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    });

    testWidgets('사진이 없으면 크게 보기를 잠근다', (tester) async {
      await pumpLayout(
        tester,
        const OneControlCookLayout(),
        buildViewModel(),
        size: landscape,
      );

      await tester.tap(find.byKey(const Key('photo-zoom')));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    });

    testWidgets('작은 휴대폰 화면에서 안내가 겹쳐도 넘치지 않는다', (tester) async {
      // 오른쪽 패널이 좁아서 안내가 겹치면 가장 먼저 넘친다.
      // 안내 세 개가 한꺼번에 뜨는 최악의 경우를 실제 가로 화면 크기로 확인한다.
      await pumpLayout(
        tester,
        const OneControlCookLayout(),
        buildViewModel(
          coachMessage: '코치와 연결됐어요.',
          helpAnswer: '기름이 튀지 않도록 불을 중간으로 낮추고 뚜껑을 살짝 덮어 주세요.',
          finishError: '완료 정보를 저장하지 못했어요. 잠시 뒤 다시 시도해 주세요.',
        ),
        size: landscape,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('사진을 잘라 채우지도, 원본보다 늘리지도 않는다', (tester) async {
      await pumpLayout(
        tester,
        const OneControlCookLayout(),
        buildViewModel(),
        size: landscape,
      );

      // 끄면 조리에 필요한 부분이 잘려 나가거나, 늘어나면서 뭉개진다.
      final photo = tester.widget<FoodImage>(
        find.byKey(const Key('cook-step-photo')),
      );
      expect(photo.neverUpscale, isTrue);
    });
  });
}
