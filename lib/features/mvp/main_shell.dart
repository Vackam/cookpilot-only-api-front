import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../design/design_tokens.dart';
import '../cooking/application/cooking_session_store.dart';
import '../cooking/data/exception_advice_api.dart';
import '../cooking/presentation/native_speech_output.dart';
import '../recipe/data/recipe_api.dart';
import '../recipe/domain/recipe.dart';
import '../review/application/pending_review_draft_store.dart';
import '../review/data/review_api.dart';
import 'account_screen.dart';
import 'cook_flow_screens.dart';
import 'mvp_widgets.dart';
import 'shell_tab.dart';

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
  @override
  void initState() {
    super.initState();
    shellTabIndex.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    shellTabIndex.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  int get index => shellTabIndex.value;

  void _select(int value) => shellTabIndex.value = value;

  @override
  Widget build(BuildContext context) {
    const pages = [
      HomeScreen(),
      SearchScreen(),
      MemoryScreen(),
      AccountScreen(),
    ];

    return Scaffold(
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: index,
        onDestinationSelected: _select,
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
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today_rounded),
            label: '기록',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '내 정보',
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

  /// 히어로 저장 버튼의 화면상 상태. null 이면 레시피가 들고 온 값을 쓴다.
  bool? _heroFavorite;
  bool _savingHeroFavorite = false;

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
      // 오늘의 추천은 매번 다르게 고른다. 첫 건으로 고정하면 카탈로그가 커도
      // 홈을 열 때마다 같은 요리가 나온다.
      featured = await _homeRecipeRepository.findById(
        summaries[Random().nextInt(summaries.length)],
      );
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
      _heroFavorite = null;
      _catalog = _loadCatalog();
    });
    unawaited(_refreshRecovery());
  }

  void _refreshHome() {
    _retry();
  }

  /// 카드에서 레시피 상세로. 돌아오면 즐겨찾기·개인 버전 변화가 반영되도록 다시 읽는다.
  void _openRecipe(RecipeSummary summary) {
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => _RecipeDetailLoader(summary: summary),
            ),
          )
          .then((_) => _refreshHome()),
    );
  }

  /// 오늘의 추천은 이미 전체 레시피를 들고 있어 다시 불러올 필요가 없다.
  void _openFeatured(Recipe recipe) {
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => RecipeDetailScreen(recipe: recipe),
            ),
          )
          .then((_) => _refreshHome()),
    );
  }

  /// 카드 아래 캡션. 데이터가 없으면 빈 줄을 만들지 않고 비운다.
  String? _cookedOn(RecipeSummary recipe) {
    final cooked = recipe.lastCookedAt;
    if (cooked == null) return null;
    return '${cooked.month}월 ${cooked.day}일';
  }

  String? _ratingOf(RecipeSummary recipe) {
    final rating = recipe.lastRating;
    return rating == null ? null : '★ $rating';
  }

  /// 히어로 저장 버튼. 상세 화면과 같은 즐겨찾기 토글이다.
  Future<void> _toggleHeroFavorite(Recipe recipe) async {
    if (_savingHeroFavorite) return;
    final saved = _heroFavorite ?? recipe.favorite;
    setState(() => _savingHeroFavorite = true);
    try {
      if (saved) {
        await _homeRecipeRepository.removeFavorite(recipe.id);
      } else {
        await _homeRecipeRepository.addFavorite(recipe.id);
      }
      if (!mounted) return;
      setState(() => _heroFavorite = !saved);
    } on RecipeApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _savingHeroFavorite = false);
      }
    }
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
      // 후기 초안과 이어서 할 조리는 서로를 밀어내지 않는다. 둘 다 조회해서
      // 둘 다 카드로 띄운다.
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
      // 조리 세션 조회는 조리 완료보다 늦게 끝날 수 있다. 그 사이에 생긴 초안도
      // 잡히도록 조회 뒤에 읽는다.
      final pendingReviewDraft = await _pendingReviewDraftLoader();
      if (!_isCurrentRecovery(generation)) {
        return;
      }
      // 보여 줄 것이 아무것도 없을 때만 조회 실패를 오류로 올린다.
      if (pendingReviewDraft == null && resumableCookingError != null) {
        Error.throwWithStackTrace(
          resumableCookingError,
          resumableCookingStackTrace!,
        );
      }
      setState(() {
        _recoveryLoading = false;
        _recoveryError = null;
        _pendingReviewDraft = pendingReviewDraft;
        _resumableSession = resumableCooking?.session;
        _resumableRecipe = resumableCooking?.recipe;
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
      if (!_isCurrentRecovery(generation)) {
        return;
      }
      if (!mounted) {
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
      _heroFavorite = null;
      _catalog = nextCatalog;
    });
    final nextRecovery = _refreshRecovery();
    await Future.wait([nextCatalog, nextRecovery]);
  }

  /// 조리 이어하기 / 후기 이어쓰기 안내. 히어로 아래에 두는 자리라
  /// 카탈로그 로딩 상태와 무관하게 같은 위젯을 쓴다.
  Widget _recoveryBlock() {
    final space = context.space;
    if (_recoveryLoading) return const _HomeRecoveryLoadingCard();
    if (_recoveryError != null) {
      return _HomeRecoveryErrorCard(
        onRetry: () => unawaited(_refreshRecovery()),
      );
    }
    // 후기 초안과 이어서 할 조리는 서로를 가리지 않는다. 후기를 쓸지는
    // 사용자가 정할 일이라, 조리 진입을 막는 대신 여기서 나란히 알린다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_pendingReviewDraft case final PendingReviewDraft draft)
          Padding(
            padding: EdgeInsets.only(bottom: space.itemGap),
            child: _ResumeReviewCard(
              draft: draft,
              onTap: () => unawaited(_openPendingReview()),
            ),
          ),
        if (_resumableSession case final PersistedCookingSession session)
          Padding(
            padding: EdgeInsets.only(bottom: space.itemGap),
            child: _ResumeCookingCard(
              session: session,
              stepCount:
                  _resumableRecipe?.steps.length ?? session.stepIndex + 1,
              opening: _resumingCooking,
              onTap: _resumingCooking
                  ? null
                  : () => unawaited(_resumeCooking()),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            // 히어로가 화면 끝까지 닿아야 해서 목록에는 좌우 여백을 주지 않는다.
            // 여백은 _Gutter 로 섹션마다 따로 준다.
            padding: EdgeInsets.only(
              top: space.screenPaddingTop,
              bottom: space.screenPaddingBottom,
            ),
            children: [
              _Gutter(
                child: SizedBox(
                  // 다른 탭의 로고 버튼(34 + 위아래 8)과 같은 높이로 맞춘다.
                  height: 50,
                  child: Row(
                    children: [
                      // 인사말 대신 워드마크만 둔다. 넷플릭스 좌상단과 같은 자리다.
                      // 검색은 하단 탭에 있으므로 여기에 또 두지 않는다.
                      Image.asset(
                        'assets/logo/cooklog-wordmark.png',
                        height: 34,
                        fit: BoxFit.contain,
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
              FutureBuilder<_HomeCatalog>(
                future: _catalog,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return _Gutter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: space.sectionGap),
                          _recoveryBlock(),
                          const _RecipeLoading(),
                        ],
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return _Gutter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: space.sectionGap),
                          _recoveryBlock(),
                          _RecipeLoadError(onRetry: _retry),
                        ],
                      ),
                    );
                  }

                  final catalog = snapshot.data;
                  if (catalog == null || catalog.summaries.isEmpty) {
                    return _Gutter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: space.sectionGap),
                          _recoveryBlock(),
                          const _RecipeEmpty(message: '등록된 레시피가 아직 없어요.'),
                        ],
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (catalog.featured != null) ...[
                        RecipeHeroCard(
                          recipe: catalog.featured!,
                          favorite: _heroFavorite,
                          saving: _savingHeroFavorite,
                          onTap: () => _openFeatured(catalog.featured!),
                          onStart: () => _openFeatured(catalog.featured!),
                          onSave: () => unawaited(
                            _toggleHeroFavorite(catalog.featured!),
                          ),
                        ),
                        SizedBox(height: space.sectionGap),
                      ],
                      // 이어하기 안내는 히어로 바로 아래다. 화면 맨 위를 차지하면
                      // 카탈로그가 아니라 알림창처럼 보인다.
                      _Gutter(child: _recoveryBlock()),
                      if (catalog.recent.isNotEmpty)
                        _Gutter(
                          child: RecipeRail(
                            title: '내가 만든 요리',
                            trailing: '전체 ${catalog.recent.length} →',
                            hasMeta: true,
                            children: [
                              for (final recipe in catalog.recent)
                                RecipePosterCard(
                                  title: recipe.title,
                                  image: recipe.imageUrl,
                                  meta: _cookedOn(recipe),
                                  onTap: () => _openRecipe(recipe),
                                ),
                            ],
                          ),
                        )
                      else
                        const _Gutter(
                          child: _HomeDataEmpty(
                            icon: Icons.history_rounded,
                            title: '아직 최근 조리 데이터가 없어요',
                            body: '첫 요리를 마치고 후기를 남기면 여기에 모여요.',
                          ),
                        ),
                      if (catalog.favorites.isNotEmpty)
                        _Gutter(
                          child: RecipeRail(
                            title: '다시 만들까요',
                            trailing: '즐겨찾기 ${catalog.favorites.length} →',
                            hasMeta: true,
                            children: [
                              for (final recipe in catalog.favorites)
                                RecipePosterCard(
                                  title: recipe.title,
                                  image: recipe.imageUrl,
                                  meta: _ratingOf(recipe),
                                  onTap: () => _openRecipe(recipe),
                                ),
                            ],
                          ),
                        ),
                      _Gutter(
                        child: RecipeRail(
                          title: '전체 레시피',
                          trailing: '${catalog.summaries.length}개 →',
                          children: [
                            for (final recipe in catalog.summaries)
                              RecipePosterCard(
                                title: recipe.title,
                                image: recipe.imageUrl,
                                onTap: () => _openRecipe(recipe),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(height: space.snugGap),
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

/// 목록 좌우 여백. 히어로만 여백을 벗어나 화면 끝까지 가야 해서
/// 여백을 ListView 가 아니라 섹션마다 준다.
class _Gutter extends StatelessWidget {
  const _Gutter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.space.screenPaddingX),
      child: child,
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.recipeRepository});

  final RecipeRepository? recipeRepository;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

/// 검색창을 처음 열었을 때 무엇을 칠 수 있는지 보여주는 예시.
/// 카탈로그에서 실제로 결과가 많은 재료들이다.
const _searchHints = ['두부', '계란', '김치', '돼지고기', '양파', '애호박', '감자'];

class _SearchScreenState extends State<SearchScreen> {
  static const _pageSize = 9;

  late final RecipeRepository _searchRecipeRepository;
  late final TextEditingController _titleController;
  late final TextEditingController _ingredientController;

  /// 요리 이름에서 '다음' 을 눌렀을 때 재료로 옮겨 갈 대상.
  /// 이것이 없으면 iOS 에서 다음 키가 아무 일도 하지 않아 키보드가 그대로 남는다.
  late final FocusNode _ingredientFocus;
  late Future<RecipePage> _results;
  String _title = '';
  String _ingredient = '';

  /// 서버 계약대로 0부터 센다. 화면에 보여줄 때만 +1 한다.
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _searchRecipeRepository = widget.recipeRepository ?? _recipeRepository;
    _titleController = TextEditingController();
    _ingredientController = TextEditingController();
    _ingredientFocus = FocusNode();
    _results = _loadResults();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _ingredientController.dispose();
    _ingredientFocus.dispose();
    super.dispose();
  }

  void _openRecipe(RecipeSummary summary) {
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => _RecipeDetailLoader(summary: summary),
            ),
          )
          .then((_) => _retry()),
    );
  }

  Future<RecipePage> _loadResults() {
    return _searchRecipeRepository.search(
      title: _title,
      ingredient: _ingredient,
      page: _page,
      size: _pageSize,
    );
  }

  void _submitSearch() {
    FocusScope.of(context).unfocus();
    setState(() {
      _title = _titleController.text.trim();
      _ingredient = _ingredientController.text.trim();
      _page = 0;
      _results = _loadResults();
    });
  }

  void _clearSearch() {
    _titleController.clear();
    _ingredientController.clear();
    setState(() {
      _title = '';
      _ingredient = '';
      _page = 0;
      _results = _loadResults();
    });
  }

  void _loadPage(int page) {
    if (page == _page) return;
    setState(() {
      _page = page;
      _results = _loadResults();
    });
  }

  void _retry() {
    setState(() => _results = _loadResults());
  }

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final space = context.space;
    return PageShell(
      homeLogo: true,
      title: '검색',
      children: [
        TextField(
          controller: _titleController,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _ingredientFocus.requestFocus(),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search_rounded, color: color.muted),
            labelText: '요리 이름',
            hintText: '예: 가지 탕수육',
          ),
        ),
        SizedBox(height: space.itemGap),
        TextField(
          controller: _ingredientController,
          focusNode: _ingredientFocus,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _submitSearch(),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.kitchen_rounded, color: color.muted),
            labelText: '재료',
            hintText: '예: 두부',
          ),
        ),
        SizedBox(height: space.blockGap),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _submitSearch,
                icon: const Icon(Icons.search_rounded),
                label: const Text('검색'),
              ),
            ),
            SizedBox(width: space.itemGap),
            // 좁은 폭·큰 글꼴에서 잘리지 않도록 Expanded로 폭을 나눠 갖는다.
            Expanded(
              child: OutlinedButton(
                onPressed: _clearSearch,
                child: const Text('초기화'),
              ),
            ),
          ],
        ),
        const SectionTitle('이렇게 찾아보세요'),
        Wrap(
          spacing: space.snugGap,
          runSpacing: space.snugGap,
          children: [
            for (final ingredient in _searchHints)
              ActionChip(
                label: Text(ingredient),
                onPressed: () {
                  _ingredientController.text = ingredient;
                  _submitSearch();
                },
              ),
          ],
        ),
        FutureBuilder<RecipePage>(
          future: _results,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _RecipeLoading();
            }
            if (snapshot.hasError) {
              return _RecipeLoadError(onRetry: _retry);
            }

            final result = snapshot.data;
            final items = result?.items ?? const <RecipeSummary>[];

            if (items.isEmpty) {
              return const _RecipeEmpty(message: '조건에 맞는 레시피가 없어요.');
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionTitle('검색 결과 ${result!.totalElements}'),
                // 사진 그리드. 레시피를 고르는 근거는 사진이라 목록 대신
                // 사진을 3열로 깐다.
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: space.snugGap,
                    mainAxisSpacing: space.snugGap,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final recipe = items[index];
                    return RecipePosterCard(
                      title: recipe.title,
                      image: recipe.imageUrl,
                      width: double.infinity,
                      onTap: () => _openRecipe(recipe),
                    );
                  },
                ),
                SizedBox(height: space.blockGap),
                if (result.totalPages > 1)
                  _RecipePagination(
                    page: result.page,
                    totalPages: result.totalPages,
                    onPageSelected: _loadPage,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RecipePagination extends StatelessWidget {
  const _RecipePagination({
    required this.page,
    required this.totalPages,
    required this.onPageSelected,
  });

  /// 0-base. 화면에는 +1 해서 그린다.
  final int page;
  final int totalPages;
  final ValueChanged<int> onPageSelected;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final space = context.space;
    final canGoBack = page > 0;
    final canGoForward = page < totalPages - 1;

    Widget pageButton({
      required String tooltip,
      required IconData icon,
      required int targetPage,
      required bool enabled,
    }) {
      return IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.standard,
        constraints: BoxConstraints.tightFor(
          width: space.tapTarget,
          height: space.tapTarget,
        ),
        onPressed: enabled ? () => onPageSelected(targetPage) : null,
        icon: Icon(icon),
      );
    }

    // 탭 타겟을 지키면서 360dp 폭 기기에서 한 줄을 유지하려면 컨트롤은
    // 4개(처음·이전·다음·마지막)까지다. ±5 점프를 두면 일곱 개가 한 줄에
    // 못 들어가 마지막 버튼이 다음 줄로 밀린다(메인 저장소 실기기 제보).
    return Padding(
      padding: EdgeInsets.only(top: space.snugGap),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          pageButton(
            tooltip: '처음 페이지',
            icon: Icons.first_page_rounded,
            targetPage: 0,
            enabled: canGoBack,
          ),
          pageButton(
            tooltip: '이전 페이지',
            icon: Icons.chevron_left_rounded,
            targetPage: page - 1,
            enabled: canGoBack,
          ),
          SizedBox(
            width: 72,
            child: Text(
              '${page + 1} / $totalPages',
              textAlign: TextAlign.center,
              style: type.body.copyWith(fontWeight: type.bold),
            ),
          ),
          pageButton(
            tooltip: '다음 페이지',
            icon: Icons.chevron_right_rounded,
            targetPage: page + 1,
            enabled: canGoForward,
          ),
          pageButton(
            tooltip: '마지막 페이지',
            icon: Icons.last_page_rounded,
            targetPage: totalPages - 1,
            enabled: canGoForward,
          ),
        ],
      ),
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
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return PageShell(
      homeLogo: true,
      title: '기록',
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
                style: type.title.copyWith(fontWeight: type.black),
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
                SizedBox(height: space.snugGap),
                Row(
                  children: [
                    for (final day in ['일', '월', '화', '수', '목', '금', '토'])
                      Expanded(
                        child: Text(
                          day,
                          textAlign: TextAlign.center,
                          style: type.small.copyWith(
                            color: color.muted,
                            fontWeight: type.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: space.snugGap),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 7,
                  mainAxisSpacing: space.tightGap,
                  crossAxisSpacing: space.tightGap,
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
                      padding: EdgeInsets.only(bottom: space.itemGap),
                      child: FoodTile(
                        title: entry.recipeTitle,
                        subtitle:
                            '${entry.rating == null ? '평점 없음' : '★ ${entry.rating}'}'
                            '${entry.createdPersonalVersionNumber == null ? '' : ' · 개인 v${entry.createdPersonalVersionNumber}'}',
                        image: entry.recipeImageUrl,
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: color.muted,
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
    final color = context.color;
    final type = context.type;
    final space = context.space;
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
          style: type.titleLarge.copyWith(
            color: color.ink,
            fontWeight: type.black,
          ),
        ),
        SizedBox(height: space.tightGap),
        Text(
          _fullDateLabel(entry.cookedAt),
          style: type.body.copyWith(
            color: color.slate,
            fontWeight: type.semiBold,
          ),
        ),
        SizedBox(height: space.screenPaddingX),
        _CookingResultOverview(entry: entry, recipeSource: recipeSource),
        if (entry.createdPersonalVersionNumber case final int number) ...[
          SizedBox(height: space.blockGap),
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
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return Container(
      padding: EdgeInsets.all(space.cardPadding),
      decoration: BoxDecoration(
        color: color.wash,
        borderRadius: BorderRadius.circular(space.radiusXl),
        border: Border.all(color: color.line),
      ),
      child: Row(
        children: [
          Container(
            width: space.avatarLargeSize,
            height: space.avatarLargeSize,
            decoration: BoxDecoration(
              color: color.accentSoft,
              borderRadius: BorderRadius.circular(space.radiusLg),
            ),
            child: Icon(Icons.restaurant_rounded, color: color.accent),
          ),
          SizedBox(width: space.blockGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipeSource,
                  style: type.caption.copyWith(
                    color: color.slate,
                    fontWeight: type.bold,
                  ),
                ),
                SizedBox(height: space.tightGap),
                Text(
                  _ratingLabel(entry.rating),
                  // 별 문자열이 뭉치지 않도록 이 자리만 자간을 양수로 벌린다.
                  style: type.lead.copyWith(
                    color: color.ink,
                    fontWeight: type.black,
                    letterSpacing: -type.tightTracking,
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
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(space.cardPadding),
      decoration: BoxDecoration(
        color: color.card,
        borderRadius: BorderRadius.circular(space.radiusLg),
        border: Border.all(color: color.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color.accent, size: space.iconLg),
          SizedBox(width: space.itemGap),
          Expanded(
            child: Text(
              text,
              style: type.body.copyWith(
                color: color.ink,
                fontWeight: type.semiBold,
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
    final color = context.color;
    final type = context.type;
    final space = context.space;
    final version = entry.createdPersonalVersionNumber;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: space.iconLg,
            child: Column(
              children: [
                Container(
                  width: space.itemGap,
                  height: space.itemGap,
                  decoration: BoxDecoration(
                    color: color.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: space.hairGap, color: color.line),
                  ),
              ],
            ),
          ),
          SizedBox(width: space.itemGap),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: space.sectionGap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _fullDateLabel(entry.cookedAt),
                    style: type.body.copyWith(
                      color: color.ink,
                      fontWeight: type.extraBold,
                    ),
                  ),
                  SizedBox(height: space.hairGap),
                  Text(
                    '${_ratingLabel(entry.rating)}'
                    '${version == null ? '' : ' · 개인 v$version 생성'}',
                    style: type.caption.copyWith(color: color.slate),
                  ),
                  if (entry.comment case final String comment
                      when comment.isNotEmpty) ...[
                    SizedBox(height: space.tightGap),
                    Text(
                      comment,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: type.body.copyWith(color: color.slate),
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
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return InkWell(
      borderRadius: BorderRadius.circular(space.radiusMd),
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        decoration: BoxDecoration(
          color: selected ? color.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(space.radiusMd),
          border: Border.all(color: selected ? color.accent : color.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: type.body.copyWith(
                color: selected ? color.accent : color.ink,
                fontWeight: selected ? type.black : type.semiBold,
              ),
            ),
            SizedBox(height: space.hairGap),
            if (count > 0)
              Container(
                padding: EdgeInsets.symmetric(horizontal: space.tightGap),
                decoration: BoxDecoration(
                  color: color.accent,
                  borderRadius: BorderRadius.circular(space.radiusPill),
                ),
                child: Text(
                  '$count',
                  style: type.micro.copyWith(
                    color: color.onAccent,
                    fontWeight: type.extraBold,
                  ),
                ),
              )
            else
              SizedBox(height: space.blockGap),
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
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return Container(
      padding: EdgeInsets.all(space.cardPadding),
      decoration: BoxDecoration(
        color: color.surface,
        borderRadius: BorderRadius.circular(space.radiusXl),
        border: Border.all(color: color.line),
      ),
      child: Row(
        children: [
          SizedBox(
            width: space.iconLg,
            height: space.iconLg,
            child: const CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: space.blockGap),
          Expanded(
            child: Text(
              '저장된 진행 상황을 확인하고 있어요.',
              style: type.body.copyWith(
                color: color.slate,
                fontWeight: type.bold,
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
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return Container(
      padding: EdgeInsets.all(space.cardPadding),
      decoration: BoxDecoration(
        color: color.surface,
        borderRadius: BorderRadius.circular(space.radiusXl),
        border: Border.all(color: color.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, color: color.accent),
              SizedBox(width: space.snugGap),
              Expanded(
                child: Text(
                  '저장된 진행 상황을 불러오지 못했어요.',
                  style: type.body.copyWith(
                    color: color.ink,
                    fontWeight: type.extraBold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: space.tightGap),
          Text(
            '후기나 조리 세션이 남아 있을 수 있어요. 다시 확인해 주세요.',
            style: type.caption.copyWith(color: color.slate),
          ),
          SizedBox(height: space.blockGap),
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
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(space.cardPadding),
          decoration: BoxDecoration(
            color: color.accentSoft,
            borderRadius: BorderRadius.circular(space.radiusXl),
            border: Border.all(color: color.line),
          ),
          child: Row(
            children: [
              Container(
                width: space.avatarSize,
                height: space.avatarSize,
                decoration: BoxDecoration(
                  color: color.accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.rate_review_rounded, color: color.onAccent),
              ),
              SizedBox(width: space.blockGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '후기 작성 이어가기',
                      style: type.caption.copyWith(
                        color: color.accent,
                        fontWeight: type.extraBold,
                      ),
                    ),
                    SizedBox(height: space.hairGap),
                    Text(
                      draft.setupSnapshot.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.subtitle.copyWith(
                        color: color.ink,
                        fontWeight: type.extraBold,
                      ),
                    ),
                    SizedBox(height: space.hairGap),
                    Text(
                      '작성 중인 내용을 확인하고 저장해 주세요.',
                      style: type.caption.copyWith(color: color.slate),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color.muted),
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
    required this.opening,
    required this.onTap,
  });

  final PersistedCookingSession session;
  final int stepCount;

  /// 조리 화면을 여는 중. 카드를 잠그고 라벨을 바꾼다.
  final bool opening;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(space.cardPadding),
          decoration: BoxDecoration(
            color: color.accentSoft,
            borderRadius: BorderRadius.circular(space.radiusXl),
            border: Border.all(color: color.line),
          ),
          child: Row(
            children: [
              Container(
                width: space.avatarSize,
                height: space.avatarSize,
                decoration: BoxDecoration(
                  color: color.accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.play_arrow_rounded, color: color.onAccent),
              ),
              SizedBox(width: space.blockGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      opening ? '조리 화면 여는 중' : '이어서 요리하기',
                      style: type.caption.copyWith(
                        color: color.accent,
                        fontWeight: type.extraBold,
                      ),
                    ),
                    SizedBox(height: space.hairGap),
                    Text(
                      session.recipeTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.subtitle.copyWith(
                        color: color.ink,
                        fontWeight: type.extraBold,
                      ),
                    ),
                    SizedBox(height: space.hairGap),
                    Text(
                      '${session.stepIndex + 1} / $stepCount 단계',
                      style: type.caption.copyWith(color: color.slate),
                    ),
                  ],
                ),
              ),
              if (opening)
                SizedBox(
                  width: space.iconLg,
                  height: space.iconLg,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.chevron_right_rounded, color: color.muted),
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
        color: summary.favorite ? context.color.accent : context.color.muted,
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
    return Padding(
      padding: EdgeInsets.only(top: context.space.sectionBreak),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _RecipeLoadError extends StatelessWidget {
  const _RecipeLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return Padding(
      padding: EdgeInsets.only(top: space.sectionBreak),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            color: color.muted,
            size: space.iconHero,
          ),
          SizedBox(height: space.blockGap),
          Text(
            '레시피를 불러오지 못했어요.',
            style: type.body.copyWith(fontWeight: type.bold),
          ),
          SizedBox(height: space.tightGap),
          Text(
            '백엔드 서버 연결을 확인한 뒤 다시 시도해 주세요.',
            textAlign: TextAlign.center,
            style: type.body.copyWith(color: color.slate),
          ),
          SizedBox(height: space.blockGap),
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
      padding: EdgeInsets.only(top: context.space.sectionBreak),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: context.type.body.copyWith(color: context.color.slate),
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
