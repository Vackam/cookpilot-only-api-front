import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../cooking/application/cooking_session_store.dart';
import '../cooking/data/exception_advice_api.dart';
import '../cooking/presentation/native_speech_output.dart';
import '../recipe/data/recipe_api.dart';
import '../recipe/domain/recipe.dart';
import '../review/application/pending_review_draft_store.dart';
import '../review/data/review_api.dart';
import 'cook_flow_screens.dart';
import 'mvp_widgets.dart';

final _recipeRepository = RecipeRepository();

/// 검색과 제목 매칭은 클라이언트에서 하므로 기본 페이지(10건)로는 부족하다.
/// 서버가 허용하는 최대 페이지 크기와 같은 값이다.
const _localScanPageSize = 100;

typedef HomeReviewScreenBuilder =
    Widget Function(PendingReviewDraft initialDraft);
typedef HomePendingReviewDraftLoader = Future<PendingReviewDraft?> Function();
typedef HomeCookingSessionLoader = Future<PersistedCookingSession?> Function();
typedef HomeCookingScreenBuilder =
    Widget Function(PersistedCookingSession session, Recipe recipe);

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    const pages = [HomeScreen(), SearchScreen(), MemoryScreen()];

    return Scaffold(
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search_rounded),
            label: '검색',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline_rounded),
            selectedIcon: Icon(Icons.bookmark_rounded),
            label: '메모리',
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.recipeRepository,
    this.pendingReviewDraftLoader,
    this.cookingSessionLoader,
    this.reviewScreenBuilder,
    this.cookingScreenBuilder,
  });

  final RecipeRepository? recipeRepository;
  final HomePendingReviewDraftLoader? pendingReviewDraftLoader;
  final HomeCookingSessionLoader? cookingSessionLoader;
  final HomeReviewScreenBuilder? reviewScreenBuilder;
  final HomeCookingScreenBuilder? cookingScreenBuilder;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final RecipeRepository _homeRecipeRepository;
  late final CookingSessionStore _sessionStore;
  late final HomePendingReviewDraftLoader _pendingReviewDraftLoader;
  late final HomeCookingSessionLoader _cookingSessionLoader;

  late Future<_HomeCatalog> _catalog;
  var _recoveryGeneration = 0;
  var _recoveryLoading = true;
  Object? _recoveryError;
  PendingReviewDraft? _pendingReviewDraft;
  PersistedCookingSession? _resumableSession;
  Recipe? _resumableRecipe;
  bool _resumingCooking = false;
  var _openingPendingReview = false;

  @override
  void initState() {
    super.initState();
    _homeRecipeRepository = widget.recipeRepository ?? _recipeRepository;
    _sessionStore = const CookingSessionStore();
    _pendingReviewDraftLoader =
        widget.pendingReviewDraftLoader ?? PendingReviewDraftStore().load;
    _cookingSessionLoader = widget.cookingSessionLoader ?? _sessionStore.load;
    _catalog = _loadCatalog();
    unawaited(_refreshRecovery(markLoading: false));
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 11) return '좋은 아침이에요';
    if (hour < 17) return '점심은 챙기셨나요?';
    return '오늘 저녁, 뭐 해먹을까요?';
  }

  Future<_HomeCatalog> _loadCatalog() async {
    final results = await Future.wait<List<RecipeSummary>>([
      _homeRecipeRepository.findAll(),
      _homeRecipeRepository.findRecent(),
      _homeRecipeRepository.findFavorites(),
    ]);
    final summaries = results[0];
    final recent = results[1];
    final favorites = results[2];
    if (summaries.isEmpty) {
      return _HomeCatalog(
        summaries: summaries,
        featured: null,
        recent: recent,
        favorites: favorites,
      );
    }
    Recipe? featured;
    try {
      featured = await _homeRecipeRepository.findById(summaries.first);
    } on Object {
      // 추천 상세가 실패해도 조회 가능한 전체 목록은 유지한다.
      featured = null;
    }
    return _HomeCatalog(
      summaries: summaries,
      featured: featured,
      recent: recent,
      favorites: favorites,
    );
  }

  void _retry() {
    setState(() {
      _catalog = _loadCatalog();
    });
    unawaited(_refreshRecovery());
  }

  void _refreshHome() {
    _retry();
  }

  bool _isCurrentRecovery(int generation) {
    return mounted && generation == _recoveryGeneration;
  }

  Future<void> _refreshRecovery({bool markLoading = true}) async {
    final generation = ++_recoveryGeneration;
    if (markLoading && mounted) {
      setState(() {
        _recoveryLoading = true;
        _recoveryError = null;
        _pendingReviewDraft = null;
        _resumableSession = null;
        _resumableRecipe = null;
      });
    }

    try {
      final pendingReviewDraft = await _pendingReviewDraftLoader();
      if (!_isCurrentRecovery(generation)) {
        return;
      }
      if (pendingReviewDraft != null) {
        setState(() {
          _recoveryLoading = false;
          _recoveryError = null;
          _pendingReviewDraft = pendingReviewDraft;
          _resumableSession = null;
          _resumableRecipe = null;
        });
        return;
      }

      _ResumableCooking? resumableCooking;
      Object? resumableCookingError;
      StackTrace? resumableCookingStackTrace;
      try {
        resumableCooking = await _findResumableCooking(generation);
      } on Object catch (error, stackTrace) {
        resumableCookingError = error;
        resumableCookingStackTrace = stackTrace;
      }
      if (!_isCurrentRecovery(generation)) {
        return;
      }
      // The active-session lookup can outlive cooking completion. Re-read the
      // draft even when that lookup failed, so a review created while it was
      // running still wins.
      final latestPendingReviewDraft = await _pendingReviewDraftLoader();
      if (!_isCurrentRecovery(generation)) {
        return;
      }
      if (latestPendingReviewDraft == null && resumableCookingError != null) {
        Error.throwWithStackTrace(
          resumableCookingError,
          resumableCookingStackTrace!,
        );
      }
      setState(() {
        _recoveryLoading = false;
        _recoveryError = null;
        _pendingReviewDraft = latestPendingReviewDraft;
        _resumableSession = latestPendingReviewDraft == null
            ? resumableCooking?.session
            : null;
        _resumableRecipe = latestPendingReviewDraft == null
            ? resumableCooking?.recipe
            : null;
      });
    } on Object catch (error) {
      if (!_isCurrentRecovery(generation)) {
        return;
      }
      setState(() {
        _recoveryLoading = false;
        _recoveryError = error;
        _pendingReviewDraft = null;
        _resumableSession = null;
        _resumableRecipe = null;
      });
    }
  }

  Future<_ResumableCooking?> _findResumableCooking(int generation) async {
    final session = await _cookingSessionLoader();
    if (!_isCurrentRecovery(generation)) {
      return null;
    }
    if (session == null || !session.isResumable) {
      return null;
    }

    final storedRecipeId = session.recipeId;
    try {
      var restoredSession = session;
      final Recipe recipe;
      final setupSnapshot = session.setupSnapshot;
      if (setupSnapshot != null) {
        recipe = setupSnapshot.toExecutionRecipe();
      } else {
        final recipeId = storedRecipeId;
        if (recipeId != null && recipeId.isNotEmpty) {
          recipe = await _homeRecipeRepository.findByRecipeId(recipeId);
        } else {
          final summaries = await _homeRecipeRepository.findAll(
            size: _localScanPageSize,
          );
          final matches = summaries
              .where((summary) => summary.title == session.recipeTitle)
              .toList(growable: false);
          if (matches.length != 1) {
            return null;
          }
          recipe = await _homeRecipeRepository.findById(matches.single);
        }
      }
      if (recipe.steps.isEmpty) {
        return null;
      }
      if (session.recipeId != recipe.id ||
          session.recipeTitle != recipe.title) {
        restoredSession = session.copyWith(
          recipeId: recipe.id,
          recipeTitle: recipe.title,
        );
      }
      return _ResumableCooking(session: restoredSession, recipe: recipe);
    } on RecipeApiException catch (error) {
      if (storedRecipeId == null ||
          storedRecipeId.isEmpty ||
          error.statusCode != 404) {
        rethrow;
      }
      return null;
    }
  }

  Future<void> _openPendingReview() async {
    final pendingReviewDraft = _pendingReviewDraft;
    if (pendingReviewDraft == null || _openingPendingReview) {
      return;
    }
    _openingPendingReview = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              widget.reviewScreenBuilder?.call(pendingReviewDraft) ??
              ReviewScreen(initialDraft: pendingReviewDraft),
        ),
      );
    } finally {
      _openingPendingReview = false;
    }
    if (mounted) {
      await _refreshRecovery();
    }
  }

  Future<void> _resumeCooking() async {
    if (_resumingCooking) {
      return;
    }
    final session = _resumableSession;
    final recipe = _resumableRecipe;
    if (session == null || recipe == null) {
      return;
    }
    final generation = ++_recoveryGeneration;
    setState(() => _resumingCooking = true);
    try {
      final PendingReviewDraft? latestPendingReviewDraft;
      try {
        latestPendingReviewDraft = await _pendingReviewDraftLoader();
      } on Object catch (error) {
        if (_isCurrentRecovery(generation)) {
          setState(() {
            _recoveryLoading = false;
            _recoveryError = error;
            _pendingReviewDraft = null;
            _resumableSession = null;
            _resumableRecipe = null;
          });
        }
        return;
      }
      if (!_isCurrentRecovery(generation)) {
        return;
      }
      // Keep the explicit check for BuildContext use after the async load.
      if (!mounted) {
        return;
      }
      if (latestPendingReviewDraft != null) {
        setState(() {
          _recoveryLoading = false;
          _recoveryError = null;
          _pendingReviewDraft = latestPendingReviewDraft;
          _resumableSession = null;
          _resumableRecipe = null;
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('작성 중인 후기를 먼저 이어갈게요.')));
        await _openPendingReview();
        return;
      }

      // MaterialPageRoute.builder는 재실행될 수 있으므로 화면이 소유할 포트는
      // 밖에서 한 번만 만든다.
      final advicePort = HttpExceptionAdvicePort();
      final speechOutput = NativeSpeechOutput();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              widget.cookingScreenBuilder?.call(session, recipe) ??
              CookSessionScreen(
                recipe: recipe,
                servings: session.servings,
                setupSnapshot: session.setupSnapshot,
                restoredSession: session,
                advicePort: advicePort,
                speechOutput: speechOutput,
              ),
        ),
      );
      if (mounted) {
        unawaited(_refreshRecovery());
      }
    } finally {
      if (mounted) {
        setState(() => _resumingCooking = false);
      }
    }
  }

  Future<void> _refreshAll() async {
    final nextCatalog = _loadCatalog();
    setState(() {
      _catalog = nextCatalog;
    });
    final nextRecovery = _refreshRecovery();
    await Future.wait([nextCatalog, nextRecovery]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '셰프님 👋',
                          style: TextStyle(
                            color: AppColors.slate,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _greeting,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.headlineSmall?.copyWith(fontSize: 22),
                        ),
                      ],
                    ),
                  ),
                  PressableScale(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.line),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
              if (_recoveryLoading) ...[
                const SizedBox(height: 18),
                const _HomeRecoveryLoadingCard(),
              ] else if (_recoveryError != null) ...[
                const SizedBox(height: 18),
                _HomeRecoveryErrorCard(
                  onRetry: () => unawaited(_refreshRecovery()),
                ),
              ] else if (_pendingReviewDraft
                  case final PendingReviewDraft draft) ...[
                const SizedBox(height: 18),
                _ResumeReviewCard(
                  draft: draft,
                  onTap: () => unawaited(_openPendingReview()),
                ),
              ] else if (_resumableSession
                  case final PersistedCookingSession session) ...[
                const SizedBox(height: 18),
                _ResumeCookingCard(
                  session: session,
                  stepCount:
                      _resumableRecipe?.steps.length ?? session.stepIndex + 1,
                  checkingPendingReview: _resumingCooking,
                  onTap: _resumingCooking
                      ? null
                      : () => unawaited(_resumeCooking()),
                ),
              ],
              FutureBuilder<_HomeCatalog>(
                future: _catalog,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const _RecipeLoading();
                  }
                  if (snapshot.hasError) {
                    return _RecipeLoadError(onRetry: _retry);
                  }

                  final catalog = snapshot.data;
                  if (catalog == null || catalog.summaries.isEmpty) {
                    return const _RecipeEmpty(message: '등록된 레시피가 아직 없어요.');
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (catalog.featured != null) ...[
                        const SectionTitle('오늘의 메뉴'),
                        RecipeHeroCard(
                          recipe: catalog.featured!,
                          onTap: () => Navigator.of(context)
                              .push(
                                MaterialPageRoute<void>(
                                  builder: (_) => RecipeDetailScreen(
                                    recipe: catalog.featured!,
                                  ),
                                ),
                              )
                              .then((_) => _refreshHome()),
                        ),
                      ],
                      const SectionTitle('최근 조리'),
                      if (catalog.recent.isEmpty)
                        const _HomeDataEmpty(
                          icon: Icons.history_rounded,
                          title: '아직 최근 조리 데이터가 없어요',
                          body: '첫 요리를 마치고 후기를 남기면 여기에 표시돼요.',
                        )
                      else
                        for (final recipe in catalog.recent.take(3))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _RecipeSummaryTile(
                              summary: recipe,
                              onChanged: _refreshHome,
                            ),
                          ),
                      const SectionTitle('즐겨찾기'),
                      if (catalog.favorites.isEmpty)
                        const _HomeDataEmpty(
                          icon: Icons.bookmark_outline_rounded,
                          title: '아직 즐겨찾기 데이터가 없어요',
                          body: '마음에 드는 레시피를 저장하면 바로 모아볼 수 있어요.',
                        )
                      else
                        for (final recipe in catalog.favorites.take(3))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _RecipeSummaryTile(
                              summary: recipe,
                              onChanged: _refreshHome,
                            ),
                          ),
                      SectionTitle('전체 레시피 ${catalog.summaries.length}'),
                      for (final recipe in catalog.summaries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RecipeSummaryTile(
                            summary: recipe,
                            onChanged: _refreshHome,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late Future<List<RecipeSummary>> _recipes;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _recipes = _recipeRepository.findAll(size: _localScanPageSize);
  }

  void _retry() {
    setState(
      () => _recipes = _recipeRepository.findAll(size: _localScanPageSize),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: '검색',
      children: [
        TextField(
          onChanged: (value) => setState(() => _query = value.trim()),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded, color: AppColors.muted),
            hintText: '레시피 이름 또는 설명 검색',
          ),
        ),
        FutureBuilder<List<RecipeSummary>>(
          future: _recipes,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _RecipeLoading();
            }
            if (snapshot.hasError) {
              return _RecipeLoadError(onRetry: _retry);
            }

            final query = _query.toLowerCase();
            final items = (snapshot.data ?? const <RecipeSummary>[])
                .where(
                  (recipe) =>
                      query.isEmpty ||
                      recipe.title.toLowerCase().contains(query) ||
                      recipe.description.toLowerCase().contains(query),
                )
                .toList(growable: false);

            if (items.isEmpty) {
              return const _RecipeEmpty(message: '조건에 맞는 레시피가 없어요.');
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionTitle('검색 결과 ${items.length}'),
                for (final recipe in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RecipeSummaryTile(
                      summary: recipe,
                      onChanged: _retry,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key, this.reviewRepository, this.initialDate});

  final ReviewRepository? reviewRepository;
  final DateTime? initialDate;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  late final ReviewRepository _reviewRepository;
  late DateTime _month;
  late DateTime _selectedDate;
  late Future<List<CookingHistoryEntry>> _history;

  @override
  void initState() {
    super.initState();
    _reviewRepository = widget.reviewRepository ?? ReviewRepository();
    final today = widget.initialDate ?? DateTime.now();
    _month = DateTime(today.year, today.month);
    _selectedDate = DateTime(today.year, today.month, today.day);
    _history = _loadMonth();
  }

  Future<List<CookingHistoryEntry>> _loadMonth() {
    return _reviewRepository.findHistory(
      from: _month,
      to: DateTime(_month.year, _month.month + 1),
    );
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selectedDate = _month;
      _history = _loadMonth();
    });
  }

  void _retry() {
    setState(() => _history = _loadMonth());
  }

  void _openHistoryDetail(
    CookingHistoryEntry selected,
    List<CookingHistoryEntry> monthEntries,
  ) {
    final sameRecipe =
        monthEntries
            .where((entry) => entry.recipeId == selected.recipeId)
            .toList(growable: false)
          ..sort((left, right) => right.cookedAt.compareTo(left.cookedAt));
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CookingHistoryDetailScreen(
            entry: selected,
            sameRecipeEntries: sameRecipe,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: '레시피 메모리',
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                '${_month.year}년 ${_month.month}월',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            IconButton(
              onPressed: () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        FutureBuilder<List<CookingHistoryEntry>>(
          future: _history,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _RecipeLoading();
            }
            if (snapshot.hasError) {
              return _RecipeLoadError(onRetry: _retry);
            }

            final entries = snapshot.data ?? const <CookingHistoryEntry>[];
            final entriesByDay = <int, List<CookingHistoryEntry>>{};
            for (final entry in entries) {
              entriesByDay.putIfAbsent(entry.cookedAt.day, () => []).add(entry);
            }
            final selectedEntries = entries
                .where((entry) => _isSameDate(entry.cookedAt, _selectedDate))
                .toList(growable: false);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final day in ['일', '월', '화', '수', '목', '금', '토'])
                      Expanded(
                        child: Text(
                          day,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 7,
                  mainAxisSpacing: 5,
                  crossAxisSpacing: 5,
                  children: [
                    for (var index = 0; index < _month.weekday % 7; index++)
                      const SizedBox.shrink(),
                    for (
                      var day = 1;
                      day <= DateTime(_month.year, _month.month + 1, 0).day;
                      day++
                    )
                      _MemoryCalendarDay(
                        day: day,
                        count: entriesByDay[day]?.length ?? 0,
                        selected:
                            _selectedDate.year == _month.year &&
                            _selectedDate.month == _month.month &&
                            _selectedDate.day == day,
                        onTap: () => setState(
                          () => _selectedDate = DateTime(
                            _month.year,
                            _month.month,
                            day,
                          ),
                        ),
                      ),
                  ],
                ),
                SectionTitle(
                  '${_selectedDate.month}월 ${_selectedDate.day}일 조리',
                ),
                if (selectedEntries.isEmpty)
                  const _RecipeEmpty(message: '이날 저장된 조리 기록이 없어요.')
                else
                  for (final entry in selectedEntries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: FoodTile(
                        title: entry.recipeTitle,
                        subtitle:
                            '${entry.rating == null ? '평점 없음' : '★ ${entry.rating}'}'
                            '${entry.createdPersonalVersionNumber == null ? '' : ' · 개인 v${entry.createdPersonalVersionNumber}'}',
                        image: entry.recipeImageUrl,
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.muted,
                        ),
                        onTap: () => _openHistoryDetail(entry, entries),
                      ),
                    ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class CookingHistoryDetailScreen extends StatelessWidget {
  const CookingHistoryDetailScreen({
    super.key,
    required this.entry,
    required this.sameRecipeEntries,
  });

  final CookingHistoryEntry entry;
  final List<CookingHistoryEntry> sameRecipeEntries;

  @override
  Widget build(BuildContext context) {
    final otherEntries = sameRecipeEntries
        .where((item) => item.reviewId != entry.reviewId)
        .toList(growable: false);
    final recipeSource = entry.sourcePersonalVersionId == null
        ? '기본 레시피'
        : '개인 레시피';

    return PageShell(
      title: '조리 기록',
      leading: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      children: [
        Text(
          entry.recipeTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          _fullDateLabel(entry.cookedAt),
          style: const TextStyle(
            color: AppColors.slate,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        _CookingResultOverview(entry: entry, recipeSource: recipeSource),
        if (entry.createdPersonalVersionNumber case final int number) ...[
          const SizedBox(height: 14),
          InfoStrip(
            icon: Icons.auto_awesome_rounded,
            title: '개인 레시피 v$number 생성',
            body:
                entry.createdPersonalVersionSummary ??
                '이번 실행 변경을 개인 버전으로 저장했어요.',
          ),
        ],
        if (entry.comment case final String comment
            when comment.isNotEmpty) ...[
          const SectionTitle('이번 요리 메모'),
          _MemoryNoteCard(icon: Icons.edit_note_rounded, text: comment),
        ],
        if (entry.nextTimeNote case final String note when note.isNotEmpty) ...[
          const SectionTitle('다음에는'),
          _MemoryNoteCard(icon: Icons.next_plan_outlined, text: note),
        ],
        if (otherEntries.isNotEmpty) ...[
          const SectionTitle('같은 요리의 다른 기록'),
          for (var index = 0; index < otherEntries.length; index++)
            _CookingHistoryTimelineItem(
              entry: otherEntries[index],
              isLast: index == otherEntries.length - 1,
            ),
        ],
      ],
    );
  }
}

class _CookingResultOverview extends StatelessWidget {
  const _CookingResultOverview({
    required this.entry,
    required this.recipeSource,
  });

  final CookingHistoryEntry entry;
  final String recipeSource;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.wash,
        borderRadius: BorderRadius.circular(AppShape.container),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppShape.inner),
            ),
            child: const Icon(
              Icons.restaurant_rounded,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipeSource,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _ratingLabel(entry.rating),
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryNoteCard extends StatelessWidget {
  const _MemoryNoteCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppShape.inner),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.accent, size: 22),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.ink,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CookingHistoryTimelineItem extends StatelessWidget {
  const _CookingHistoryTimelineItem({
    required this.entry,
    required this.isLast,
  });

  final CookingHistoryEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final version = entry.createdPersonalVersionNumber;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(child: Container(width: 2, color: AppColors.line)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _fullDateLabel(entry.cookedAt),
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_ratingLabel(entry.rating)}'
                    '${version == null ? '' : ' · 개인 v$version 생성'}',
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 13,
                    ),
                  ),
                  if (entry.comment case final String comment
                      when comment.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      comment,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.slate),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _fullDateLabel(DateTime date) {
  return '${date.year}년 ${date.month}월 ${date.day}일';
}

String _ratingLabel(int? rating) {
  if (rating == null) return '평점 없음';
  final safeRating = rating.clamp(0, 5);
  return '${'★' * safeRating}${'☆' * (5 - safeRating)}  $safeRating.0';
}

class _MemoryCalendarDay extends StatelessWidget {
  const _MemoryCalendarDay({
    required this.day,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final int day;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.line,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                color: selected ? AppColors.accent : AppColors.ink,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            if (count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else
              const SizedBox(height: 13),
          ],
        ),
      ),
    );
  }
}

bool _isSameDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

class _HomeRecoveryLoadingCard extends StatelessWidget {
  const _HomeRecoveryLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppShape.container),
        border: Border.all(color: AppColors.line),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: 13),
          Expanded(
            child: Text(
              '저장된 진행 상황을 확인하고 있어요.',
              style: TextStyle(
                color: AppColors.slate,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeRecoveryErrorCard extends StatelessWidget {
  const _HomeRecoveryErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppShape.container),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: AppColors.accent),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  '저장된 진행 상황을 불러오지 못했어요.',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            '후기나 조리 세션이 남아 있을 수 있어요. 다시 확인해 주세요.',
            style: TextStyle(color: AppColors.slate, fontSize: 13),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

class _ResumeReviewCard extends StatelessWidget {
  const _ResumeReviewCard({required this.draft, required this.onTap});

  final PendingReviewDraft draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(AppShape.container),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.rate_review_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '후기 작성 이어가기',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      draft.setupSnapshot.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '작성 중인 내용을 확인하고 저장해 주세요.',
                      style: TextStyle(color: AppColors.slate, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumeCookingCard extends StatelessWidget {
  const _ResumeCookingCard({
    required this.session,
    required this.stepCount,
    required this.checkingPendingReview,
    required this.onTap,
  });

  final PersistedCookingSession session;
  final int stepCount;
  final bool checkingPendingReview;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(AppShape.container),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      checkingPendingReview ? '후기 상태 확인 중' : '이어서 요리하기',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      session.recipeTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${session.stepIndex + 1} / $stepCount 단계',
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (checkingPendingReview)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecipeSummaryTile extends StatelessWidget {
  const _RecipeSummaryTile({required this.summary, required this.onChanged});

  final RecipeSummary summary;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return FoodTile(
      title: summary.title,
      subtitle: summary.description,
      image: summary.imageUrl,
      trailing: Icon(
        summary.favorite ? Icons.bookmark_rounded : Icons.chevron_right_rounded,
        color: summary.favorite ? AppColors.accent : AppColors.muted,
      ),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _RecipeDetailLoader(summary: summary),
          ),
        );
        onChanged();
      },
    );
  }
}

class _RecipeDetailLoader extends StatefulWidget {
  const _RecipeDetailLoader({required this.summary});

  final RecipeSummary summary;

  @override
  State<_RecipeDetailLoader> createState() => _RecipeDetailLoaderState();
}

class _RecipeDetailLoaderState extends State<_RecipeDetailLoader> {
  late Future<Recipe> _recipe;

  @override
  void initState() {
    super.initState();
    _recipe = _recipeRepository.findById(widget.summary);
  }

  void _retry() {
    setState(() => _recipe = _recipeRepository.findById(widget.summary));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Recipe>(
      future: _recipe,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.summary.title)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.summary.title)),
            body: _RecipeLoadError(onRetry: _retry),
          );
        }
        return RecipeDetailScreen(recipe: snapshot.data!);
      },
    );
  }
}

class _RecipeLoading extends StatelessWidget {
  const _RecipeLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 48),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _RecipeLoadError extends StatelessWidget {
  const _RecipeLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.muted, size: 40),
          const SizedBox(height: 12),
          const Text(
            '레시피를 불러오지 못했어요.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            '백엔드 서버 연결을 확인한 뒤 다시 시도해 주세요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.slate),
          ),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

class _RecipeEmpty extends StatelessWidget {
  const _RecipeEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.slate),
        ),
      ),
    );
  }
}

class _HomeDataEmpty extends StatelessWidget {
  const _HomeDataEmpty({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return InfoStrip(icon: icon, title: title, body: body);
  }
}

class _HomeCatalog {
  const _HomeCatalog({
    required this.summaries,
    required this.featured,
    required this.recent,
    required this.favorites,
  });

  final List<RecipeSummary> summaries;
  final Recipe? featured;
  final List<RecipeSummary> recent;
  final List<RecipeSummary> favorites;
}

class _ResumableCooking {
  const _ResumableCooking({required this.session, required this.recipe});

  final PersistedCookingSession session;
  final Recipe recipe;
}
