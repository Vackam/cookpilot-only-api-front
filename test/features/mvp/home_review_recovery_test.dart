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

  // 예전에는 후기 초안이 조리 카드를 밀어냈다. 후기를 쓸지는 사용자가 정할
  // 일이라, 둘 다 있으면 둘 다 보여 주고 선택은 사용자에게 맡긴다.
  testWidgets('후기 초안과 활성 조리 세션이 함께 있으면 카드 둘 다 표시한다', (tester) async {
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
    expect(find.text('이어서 요리하기'), findsOneWidget);
    expect(cookingSessionLoadAttempts, 1);
  });

  testWidgets('활성 세션 조회 중 생긴 후기 초안도 카드로 잡는다', (tester) async {
    final activeLoad = Completer<PersistedCookingSession?>();
    final draft = _buildDraft();
    var activeLoadFinished = false;
    var pendingLoadAttempts = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCookPilotTheme(),
        home: HomeScreen(
          recipeRepository: _EmptyRecipeRepository(),
          // 세션 조회가 끝난 뒤에 읽어야, 그 사이에 생긴 초안이 잡힌다.
          pendingReviewDraftLoader: () async {
            pendingLoadAttempts += 1;
            return activeLoadFinished ? draft : null;
          },
          cookingSessionLoader: () => activeLoad.future,
        ),
      ),
    );
    await tester.pump();

    activeLoadFinished = true;
    activeLoad.complete(_buildActiveSession());
    await tester.pumpAndSettle();

    expect(pendingLoadAttempts, 1);
    expect(find.text('후기 작성 이어가기'), findsOneWidget);
    expect(find.text('이어서 요리하기'), findsOneWidget);
  });

  testWidgets('활성 세션 조회가 실패해도 후기 초안이 있으면 그것만 표시한다', (tester) async {
    final activeLoad = Completer<PersistedCookingSession?>();
    final draft = _buildDraft();
    var activeLoadFinished = false;
    var pendingLoadAttempts = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCookPilotTheme(),
        home: HomeScreen(
          recipeRepository: _EmptyRecipeRepository(),
          pendingReviewDraftLoader: () async {
            pendingLoadAttempts += 1;
            return activeLoadFinished ? draft : null;
          },
          cookingSessionLoader: () => activeLoad.future,
        ),
      ),
    );
    await tester.pump();

    activeLoadFinished = true;
    activeLoad.completeError(StateError('active session read failure'));
    await tester.pumpAndSettle();

    // 보여 줄 것이 남아 있으면 세션 조회 실패로 화면을 오류로 덮지 않는다.
    expect(pendingLoadAttempts, 1);
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

  // 작성 중인 후기가 있어도 조리 재개를 가로채지 않는다. 후기를 쓸지는
  // 사용자가 정할 일이고, 초안은 홈의 "후기 작성 이어가기" 카드가 알린다.
  testWidgets('작성 중인 후기가 있어도 이어서 요리하기는 조리 화면을 연다', (tester) async {
    var cookingRouteBuilds = 0;

    await _pumpHome(
      tester,
      pendingReviewDraftLoader: () async => _buildDraft(),
      cookingSessionLoader: () async => _buildActiveSession(),
      reviewScreenBuilder: (_) => const Scaffold(body: Text('열리면 안 되는 후기 화면')),
      cookingScreenBuilder: (_, _) {
        cookingRouteBuilds += 1;
        return const Scaffold(body: Text('조리 재개 화면'));
      },
    );

    // 두 카드가 서로를 가리지 않고 함께 떠 있어야 한다.
    expect(find.text('후기 작성 이어가기'), findsOneWidget);
    await tester.tap(find.text('이어서 요리하기'));
    await tester.pumpAndSettle();

    expect(cookingRouteBuilds, 1);
    expect(find.text('조리 재개 화면'), findsOneWidget);
    expect(find.text('열리면 안 되는 후기 화면'), findsNothing);
    expect(find.text('작성 중인 후기를 먼저 이어갈게요.'), findsNothing);
  });

  testWidgets('조리 재개는 초안을 다시 조회하지 않는다', (tester) async {
    var pendingLoadAttempts = 0;
    var cookingRouteBuilds = 0;

    await _pumpHome(
      tester,
      pendingReviewDraftLoader: () async {
        pendingLoadAttempts += 1;
        return null;
      },
      cookingSessionLoader: () async => _buildActiveSession(),
      cookingScreenBuilder: (_, _) {
        cookingRouteBuilds += 1;
        return const Scaffold(body: Text('조리 재개 화면'));
      },
    );
    final loadsBeforeResume = pendingLoadAttempts;

    await tester.tap(find.text('이어서 요리하기'));
    await tester.pumpAndSettle();

    // 재개 시점에는 초안을 보지 않으므로 조회 실패가 조리를 막을 일도 없다.
    expect(pendingLoadAttempts, loadsBeforeResume);
    expect(cookingRouteBuilds, 1);
    expect(find.text('조리 재개 화면'), findsOneWidget);
  });

  testWidgets('조리 재개 중복 탭은 조리 화면을 한 번만 연다', (tester) async {
    var cookingRouteBuilds = 0;

    await _pumpHome(
      tester,
      pendingReviewDraftLoader: () async => null,
      cookingSessionLoader: () async => _buildActiveSession(),
      cookingScreenBuilder: (_, _) {
        cookingRouteBuilds += 1;
        return const Scaffold(body: Text('조리 재개 화면'));
      },
    );
    final resumeCard = find.text('이어서 요리하기');
    await tester.tap(resumeCard);
    await tester.tap(resumeCard);
    await tester.pumpAndSettle();

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
    // 복구 한 번에 초안 조회는 한 번. 최초 진입과 후기 화면 복귀로 두 번이다.
    expect(loadAttempts, 2);
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
    expect(cookingSessionLoadAttempts, 1);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(loadAttempts, 2);
    expect(find.text('후기 작성 이어가기'), findsOneWidget);
    expect(find.text('이어서 요리하기'), findsOneWidget);
    expect(cookingSessionLoadAttempts, 2);
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
