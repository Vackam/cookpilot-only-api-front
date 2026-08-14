import 'dart:async';

import 'package:cookpilot/app/app_theme.dart';
import 'package:cookpilot/features/cooking/application/cooking_session_store.dart';
import 'package:cookpilot/features/cooking/domain/cooking_setup_snapshot.dart';
import 'package:cookpilot/features/mvp/main_shell.dart';
import 'package:cookpilot/features/recipe/data/recipe_api.dart';
import 'package:cookpilot/features/recipe/domain/recipe.dart';
import 'package:cookpilot/features/review/application/pending_review_draft_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('저장된 후기 초안이 있으면 홈에 후기 작성 이어가기를 표시한다', (tester) async {
    final draft = _buildDraft();

    await _pumpHome(tester, pendingReviewDraftLoader: () async => draft);

    expect(find.text('후기 작성 이어가기'), findsOneWidget);
    expect(find.text(draft.setupSnapshot.title), findsOneWidget);
  });

  testWidgets('후기 초안과 활성 조리 세션이 함께 있으면 후기만 표시한다', (tester) async {
    final draft = _buildDraft();
    var cookingSessionLoadAttempts = 0;

    await _pumpHome(
      tester,
      pendingReviewDraftLoader: () async => draft,
      cookingSessionLoader: () async {
        cookingSessionLoadAttempts += 1;
        return _buildActiveSession();
      },
    );

    expect(find.text('후기 작성 이어가기'), findsOneWidget);
    expect(find.text('이어서 요리하기'), findsNothing);
    expect(cookingSessionLoadAttempts, 0);
  });

  testWidgets('활성 세션 조회 중 새 후기 초안이 생기면 후기를 우선 표시한다', (tester) async {
    final activeLoad = Completer<PersistedCookingSession?>();
    final draft = _buildDraft();
    var pendingLoadAttempts = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCookPilotTheme(),
        home: HomeScreen(
          recipeRepository: _EmptyRecipeRepository(),
          pendingReviewDraftLoader: () async {
            pendingLoadAttempts += 1;
            return pendingLoadAttempts == 1 ? null : draft;
          },
          cookingSessionLoader: () => activeLoad.future,
        ),
      ),
    );
    await tester.pump();

    activeLoad.complete(_buildActiveSession());
    await tester.pumpAndSettle();

    expect(pendingLoadAttempts, 2);
    expect(find.text('후기 작성 이어가기'), findsOneWidget);
    expect(find.text('이어서 요리하기'), findsNothing);
  });

  testWidgets('활성 세션 조회 실패 중 새 후기 초안이 생겨도 후기를 우선 표시한다', (tester) async {
    final activeLoad = Completer<PersistedCookingSession?>();
    final draft = _buildDraft();
    var pendingLoadAttempts = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCookPilotTheme(),
        home: HomeScreen(
          recipeRepository: _EmptyRecipeRepository(),
          pendingReviewDraftLoader: () async {
            pendingLoadAttempts += 1;
            return pendingLoadAttempts == 1 ? null : draft;
          },
          cookingSessionLoader: () => activeLoad.future,
        ),
      ),
    );
    await tester.pump();

    activeLoad.completeError(StateError('active session read failure'));
    await tester.pumpAndSettle();

    expect(pendingLoadAttempts, 2);
    expect(find.text('후기 작성 이어가기'), findsOneWidget);
    expect(find.text('저장된 진행 상황을 불러오지 못했어요.'), findsNothing);
    expect(find.text('이어서 요리하기'), findsNothing);
  });

  testWidgets('후기 초안이 없고 활성 조리 세션만 있으면 조리 이어가기를 표시한다', (tester) async {
    await _pumpHome(
      tester,
      pendingReviewDraftLoader: () async => null,
      cookingSessionLoader: () async => _buildActiveSession(),
    );

    expect(find.text('후기 작성 이어가기'), findsNothing);
    expect(find.text('이어서 요리하기'), findsOneWidget);
    expect(find.text(_buildSetupSnapshot().title), findsOneWidget);
  });

  testWidgets('조리 재개 직전에도 초안이 없으면 기존 조리 화면을 연다', (tester) async {
    final activeSession = _buildActiveSession();
    PersistedCookingSession? receivedSession;

    await _pumpHome(
      tester,
      pendingReviewDraftLoader: () async => null,
      cookingSessionLoader: () async => activeSession,
      cookingScreenBuilder: (session, _) {
        receivedSession = session;
        return const Scaffold(body: Text('조리 재개 화면'));
      },
    );
    await tester.tap(find.text('이어서 요리하기'));
    await tester.pumpAndSettle();

    expect(receivedSession, same(activeSession));
    expect(find.text('조리 재개 화면'), findsOneWidget);
    expect(find.text('후기 작성 이어가기'), findsNothing);
  });

  testWidgets('조리 재개 카드 표시 뒤 초안이 생기면 후기를 먼저 연다', (tester) async {
    PendingReviewDraft? availableDraft;
    PendingReviewDraft? receivedDraft;
    var cookingRouteBuilds = 0;

    await _pumpHome(
      tester,
      pendingReviewDraftLoader: () async => availableDraft,
      cookingSessionLoader: () async => _buildActiveSession(),
      reviewScreenBuilder: (draft) {
        receivedDraft = draft;
        return const Scaffold(body: Text('후기 재개 화면'));
      },
      cookingScreenBuilder: (_, _) {
        cookingRouteBuilds += 1;
        return const Scaffold(body: Text('열리면 안 되는 조리 화면'));
      },
    );
    availableDraft = _buildDraft();

    await tester.tap(find.text('이어서 요리하기'));
    await tester.pumpAndSettle();

    expect(receivedDraft, same(availableDraft));
    expect(cookingRouteBuilds, 0);
    expect(find.text('후기 재개 화면'), findsOneWidget);
    expect(find.text('열리면 안 되는 조리 화면'), findsNothing);
    expect(find.text('작성 중인 후기를 먼저 이어갈게요.'), findsOneWidget);
  });

  testWidgets('조리 재개 직전 초안 조회 오류는 조리 화면을 열지 않는다', (tester) async {
    var pendingLoadAttempts = 0;
    var cookingRouteBuilds = 0;

    await _pumpHome(
      tester,
      pendingReviewDraftLoader: () async {
        pendingLoadAttempts += 1;
        if (pendingLoadAttempts > 2) {
          throw StateError('pending review read failure');
        }
        return null;
      },
      cookingSessionLoader: () async => _buildActiveSession(),
      cookingScreenBuilder: (_, _) {
        cookingRouteBuilds += 1;
        return const Scaffold(body: Text('열리면 안 되는 조리 화면'));
      },
    );

    await tester.tap(find.text('이어서 요리하기'));
    await tester.pumpAndSettle();

    expect(pendingLoadAttempts, 3);
    expect(cookingRouteBuilds, 0);
    expect(find.text('저장된 진행 상황을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('열리면 안 되는 조리 화면'), findsNothing);
  });

  testWidgets('조리 재개 직전 초안 확인 중 중복 탭은 한 번만 처리한다', (tester) async {
    final guardLoad = Completer<PendingReviewDraft?>();
    var pendingLoadAttempts = 0;
    var cookingRouteBuilds = 0;

    await _pumpHome(
      tester,
      pendingReviewDraftLoader: () {
        pendingLoadAttempts += 1;
        if (pendingLoadAttempts <= 2) {
          return Future<PendingReviewDraft?>.value(null);
        }
        return guardLoad.future;
      },
      cookingSessionLoader: () async => _buildActiveSession(),
      cookingScreenBuilder: (_, _) {
        cookingRouteBuilds += 1;
        return const Scaffold(body: Text('조리 재개 화면'));
      },
    );
    final resumeCard = find.text('이어서 요리하기');
    await tester.tap(resumeCard);
    await tester.tap(resumeCard);
    await tester.pump();

    expect(pendingLoadAttempts, 3);
    expect(find.text('후기 상태 확인 중'), findsOneWidget);

    guardLoad.complete(null);
    await tester.pumpAndSettle();

    expect(pendingLoadAttempts, 3);
    expect(cookingRouteBuilds, 1);
    expect(find.text('조리 재개 화면'), findsOneWidget);
  });

  testWidgets('후기 카드를 누르면 저장된 초안 객체를 그대로 후기 화면에 전달한다', (tester) async {
    final draft = _buildDraft();
    PendingReviewDraft? receivedDraft;

    await _pumpHome(
      tester,
      pendingReviewDraftLoader: () async => draft,
      reviewScreenBuilder: (initialDraft) {
        receivedDraft = initialDraft;
        return Scaffold(
          body: Text(
            '${initialDraft.rating}|${initialDraft.comment}|'
            '${initialDraft.nextTimeNote}|'
            '${initialDraft.approvedPersonalVersionCreation}',
          ),
        );
      },
    );
    await tester.tap(find.text('후기 작성 이어가기'));
    await tester.pumpAndSettle();

    expect(receivedDraft, isNotNull);
    expect(receivedDraft, same(draft));
    expect(receivedDraft!.toJson(), equals(draft.toJson()));
    expect(find.text('4|양념이 조금 진했다.|간장을 반 숟갈 줄이기|true'), findsOneWidget);
  });

  testWidgets('후기 카드를 연속으로 눌러도 후기 화면은 하나만 연다', (tester) async {
    var reviewBuilds = 0;
    await _pumpHome(
      tester,
      pendingReviewDraftLoader: () async => _buildDraft(),
      reviewScreenBuilder: (_) {
        reviewBuilds += 1;
        return const Scaffold(body: Text('단일 후기 화면'));
      },
    );

    final card = find.text('후기 작성 이어가기');
    await tester.tap(card);
    await tester.tap(card, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(reviewBuilds, 1);
    expect(find.text('단일 후기 화면'), findsOneWidget);
  });

  testWidgets('후기 화면에서 돌아오면 초안을 다시 조회한다', (tester) async {
    PendingReviewDraft? availableDraft = _buildDraft();
    var loadAttempts = 0;

    await _pumpHome(
      tester,
      pendingReviewDraftLoader: () async {
        loadAttempts += 1;
        return availableDraft;
      },
      reviewScreenBuilder: (_) => _ReviewCloseFixture(
        beforeClose: () async {
          availableDraft = null;
        },
      ),
    );
    await tester.tap(find.text('후기 작성 이어가기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('후기 저장 완료'));
    await tester.pumpAndSettle();

    expect(find.text('후기 작성 이어가기'), findsNothing);
    expect(find.text('이어서 요리하기'), findsNothing);
    expect(loadAttempts, 3);
  });

  testWidgets('복구 로드 오류는 활성 세션 대신 오류와 재시도를 표시한다', (tester) async {
    final draft = _buildDraft();
    var loadAttempts = 0;
    var cookingSessionLoadAttempts = 0;

    await _pumpHome(
      tester,
      pendingReviewDraftLoader: () async {
        loadAttempts += 1;
        if (loadAttempts == 1) {
          throw StateError('temporary read failure');
        }
        return draft;
      },
      cookingSessionLoader: () async {
        cookingSessionLoadAttempts += 1;
        return _buildActiveSession();
      },
    );

    expect(find.text('저장된 진행 상황을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('후기 작성 이어가기'), findsNothing);
    expect(find.text('이어서 요리하기'), findsNothing);
    expect(cookingSessionLoadAttempts, 0);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(loadAttempts, 2);
    expect(find.text('후기 작성 이어가기'), findsOneWidget);
    expect(find.text('이어서 요리하기'), findsNothing);
    expect(cookingSessionLoadAttempts, 0);
  });

  testWidgets('활성 조리 저장소 로드 오류도 복구 오류로 표시한다', (tester) async {
    await _pumpHome(
      tester,
      pendingReviewDraftLoader: () async => null,
      cookingSessionLoader: () async {
        throw StateError('active session read failure');
      },
    );

    expect(find.text('저장된 진행 상황을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('후기 작성 이어가기'), findsNothing);
    expect(find.text('이어서 요리하기'), findsNothing);
  });

  testWidgets('늦게 끝난 이전 복구 요청이 최신 후기 초안을 덮어쓰지 않는다', (tester) async {
    final firstLoad = Completer<PendingReviewDraft?>();
    final latestDraft = _buildDraft();
    var loadAttempts = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCookPilotTheme(),
        home: HomeScreen(
          recipeRepository: _EmptyRecipeRepository(),
          pendingReviewDraftLoader: () {
            loadAttempts += 1;
            if (loadAttempts == 1) {
              return firstLoad.future;
            }
            return Future<PendingReviewDraft?>.value(latestDraft);
          },
          cookingSessionLoader: () async => null,
        ),
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(loadAttempts, 2);
    expect(find.text('후기 작성 이어가기'), findsOneWidget);

    firstLoad.complete(null);
    await tester.pumpAndSettle();

    expect(find.text('후기 작성 이어가기'), findsOneWidget);
    expect(find.text(latestDraft.setupSnapshot.title), findsOneWidget);
    expect(find.text('이어서 요리하기'), findsNothing);
  });

  testWidgets('두 번째 초안 조회가 늦게 끝나도 최신 복구 결과를 덮어쓰지 않는다', (tester) async {
    final delayedSecondLoad = Completer<PendingReviewDraft?>();
    final latestDraft = _buildDraft();
    var loadAttempts = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCookPilotTheme(),
        home: HomeScreen(
          recipeRepository: _EmptyRecipeRepository(),
          pendingReviewDraftLoader: () {
            loadAttempts += 1;
            if (loadAttempts == 1) {
              return Future<PendingReviewDraft?>.value(null);
            }
            if (loadAttempts == 2) {
              return delayedSecondLoad.future;
            }
            return Future<PendingReviewDraft?>.value(latestDraft);
          },
          cookingSessionLoader: () async => null,
        ),
      ),
    );
    await tester.pump();
    expect(loadAttempts, 2);

    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();

    expect(loadAttempts, 3);
    expect(find.text('후기 작성 이어가기'), findsOneWidget);

    delayedSecondLoad.complete(null);
    await tester.pumpAndSettle();

    expect(find.text('후기 작성 이어가기'), findsOneWidget);
    expect(find.text(latestDraft.setupSnapshot.title), findsOneWidget);
    expect(find.text('이어서 요리하기'), findsNothing);
  });

  testWidgets('당겨서 새로고침하면 새로 생긴 후기 초안을 복구한다', (tester) async {
    PendingReviewDraft? availableDraft;
    final recipeRepository = _EmptyRecipeRepository();
    await _pumpHome(
      tester,
      pendingReviewDraftLoader: () async => availableDraft,
      recipeRepository: recipeRepository,
    );
    expect(find.text('후기 작성 이어가기'), findsNothing);
    expect(recipeRepository.findAllCalls, 1);
    expect(recipeRepository.findRecentCalls, 1);
    expect(recipeRepository.findFavoritesCalls, 1);

    availableDraft = _buildDraft();
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();

    expect(find.text('후기 작성 이어가기'), findsOneWidget);
    expect(recipeRepository.findAllCalls, 2);
    expect(recipeRepository.findRecentCalls, 2);
    expect(recipeRepository.findFavoritesCalls, 2);
  });
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required HomePendingReviewDraftLoader pendingReviewDraftLoader,
  HomeCookingSessionLoader? cookingSessionLoader,
  HomeReviewScreenBuilder? reviewScreenBuilder,
  HomeCookingScreenBuilder? cookingScreenBuilder,
  RecipeRepository? recipeRepository,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildCookPilotTheme(),
      home: HomeScreen(
        recipeRepository: recipeRepository ?? _EmptyRecipeRepository(),
        pendingReviewDraftLoader: pendingReviewDraftLoader,
        cookingSessionLoader: cookingSessionLoader ?? () async => null,
        reviewScreenBuilder: reviewScreenBuilder,
        cookingScreenBuilder: cookingScreenBuilder,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PendingReviewDraft _buildDraft() {
  return PendingReviewDraft(
    clientSessionId: '21000000-0000-0000-0000-000000000001',
    cookedAt: DateTime.utc(2026, 7, 30, 10, 20),
    setupSnapshot: _buildSetupSnapshot(),
    timerSecondsByStep: const {0: 105},
    rating: 4,
    comment: '양념이 조금 진했다.',
    nextTimeNote: '간장을 반 숟갈 줄이기',
    approvedPersonalVersionCreation: true,
  );
}

CookingSetupSnapshot _buildSetupSnapshot() {
  return CookingSetupSnapshot(
    recipeId: '22000000-0000-0000-0000-000000000001',
    title: '두부 조림',
    description: '짭조름한 두부 반찬',
    imageUrl: '',
    baseServings: 2,
    targetServings: 2,
    source: CookingRecipeSource.base,
    personalVersionId: null,
    ingredients: const [
      CookingSetupIngredient(
        originalIngredientId: '23000000-0000-0000-0000-000000000001',
        originalName: '두부',
        name: '두부',
        amount: 1,
        baselineAmount: 1,
        unit: '모',
        isRequired: true,
      ),
    ],
    steps: const [
      CookingSetupStep(
        originalStepId: '24000000-0000-0000-0000-000000000001',
        stepIndex: 0,
        instruction: '두부를 노릇하게 굽는다.',
        timerSeconds: 120,
        cautionNote: null,
        imageUrl: '',
      ),
    ],
  );
}

PersistedCookingSession _buildActiveSession() {
  final setupSnapshot = _buildSetupSnapshot();
  return PersistedCookingSession(
    sessionId: '25000000-0000-0000-0000-000000000001',
    recipeId: setupSnapshot.recipeId,
    recipeTitle: setupSnapshot.title,
    servings: setupSnapshot.targetServings,
    setupSnapshot: setupSnapshot,
    stepIndex: 0,
    sessionStatus: 'cooking',
    timerOriginalMs: 120000,
    timerEffectiveMs: 120000,
    timerRemainingMs: 90000,
    timerStatus: 'paused',
    savedAtEpochMs: DateTime(2026, 7, 30, 10).millisecondsSinceEpoch,
    timerSecondsByStep: const {0: 105},
  );
}

class _EmptyRecipeRepository extends RecipeRepository {
  _EmptyRecipeRepository() : super(baseUrl: 'http://example.test');

  var findAllCalls = 0;
  var findRecentCalls = 0;
  var findFavoritesCalls = 0;

  @override
  Future<List<RecipeSummary>> findAll({int page = 0, int size = 10}) async {
    findAllCalls += 1;
    return const [];
  }

  @override
  Future<List<RecipeSummary>> findRecent() async {
    findRecentCalls += 1;
    return const [];
  }

  @override
  Future<List<RecipeSummary>> findFavorites() async {
    findFavoritesCalls += 1;
    return const [];
  }

  @override
  Future<Recipe> findById(RecipeSummary summary) {
    throw StateError('빈 카탈로그에서는 상세 조회를 호출하면 안 됩니다.');
  }
}

class _ReviewCloseFixture extends StatelessWidget {
  const _ReviewCloseFixture({required this.beforeClose});

  final Future<void> Function() beforeClose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () async {
            await beforeClose();
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Text('후기 저장 완료'),
        ),
      ),
    );
  }
}
