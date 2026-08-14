import 'dart:convert';

import 'package:cookpilot/features/cooking/domain/cooking_setup_snapshot.dart';
import 'package:cookpilot/features/mvp/cook_flow_screens.dart';
import 'package:cookpilot/features/recipe/domain/recipe.dart';
import 'package:cookpilot/features/review/application/pending_review_draft_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 예전에는 작성 중인 후기가 있으면 새 조리를 막고 후기 화면으로 보냈다.
  // 후기를 쓸지는 사용자가 정할 일이라 그 차단을 걷어냈고, 남은 초안은 홈의
  // "후기 작성 이어가기" 카드가 알린다.
  testWidgets('작성 중인 후기가 있어도 새 조리를 막지 않는다', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'flutter.${PendingReviewDraftStore.storageKey}': jsonEncode(
        _buildDraft().toJson(),
      ),
    });
    var cookingRouteBuilds = 0;

    await _pumpSetup(
      tester,
      cookSessionScreenBuilder: (_) {
        cookingRouteBuilds += 1;
        return const Scaffold(body: Text('새 조리 화면'));
      },
    );
    await tester.tap(find.text('이 설정으로 조리 시작'));
    await tester.pumpAndSettle();

    expect(cookingRouteBuilds, 1);
    expect(find.text('새 조리 화면'), findsOneWidget);
    expect(find.text('작성 중인 후기를 먼저 이어갈게요.'), findsNothing);
    // 초안을 지우지도 않는다. 홈 카드가 계속 알려야 하기 때문이다.
    expect(await PendingReviewDraftStore().load(), isNotNull);
  });

  testWidgets('중복 탭은 조리 화면을 한 번만 연다', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    var cookingRouteBuilds = 0;

    await _pumpSetup(
      tester,
      cookSessionScreenBuilder: (_) {
        cookingRouteBuilds += 1;
        return const Scaffold(body: Text('새 조리 화면'));
      },
    );
    final startButton = find.text('이 설정으로 조리 시작');
    await tester.tap(startButton);
    await tester.tap(startButton);
    await tester.pumpAndSettle();

    expect(cookingRouteBuilds, 1);
    expect(find.text('새 조리 화면'), findsOneWidget);
  });
}

Future<void> _pumpSetup(
  WidgetTester tester, {
  WidgetBuilder? cookSessionScreenBuilder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CookSetupScreen(
        recipe: _recipe,
        cookSessionScreenBuilder: cookSessionScreenBuilder,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PendingReviewDraft _buildDraft() {
  return PendingReviewDraft(
    clientSessionId: '31000000-0000-0000-0000-000000000001',
    cookedAt: DateTime.utc(2026, 7, 31, 9),
    setupSnapshot: _buildSetupSnapshot(),
    timerSecondsByStep: const {0: 60},
    rating: 4,
    comment: '작성 중인 후기',
    nextTimeNote: '다음에는 약불',
    approvedPersonalVersionCreation: true,
  );
}

CookingSetupSnapshot _buildSetupSnapshot() {
  return CookingSetupSnapshot(
    recipeId: _recipe.id,
    title: _recipe.title,
    description: _recipe.description,
    imageUrl: _recipe.imageUrl,
    baseServings: _recipe.baseServings,
    targetServings: 2,
    source: CookingRecipeSource.base,
    personalVersionId: null,
    ingredients: const [],
    steps: const [
      CookingSetupStep(
        originalStepId: '33000000-0000-0000-0000-000000000001',
        stepIndex: 0,
        instruction: '두부를 굽는다.',
        timerSeconds: 60,
        cautionNote: null,
        imageUrl: '',
      ),
    ],
  );
}

const _recipe = Recipe(
  id: '32000000-0000-0000-0000-000000000001',
  title: '두부 구이',
  description: '조리 진입 테스트',
  baseServings: 2,
  imageUrl: '',
  ingredients: [],
  steps: [
    CookStep(
      originalStepId: '33000000-0000-0000-0000-000000000001',
      stepIndex: 0,
      instruction: '두부를 굽는다.',
      timerSeconds: 60,
      cautionNote: null,
      imageUrl: '',
    ),
  ],
  hasPersonalVersion: false,
);
