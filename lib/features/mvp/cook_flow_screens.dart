import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_theme.dart';
import '../../core/identity/uuid_v4.dart';
import '../../design/design_tokens.dart';
import '../cooking/application/cooking_coach_controller.dart';
import '../cooking/application/cooking_ports.dart';
import '../cooking/application/cooking_session_store.dart';
import '../cooking/application/timer_controller.dart';
import '../cooking/data/exception_advice_api.dart';
import '../cooking/data/elevenlabs_coach_controller.dart';
import '../cooking/domain/cooking_setup_snapshot.dart';
import '../cooking/domain/cooking_session_state.dart';
import '../cooking/domain/cooking_voice_router.dart';
import '../cooking/presentation/cooking_voice_session_controller.dart';
import '../cooking/presentation/native_speech_input.dart';
import '../cooking/presentation/native_speech_output.dart';
import '../cooking/presentation/timer_alarm_provider.dart';
import '../cooking/presentation/widgets/help_question_sheet.dart';
import '../recipe/data/recipe_api.dart';
import '../recipe/domain/recipe.dart';
import '../recommendation/data/recommendation_api.dart';
import '../review/application/pending_review_draft_store.dart';
import '../review/application/review_photo_file_store.dart';
import '../review/application/review_photo_upload_port.dart';
import '../review/data/personal_version_approval_api.dart';
import '../review/data/review_api.dart';
import '../review/data/review_photo_upload_api.dart';
import '../review/presentation/review_photo_picker.dart';
import 'cook_layouts/cook_layout.dart';
import 'cook_layouts/cook_layout_catalog.dart';
import 'cook_layouts/cook_session_view_model.dart';
import 'main_shell.dart';
import 'mvp_widgets.dart';

class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen({super.key, required this.recipe});

  final Recipe recipe;

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  final RecipeRepository _recipeRepository = RecipeRepository();
  late bool _isFavorite;
  bool _savingFavorite = false;

  Recipe get recipe => widget.recipe;

  @override
  void initState() {
    super.initState();
    _isFavorite = recipe.favorite;
  }

  Future<void> _toggleFavorite() async {
    if (_savingFavorite) return;
    setState(() => _savingFavorite = true);
    try {
      if (_isFavorite) {
        await _recipeRepository.removeFavorite(recipe.id);
      } else {
        await _recipeRepository.addFavorite(recipe.id);
      }
      if (!mounted) return;
      setState(() => _isFavorite = !_isFavorite);
    } on RecipeApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _savingFavorite = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCook = recipe.steps.isNotEmpty;

    final color = context.color;
    final type = context.type;
    final space = context.space;
    return PopScope(
      canPop: !_savingFavorite,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: space.heroImageHeight,
              pinned: true,
              backgroundColor: color.surface,
              leading: _CircleAction(
                icon: Icons.chevron_left_rounded,
                onTap: () => Navigator.of(context).pop(),
              ),
              actions: [
                _CircleAction(
                  icon: _isFavorite
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_outline_rounded,
                  onTap: _savingFavorite ? null : _toggleFavorite,
                ),
                SizedBox(width: space.tightGap),
                const _CircleAction(icon: Icons.ios_share_rounded),
                SizedBox(width: space.blockGap),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    FoodImage(image: recipe.imageUrl, radius: 0),
                    // 상단 시스템 아이콘, 하단 본문 경계 가독성용 그라데이션.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0, 0.25, 0.8, 1],
                          colors: [
                            color.scrimSoft,
                            Colors.transparent,
                            Colors.transparent,
                            color.scrimSoft.withValues(alpha: 0.2),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  space.screenPaddingX,
                  space.screenPaddingX,
                  space.screenPaddingX,
                  space.majorGap,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(recipe.title, style: type.headline),
                        ),
                        if (recipe.badge != null) ImageLabelChip(recipe.badge!),
                      ],
                    ),
                    SizedBox(height: space.tightGap),
                    Text(
                      recipe.description,
                      style: type.body.copyWith(color: color.slate),
                    ),
                    SizedBox(height: space.sectionGap),
                    // 핵심 스탯 타일 3개
                    Row(
                      children: [
                        _StatTile(
                          icon: Icons.schedule_rounded,
                          label: '타이머 합계',
                          value: '${recipe.timerMinutes}분',
                        ),
                        SizedBox(width: space.itemGap),
                        _StatTile(
                          icon: Icons.format_list_numbered_rounded,
                          label: '조리 단계',
                          value: '${recipe.steps.length}단계',
                        ),
                        SizedBox(width: space.itemGap),
                        _StatTile(
                          icon: Icons.people_alt_rounded,
                          label: '기준',
                          value:
                              '${recipe.baseServings.toStringAsFixed(recipe.baseServings % 1 == 0 ? 0 : 1)}인분',
                        ),
                      ],
                    ),
                    const SectionTitle('필요한 재료'),
                    if (recipe.ingredients.isEmpty)
                      const InfoStrip(
                        icon: Icons.info_outline_rounded,
                        title: '상세 재료 준비 중',
                        body: '이 레시피에는 아직 등록된 재료가 없어요.',
                      )
                    else
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: space.cardPadding,
                          vertical: space.tightGap,
                        ),
                        decoration: BoxDecoration(
                          color: color.card,
                          borderRadius: BorderRadius.circular(space.radiusLg),
                          boxShadow: [
                            BoxShadow(
                              color: color.shadow,
                              blurRadius: space.softShadowBlur,
                              offset: Offset(0, space.softShadowLift),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            for (final (i, item) in recipe.ingredients.indexed)
                              _IngredientRow(
                                item: item,
                                showDivider: i < recipe.ingredients.length - 1,
                              ),
                          ],
                        ),
                      ),
                    const SectionTitle('내 기록'),
                    InfoStrip(
                      icon: Icons.history_rounded,
                      title: recipe.hasPersonalVersion
                          ? '나 맞춤 버전 있음'
                          : '나 맞춤 버전 없음',
                      body: recipe.memorySummary,
                    ),
                    const SectionTitle('조리 순서'),
                    if (recipe.steps.isEmpty)
                      const InfoStrip(
                        icon: Icons.construction_rounded,
                        title: '조리 단계 준비 중',
                        body: '이 레시피에는 아직 등록된 조리 단계가 없어요.',
                      )
                    else
                      for (var i = 0; i < recipe.steps.length; i++)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: color.accentSoft,
                            foregroundColor: color.accent,
                            child: Text(
                              '${i + 1}',
                              style: type.body.copyWith(fontWeight: type.bold),
                            ),
                          ),
                          title: Text(
                            recipe.steps[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.body.copyWith(
                              fontWeight: type.semiBold,
                            ),
                          ),
                          subtitle: Text(
                            recipe.steps[i].timerSeconds == null
                                ? '타이머 없음'
                                : '약 ${recipe.steps[i].minutes}분',
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: EdgeInsets.fromLTRB(
            space.screenPaddingX,
            space.snugGap,
            space.screenPaddingX,
            space.screenPaddingX,
          ),
          child: PressableScale(
            child: FilledButton(
              onPressed: canCook
                  ? () {
                      unawaited(
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => CookSetupScreen(
                              recipe: recipe,
                              recommendationDataSource:
                                  RecommendationRepository(),
                              sessionSpeechOutputFactory:
                                  NativeSpeechOutput.new,
                            ),
                          ),
                        ),
                      );
                    }
                  : null,
              child: Text(canCook ? '조리 설정하기' : '조리 단계 준비 중'),
            ),
          ),
        ),
      ),
    );
  }
}

/// SliverAppBar 위에 얹는 반투명 원형 아이콘 버튼.
class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final space = context.space;
    return Center(
      child: PressableScale(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: space.overlayButtonSize,
            height: space.overlayButtonSize,
            decoration: BoxDecoration(
              color: color.overlaySurface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color.ink, size: space.iconLg),
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: space.blockGap),
        decoration: BoxDecoration(
          color: color.wash,
          borderRadius: BorderRadius.circular(space.radiusLg),
        ),
        child: Column(
          children: [
            Icon(icon, color: color.accent, size: space.iconLg),
            SizedBox(height: space.tightGap),
            Text(
              value,
              style: type.label.copyWith(
                color: color.ink,
                fontWeight: type.bold,
              ),
            ),
            SizedBox(height: space.hairGap),
            Text(label, style: type.small.copyWith(color: color.muted)),
          ],
        ),
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.item, required this.showDivider});

  final Ingredient item;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: space.blockGap),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: type.label.copyWith(color: color.ink),
                    ),
                    SizedBox(height: space.hairGap),
                    Text(
                      item.requirementLabel,
                      style: type.caption.copyWith(color: color.accent),
                    ),
                  ],
                ),
              ),
              Text(
                item.amountLabel,
                style: type.label.copyWith(color: color.slate),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }
}

class CookSetupScreen extends StatefulWidget {
  const CookSetupScreen({
    super.key,
    required this.recipe,
    this.recipeRepository,
    this.recommendationDataSource,
    this.sessionAlarm,
    this.sessionSpeechInput,
    this.sessionSpeechOutputFactory,
    this.cookSessionScreenBuilder,
  });

  final Recipe recipe;
  final RecipeRepository? recipeRepository;
  final RecommendationDataSource? recommendationDataSource;
  final TimerAlarmPort? sessionAlarm;
  final SpeechInputPort? sessionSpeechInput;

  /// Creates a fresh output owner for each cooking session. A completed
  /// session disposes its port, so the instance must not be reused.
  final SpeechOutputPort Function()? sessionSpeechOutputFactory;
  final WidgetBuilder? cookSessionScreenBuilder;

  @override
  State<CookSetupScreen> createState() => _CookSetupScreenState();
}

class _CookSetupScreenState extends State<CookSetupScreen> {
  late int servings;
  late final RecipeRepository _recipeRepository;
  late final RecommendationDataSource? _recommendationDataSource;
  late List<_IngredientSetupDraft> _ingredients;
  late List<CookStep> _steps;
  List<PersonalRecipeVersionSummary> _personalVersions = const [];
  PersonalRecipeVersionDetail? _personalVersion;
  bool _loadingPersonalVersion = false;
  bool _usePersonalVersion = false;
  String? _personalVersionError;
  List<NextCookRecommendation> _recommendations = const [];
  final Set<String> _handledRecommendationIds = {};
  final Set<String> _savingRecommendationIds = {};
  final Map<String, _AppliedRecommendation> _appliedRecommendations = {};
  bool _loadingRecommendations = false;
  String? _recommendationError;
  bool _handsFreeVoiceEnabled = false;
  bool _startingCooking = false;

  @override
  void initState() {
    super.initState();
    _recipeRepository = widget.recipeRepository ?? RecipeRepository();
    _recommendationDataSource = widget.recommendationDataSource;
    servings = widget.recipe.baseServings.round().clamp(1, 99);
    _applySelectedRecipe();
    unawaited(_loadPersonalVersions());
    if (_recommendationDataSource != null) {
      unawaited(_loadRecommendations());
    }
  }

  Future<void> _startCooking() async {
    if (_loadingPersonalVersion || _startingCooking) {
      return;
    }
    // 작성 중인 후기가 있어도 새 조리를 막지 않는다. 후기를 쓸지 말지는
    // 사용자가 정할 일이고, 남은 초안은 홈의 "후기 작성 이어가기" 카드가 알린다.
    setState(() => _startingCooking = true);
    try {
      final snapshot = _buildSnapshot();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              widget.cookSessionScreenBuilder ??
              (_) => CookSessionScreen(
                recipe: snapshot.toExecutionRecipe(),
                servings: servings,
                setupSnapshot: snapshot,
                alarm: widget.sessionAlarm,
                advicePort: HttpExceptionAdvicePort(),
                speechInput: widget.sessionSpeechInput,
                speechOutput: widget.sessionSpeechOutputFactory?.call(),
                handsFreeVoiceEnabled: _handsFreeVoiceEnabled,
              ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _startingCooking = false);
      }
    }
  }

  Future<void> _loadRecommendations() async {
    setState(() {
      _loadingRecommendations = true;
      _recommendationError = null;
    });
    try {
      final result = await _recommendationDataSource!.findForRecipe(
        widget.recipe.id,
      );
      if (!mounted) return;
      setState(() {
        _recommendations = result.recommendations
            .where(
              (item) =>
                  item.type == 'INGREDIENT_AMOUNT' && item.suggestedAmount >= 0,
            )
            .toList(growable: false);
        _loadingRecommendations = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loadingRecommendations = false;
        _recommendationError = '추천을 불러오지 못했지만 기존 설정으로 조리할 수 있어요.';
      });
    }
  }

  Future<void> _loadPersonalVersions() async {
    if (!widget.recipe.hasPersonalVersion) {
      return;
    }
    setState(() {
      _loadingPersonalVersion = true;
      _personalVersionError = null;
    });
    try {
      final versions = await _recipeRepository.findPersonalVersions(
        widget.recipe.id,
      );
      if (!mounted) return;
      setState(() {
        _personalVersions = versions;
        _loadingPersonalVersion = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loadingPersonalVersion = false;
        _personalVersionError = '나 맞춤 버전을 불러오지 못해 기본 레시피로 진행해요.';
      });
    }
  }

  Future<void> _selectPersonalVersion(
    PersonalRecipeVersionSummary? selected,
  ) async {
    if (selected == null) {
      if (!_usePersonalVersion) return;
      setState(() {
        _usePersonalVersion = false;
        _personalVersion = null;
        _personalVersionError = null;
        _applySelectedRecipe();
      });
      return;
    }
    if (_personalVersion?.id == selected.id) return;
    setState(() {
      _loadingPersonalVersion = true;
      _personalVersionError = null;
    });
    try {
      final version = await _recipeRepository.findPersonalVersionDetail(
        selected.id,
      );
      if (version.steps.isEmpty) {
        throw const RecipeApiException('나 맞춤 버전에 조리 단계가 없습니다.');
      }
      if (!mounted) return;
      setState(() {
        _personalVersion = version;
        _usePersonalVersion = true;
        _loadingPersonalVersion = false;
        _applySelectedRecipe();
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _usePersonalVersion = false;
        _personalVersion = null;
        _loadingPersonalVersion = false;
        _personalVersionError = '이 버전을 불러오지 못했어요. 기본 레시피를 이용해주세요.';
        _applySelectedRecipe();
      });
    }
  }

  void _applySelectedRecipe() {
    final personal = _usePersonalVersion ? _personalVersion : null;
    final sourceIngredients =
        personal?.ingredients ?? widget.recipe.ingredients;
    _steps = List<CookStep>.of(personal?.steps ?? widget.recipe.steps);
    final scale = servings / _safeBaseServings;
    _ingredients = personal == null
        ? sourceIngredients
              .map(
                (ingredient) => _IngredientSetupDraft(
                  originalIngredientId: ingredient.originalIngredientId,
                  originalName: ingredient.name,
                  name: ingredient.name,
                  amount: ingredient.amount == null
                      ? null
                      : ingredient.amount! * scale,
                  baselineAmount: ingredient.amount == null
                      ? null
                      : ingredient.amount! * scale,
                  baselineUnit: ingredient.unit,
                  baselineIsRequired: ingredient.isRequired,
                  unit: ingredient.unit,
                  isRequired: ingredient.isRequired,
                ),
              )
              .toList(growable: false)
        : buildOriginalAnchoredSetupIngredients(
            baseIngredients: widget.recipe.ingredients,
            composedIngredients: personal.ingredients,
            scale: scale,
          ).map(_IngredientSetupDraft.fromSnapshot).toList(growable: false);
    _ingredients = _ingredients
        .map((ingredient) {
          final originalIngredientId = ingredient.originalIngredientId;
          final appliedRecommendation = originalIngredientId == null
              ? null
              : _appliedRecommendations[originalIngredientId];
          if (appliedRecommendation == null ||
              ingredient.omitted ||
              !_sameIngredientName(
                ingredient.name,
                appliedRecommendation.ingredientName,
              )) {
            return ingredient;
          }
          return ingredient.copyWith(
            amount: appliedRecommendation.amount * scale,
          );
        })
        .toList(growable: false);
  }

  double get _safeBaseServings =>
      widget.recipe.baseServings > 0 ? widget.recipe.baseServings : 1;

  void _changeServings(int delta) {
    final next = (servings + delta).clamp(1, 99);
    if (next == servings) return;
    final scale = next / servings;
    setState(() {
      servings = next;
      _ingredients = _ingredients
          .map((ingredient) => ingredient.scaled(scale))
          .toList(growable: false);
    });
  }

  CookingSetupSnapshot _buildSnapshot() {
    return CookingSetupSnapshot(
      recipeId: widget.recipe.id,
      title: widget.recipe.title,
      description: widget.recipe.description,
      imageUrl: widget.recipe.imageUrl,
      baseServings: _safeBaseServings,
      targetServings: servings,
      source: _usePersonalVersion
          ? CookingRecipeSource.personal
          : CookingRecipeSource.base,
      personalVersionId: _usePersonalVersion ? _personalVersion?.id : null,
      ingredients: _ingredients
          .map((ingredient) => ingredient.toSnapshot())
          .toList(growable: false),
      steps: _steps
          .map(
            (step) => CookingSetupStep(
              originalStepId: step.originalStepId,
              stepIndex: step.stepIndex,
              instruction: step.instruction,
              timerSeconds: step.timerSeconds,
              cautionNote: step.cautionNote,
              imageUrl: step.imageUrl,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final space = context.space;
    final setupLocked = _loadingPersonalVersion || _startingCooking;
    final visibleRecommendations = _recommendations
        .where(
          (item) => !_handledRecommendationIds.contains(item.recommendationId),
        )
        .toList(growable: false);

    return PageShell(
      title: '조리 설정',
      leading: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      actions: [
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.help_outline_rounded),
        ),
      ],
      children: [
        Wrap(
          spacing: space.snugGap,
          children: [
            ChoiceChip(
              label: const Text('기본'),
              selected: !_usePersonalVersion,
              onSelected: setupLocked
                  ? null
                  : (_) => unawaited(_selectPersonalVersion(null)),
            ),
            for (final version in _personalVersions)
              ChoiceChip(
                label: Text('v${version.versionNumber}'),
                selected: _personalVersion?.id == version.id,
                onSelected: setupLocked
                    ? null
                    : (_) => unawaited(_selectPersonalVersion(version)),
              ),
          ],
        ),
        SizedBox(height: space.blockGap),
        InfoStrip(
          icon: Icons.auto_awesome_rounded,
          title: _loadingPersonalVersion
              ? '개인 버전을 불러오는 중'
              : _usePersonalVersion
              ? _personalVersion!.title
              : '기본 레시피',
          body:
              _personalVersionError ??
              (_loadingPersonalVersion
                  ? '최근 개인 레시피 버전을 확인하고 있어요.'
                  : _usePersonalVersion
                  ? (_personalVersion!.summary.isEmpty
                        ? '저장된 나 맞춤 재료와 조리 단계를 적용했어요.'
                        : _personalVersion!.summary)
                  : widget.recipe.memorySummary),
        ),
        if (_recommendationDataSource != null) ...[
          const SectionTitle('내 기록에서 찾은 추천'),
          if (_loadingRecommendations)
            const InfoStrip(
              icon: Icons.auto_awesome_rounded,
              title: '내 조리 기록을 확인하고 있어요',
              body: '반복해서 만족했던 변경만 골라볼게요.',
            )
          else if (_recommendationError != null)
            InfoStrip(
              icon: Icons.info_outline_rounded,
              title: '추천 없이 진행해요',
              body: _recommendationError!,
            )
          else if (_recommendations.isEmpty)
            const InfoStrip(
              icon: Icons.history_rounded,
              title: '아직 확실한 추천이 없어요',
              body: '비슷한 요리를 만족스럽게 두 번 이상 기록하면 변경안을 제안해요.',
            )
          else if (visibleRecommendations.isEmpty)
            const InfoStrip(
              icon: Icons.check_circle_outline_rounded,
              title: '추천 선택을 반영했어요',
              body: '최종 재료 설정을 확인한 뒤 조리를 시작해주세요.',
            )
          else
            for (final recommendation in visibleRecommendations)
              _buildRecommendationCard(context, recommendation),
        ],
        const SectionTitle('몇 인분인가요?'),
        Row(
          children: [
            PressableScale(
              child: IconButton.filledTonal(
                onPressed: !setupLocked && servings > 1
                    ? () => _changeServings(-1)
                    : null,
                icon: const Icon(Icons.remove_rounded),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '$servings인분',
                  textAlign: TextAlign.center,
                  style: type.title.copyWith(fontWeight: type.black),
                ),
              ),
            ),
            PressableScale(
              child: IconButton.filled(
                onPressed: setupLocked ? null : () => _changeServings(1),
                icon: const Icon(Icons.add_rounded),
              ),
            ),
          ],
        ),
        const SectionTitle('재료 변경'),
        for (final (index, ingredient) in _ingredients.indexed)
          Card(
            child: ListTile(
              title: Text(
                ingredient.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Row(
                children: [
                  Flexible(
                    child: Text(
                      ingredient.omitted
                          ? '이번 조리에서 생략'
                          : ingredient.amountLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (ingredient.isSubstituted) ...[
                    SizedBox(width: space.tightGap),
                    const Pill('대체'),
                  ],
                ],
              ),
              trailing: TextButton(
                onPressed: setupLocked
                    ? null
                    : () => _openIngredientSheet(context, index),
                child: const Text('수정'),
              ),
            ),
          ),
        const SectionTitle('이번 조리 요약'),
        InfoStrip(
          icon: Icons.check_circle_outline_rounded,
          title: '$servings인분 · ${_usePersonalVersion ? '나 맞춤' : '기본'}',
          body:
              '사용 재료 ${_ingredients.where((item) => !item.omitted).length}개'
              ' · 생략 ${_ingredients.where((item) => item.omitted).length}개'
              ' · 조리 ${_steps.length}단계',
        ),
        const SectionTitle('조리 중 음성 사용'),
        Wrap(
          spacing: space.snugGap,
          runSpacing: space.snugGap,
          children: [
            ChoiceChip(
              key: const Key('cooking-voice-mode-manual'),
              label: const Text('버튼으로 사용'),
              selected: !_handsFreeVoiceEnabled,
              onSelected: setupLocked
                  ? null
                  : (_) => setState(() => _handsFreeVoiceEnabled = false),
            ),
            ChoiceChip(
              key: const Key('cooking-voice-mode-hands-free'),
              label: const Text('핸즈프리 음성'),
              selected: _handsFreeVoiceEnabled,
              onSelected: setupLocked
                  ? null
                  : (_) => setState(() => _handsFreeVoiceEnabled = true),
            ),
          ],
        ),
        SizedBox(height: space.blockGap),
        InfoStrip(
          key: const Key('cooking-voice-mode-description'),
          icon: _handsFreeVoiceEnabled
              ? Icons.record_voice_over_rounded
              : Icons.mic_none_rounded,
          title: _handsFreeVoiceEnabled
              ? '조리 시작과 함께 음성을 들어요'
              : '마이크는 자동으로 켜지지 않아요',
          body: _handsFreeVoiceEnabled
              ? '명령을 처리한 뒤 다시 듣습니다. 직접 입력을 열거나 앱을 벗어나면 자동 듣기를 멈춰요.'
              : '기본 설정이에요. 조리 중 말하기 버튼을 누른 경우에만 음성을 사용합니다.',
        ),
      ],
      bottom: PressableScale(
        child: FilledButton(
          onPressed: setupLocked ? null : _startCooking,
          child: Text(
            _loadingPersonalVersion
                ? '나 맞춤 버전 불러오는 중'
                : _startingCooking
                ? '조리 화면 여는 중'
                : '이 설정으로 조리 시작',
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendationCard(
    BuildContext context,
    NextCookRecommendation recommendation,
  ) {
    final scale = servings / _safeBaseServings;
    final originalLabel = _formatAmount(
      recommendation.originalAmount * scale,
      recommendation.unit,
    );
    final suggestedLabel = _formatAmount(
      recommendation.suggestedAmount * scale,
      recommendation.unit,
    );
    final saving = _savingRecommendationIds.contains(
      recommendation.recommendationId,
    );
    final percent = recommendation.changePercent.abs();
    final direction = recommendation.changePercent < 0 ? '감소' : '증가';
    final color = context.color;
    final type = context.type;
    final space = context.space;

    return Card(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          space.sectionGap,
          space.cardPadding,
          space.sectionGap,
          space.blockGap,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: color.accent),
                SizedBox(width: space.snugGap),
                Expanded(
                  child: Text(
                    '${recommendation.ingredientName} $percent% $direction',
                    style: type.subtitle.copyWith(fontWeight: type.black),
                  ),
                ),
                Text(
                  '$originalLabel → $suggestedLabel',
                  style: type.body.copyWith(
                    color: color.slate,
                    fontWeight: type.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: space.snugGap),
            Text(
              recommendation.reason,
              style: type.body.copyWith(color: color.slate),
            ),
            SizedBox(height: space.tightGap),
            Text(
              '근거 ${recommendation.evidence.length}회',
              style: type.small.copyWith(
                color: color.muted,
                fontWeight: type.bold,
              ),
            ),
            SizedBox(height: space.itemGap),
            Wrap(
              spacing: space.snugGap,
              runSpacing: space.snugGap,
              children: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => unawaited(_rejectRecommendation(recommendation)),
                  child: const Text('사용 안 함'),
                ),
                OutlinedButton(
                  onPressed: saving
                      ? null
                      : () => unawaited(
                          _modifyRecommendation(context, recommendation),
                        ),
                  child: const Text('수정'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () => unawaited(
                          _applyRecommendation(
                            recommendation,
                            recommendation.suggestedAmount * scale,
                            RecommendationDecision.accepted,
                          ),
                        ),
                  child: Text(saving ? '저장 중' : '이번 조리에 적용'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rejectRecommendation(
    NextCookRecommendation recommendation,
  ) async {
    if (_savingRecommendationIds.contains(recommendation.recommendationId)) {
      return;
    }
    setState(() {
      _savingRecommendationIds.add(recommendation.recommendationId);
      _handledRecommendationIds.add(recommendation.recommendationId);
    });
    try {
      await _recommendationDataSource!.recordFeedback(
        recipeId: widget.recipe.id,
        recommendation: recommendation,
        decision: RecommendationDecision.rejected,
      );
    } on Object {
      _showRecommendationFeedbackWarning();
    } finally {
      if (mounted) {
        setState(
          () =>
              _savingRecommendationIds.remove(recommendation.recommendationId),
        );
      }
    }
  }

  Future<void> _applyRecommendation(
    NextCookRecommendation recommendation,
    double appliedAmount,
    RecommendationDecision decision,
  ) async {
    if (_savingRecommendationIds.contains(recommendation.recommendationId)) {
      return;
    }
    final ingredientIndex = _ingredients.indexWhere(
      (item) =>
          item.originalIngredientId == recommendation.originalIngredientId,
    );
    if (ingredientIndex < 0) {
      _showRecommendationMessage('현재 재료 목록에서 추천 대상을 찾지 못했어요.');
      return;
    }
    final ingredient = _ingredients[ingredientIndex];
    if (ingredient.omitted ||
        !_sameIngredientName(ingredient.name, recommendation.ingredientName)) {
      _showRecommendationMessage('이 재료가 생략되거나 대체되어 있어 기본 재료로 되돌린 뒤 적용해주세요.');
      return;
    }

    final scale = servings / _safeBaseServings;
    final normalizedAppliedAmount = appliedAmount / scale;
    setState(() {
      _ingredients[ingredientIndex] = ingredient.copyWith(
        amount: appliedAmount,
        omitted: false,
      );
      _appliedRecommendations[recommendation.originalIngredientId] =
          _AppliedRecommendation(
            ingredientName: recommendation.ingredientName,
            amount: normalizedAppliedAmount,
          );
      _savingRecommendationIds.add(recommendation.recommendationId);
      _handledRecommendationIds.add(recommendation.recommendationId);
    });
    try {
      await _recommendationDataSource!.recordFeedback(
        recipeId: widget.recipe.id,
        recommendation: recommendation,
        decision: decision,
        appliedAmount: normalizedAppliedAmount,
      );
    } on Object {
      _showRecommendationFeedbackWarning();
    } finally {
      if (mounted) {
        setState(
          () =>
              _savingRecommendationIds.remove(recommendation.recommendationId),
        );
      }
    }
  }

  Future<void> _modifyRecommendation(
    BuildContext context,
    NextCookRecommendation recommendation,
  ) async {
    final scale = servings / _safeBaseServings;
    var amount = recommendation.suggestedAmount * scale;
    final selectedAmount = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final color = context.color;
            final type = context.type;
            final space = context.space;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                space.screenPaddingX,
                space.hairGap,
                space.screenPaddingX,
                space.majorGap,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${recommendation.ingredientName} 추천 수정',
                    style: type.title.copyWith(fontWeight: type.black),
                  ),
                  SizedBox(height: space.snugGap),
                  Text(
                    recommendation.reason,
                    style: type.body.copyWith(color: color.slate),
                  ),
                  SizedBox(height: space.screenPaddingX),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: amount <= 0
                            ? null
                            : () => setSheetState(
                                () => amount = _adjustAmount(
                                  amount,
                                  recommendation.unit,
                                  -1,
                                ),
                              ),
                        icon: const Icon(Icons.remove_rounded),
                      ),
                      Expanded(
                        child: Text(
                          _formatAmount(amount, recommendation.unit),
                          textAlign: TextAlign.center,
                          style: type.title.copyWith(fontWeight: type.black),
                        ),
                      ),
                      IconButton.filled(
                        onPressed: () => setSheetState(
                          () => amount = _adjustAmount(
                            amount,
                            recommendation.unit,
                            1,
                          ),
                        ),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  SizedBox(height: space.screenPaddingX),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(amount),
                      child: const Text('수정한 양으로 적용'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (!mounted || selectedAmount == null) return;
    await _applyRecommendation(
      recommendation,
      selectedAmount,
      RecommendationDecision.modified,
    );
  }

  void _showRecommendationFeedbackWarning() {
    _showRecommendationMessage('설정은 반영했지만 추천 선택 기록은 저장하지 못했어요.');
  }

  void _showRecommendationMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openIngredientSheet(BuildContext context, int index) async {
    final ingredient = _ingredients[index];
    var mode = ingredient.omitted
        ? _IngredientEditMode.omit
        : ingredient.isSubstituted
        ? _IngredientEditMode.substitute
        : _IngredientEditMode.amount;
    var amount = ingredient.amount;
    var replacementName = ingredient.isSubstituted ? ingredient.name : '';
    String? validationMessage;

    final result = await showModalBottomSheet<_IngredientEditResult>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final color = context.color;
            final type = context.type;
            final space = context.space;
            final amountLabel = _formatAmount(amount, ingredient.unit);
            return Padding(
              padding: EdgeInsets.fromLTRB(
                space.screenPaddingX,
                space.hairGap,
                space.screenPaddingX,
                space.majorGap + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${ingredient.originalName} · ${ingredient.amountLabel}',
                      style: type.title.copyWith(
                        color: color.ink,
                        fontWeight: type.black,
                      ),
                    ),
                    SizedBox(height: space.blockGap),
                    Wrap(
                      spacing: space.snugGap,
                      children: [
                        ChoiceChip(
                          label: const Text('양 조절'),
                          selected: mode == _IngredientEditMode.amount,
                          onSelected: (_) => setSheetState(
                            () => mode = _IngredientEditMode.amount,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('대체'),
                          selected: mode == _IngredientEditMode.substitute,
                          onSelected: (_) => setSheetState(
                            () => mode = _IngredientEditMode.substitute,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('생략'),
                          selected: mode == _IngredientEditMode.omit,
                          onSelected: (_) => setSheetState(
                            () => mode = _IngredientEditMode.omit,
                          ),
                        ),
                      ],
                    ),
                    if (ingredient.isSubstituted) ...[
                      SizedBox(height: space.blockGap),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop(
                              _IngredientEditResult(
                                mode: _IngredientEditMode.restoreOriginal,
                                amount: amount,
                                replacementName: '',
                              ),
                            );
                          },
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: Text(
                            '기본 재료(${ingredient.originalName})로 되돌리기',
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: space.sectionGap),
                    if (mode == _IngredientEditMode.substitute) ...[
                      TextFormField(
                        initialValue: replacementName,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: '대체할 재료',
                          hintText: '예: 쪽파',
                        ),
                        onChanged: (value) => setSheetState(() {
                          replacementName = value;
                          validationMessage = null;
                        }),
                      ),
                      SizedBox(height: space.blockGap),
                      const InfoStrip(
                        icon: Icons.lightbulb_outline_rounded,
                        title: '추천 대체재는 준비 중이에요',
                        body: '지금은 사용할 재료를 직접 입력해주세요.',
                      ),
                    ] else if (mode == _IngredientEditMode.omit) ...[
                      InfoStrip(
                        icon: ingredient.isRequired
                            ? Icons.warning_amber_rounded
                            : Icons.remove_circle_outline_rounded,
                        title: ingredient.isRequired
                            ? '필수 재료를 생략할까요?'
                            : '이번 조리에서 생략해요',
                        body: ingredient.isRequired
                            ? '맛과 조리 결과가 달라질 수 있어요.'
                            : '조리 시작 전까지 다시 변경할 수 있어요.',
                      ),
                    ] else ...[
                      Row(
                        children: [
                          IconButton.filledTonal(
                            onPressed: amount == null || (amount ?? 0) <= 0
                                ? null
                                : () => setSheetState(() {
                                    amount = _adjustAmount(
                                      amount!,
                                      ingredient.unit,
                                      -1,
                                    );
                                  }),
                            icon: const Icon(Icons.remove_rounded),
                          ),
                          Expanded(
                            child: Text(
                              amountLabel,
                              textAlign: TextAlign.center,
                              style: type.lead.copyWith(fontWeight: type.black),
                            ),
                          ),
                          IconButton.filled(
                            onPressed: amount == null
                                ? null
                                : () => setSheetState(() {
                                    amount = _adjustAmount(
                                      amount!,
                                      ingredient.unit,
                                      1,
                                    );
                                  }),
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ],
                      ),
                      SizedBox(height: space.blockGap),
                      const InfoStrip(
                        icon: Icons.calculate_rounded,
                        title: '이 재료의 양만 조절해요',
                        body: '다른 양념 비율은 자동으로 바꾸지 않아요.',
                      ),
                    ],
                    if (validationMessage != null) ...[
                      SizedBox(height: space.snugGap),
                      Text(
                        validationMessage!,
                        style: type.body.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    SizedBox(height: space.sectionGap),
                    PressableScale(
                      child: FilledButton(
                        onPressed: () {
                          final replacement = replacementName.trim();
                          if (mode == _IngredientEditMode.substitute &&
                              replacement.isEmpty) {
                            setSheetState(
                              () => validationMessage = '대체할 재료를 입력해주세요.',
                            );
                            return;
                          }
                          Navigator.of(context).pop(
                            _IngredientEditResult(
                              mode: mode,
                              amount: amount,
                              replacementName: replacement,
                            ),
                          );
                        },
                        child: const Text('적용'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;
    setState(() {
      final originalIngredientId = ingredient.originalIngredientId;
      if (originalIngredientId != null) {
        _appliedRecommendations.remove(originalIngredientId);
      }
      _ingredients[index] = switch (result.mode) {
        _IngredientEditMode.amount => ingredient.copyWith(
          name: ingredient.name,
          amount: result.amount,
          omitted: false,
        ),
        _IngredientEditMode.substitute => ingredient.copyWith(
          name: result.replacementName,
          amount: result.amount,
          omitted: false,
        ),
        _IngredientEditMode.omit => ingredient.copyWith(omitted: true),
        _IngredientEditMode.restoreOriginal => ingredient.copyWith(
          name: ingredient.originalName,
          amount: ingredient.baselineAmount,
          unit: ingredient.baselineUnit,
          isRequired: ingredient.baselineIsRequired,
          omitted: false,
        ),
      };
    });
  }
}

enum _IngredientEditMode { amount, substitute, omit, restoreOriginal }

final class _AppliedRecommendation {
  const _AppliedRecommendation({
    required this.ingredientName,
    required this.amount,
  });

  final String ingredientName;
  final double amount;
}

final class _IngredientEditResult {
  const _IngredientEditResult({
    required this.mode,
    required this.amount,
    required this.replacementName,
  });

  final _IngredientEditMode mode;
  final double? amount;
  final String replacementName;
}

final class _IngredientSetupDraft {
  const _IngredientSetupDraft({
    required this.originalIngredientId,
    required this.originalName,
    required this.name,
    required this.amount,
    required this.baselineAmount,
    required this.baselineUnit,
    required this.baselineIsRequired,
    required this.unit,
    required this.isRequired,
    this.omitted = false,
  });

  factory _IngredientSetupDraft.fromSnapshot(
    CookingSetupIngredient ingredient,
  ) {
    return _IngredientSetupDraft(
      originalIngredientId: ingredient.originalIngredientId,
      originalName: ingredient.originalName,
      name: ingredient.name,
      amount: ingredient.amount,
      baselineAmount: ingredient.baselineAmount,
      baselineUnit: ingredient.baselineUnit ?? ingredient.unit,
      baselineIsRequired:
          ingredient.baselineIsRequired ?? ingredient.isRequired,
      unit: ingredient.unit,
      isRequired: ingredient.isRequired,
      omitted: ingredient.omitted,
    );
  }

  static const _unset = Object();

  final String? originalIngredientId;
  final String originalName;
  final String name;
  final double? amount;
  final double? baselineAmount;
  final String baselineUnit;
  final bool baselineIsRequired;
  final String unit;
  final bool isRequired;
  final bool omitted;

  bool get isSubstituted => originalName != name;
  String get amountLabel => _formatAmount(amount, unit);

  _IngredientSetupDraft scaled(double scale) => _IngredientSetupDraft(
    originalIngredientId: originalIngredientId,
    originalName: originalName,
    name: name,
    amount: amount == null ? null : amount! * scale,
    baselineAmount: baselineAmount == null ? null : baselineAmount! * scale,
    baselineUnit: baselineUnit,
    baselineIsRequired: baselineIsRequired,
    unit: unit,
    isRequired: isRequired,
    omitted: omitted,
  );

  _IngredientSetupDraft copyWith({
    String? name,
    Object? amount = _unset,
    String? unit,
    bool? isRequired,
    bool? omitted,
  }) {
    return _IngredientSetupDraft(
      originalIngredientId: originalIngredientId,
      originalName: originalName,
      name: name ?? this.name,
      amount: identical(amount, _unset) ? this.amount : amount as double?,
      baselineAmount: baselineAmount,
      baselineUnit: baselineUnit,
      baselineIsRequired: baselineIsRequired,
      unit: unit ?? this.unit,
      isRequired: isRequired ?? this.isRequired,
      omitted: omitted ?? this.omitted,
    );
  }

  CookingSetupIngredient toSnapshot() => CookingSetupIngredient(
    originalIngredientId: originalIngredientId,
    originalName: originalName,
    name: name,
    amount: amount,
    baselineAmount: baselineAmount,
    baselineUnit: baselineUnit,
    baselineIsRequired: baselineIsRequired,
    unit: unit,
    isRequired: isRequired,
    omitted: omitted,
  );
}

String _formatAmount(double? amount, String unit) {
  if (amount == null) return unit;
  final value = amount == amount.roundToDouble()
      ? amount.toInt().toString()
      : amount.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '$value$unit';
}

double _adjustAmount(double amount, String unit, int direction) {
  final step = switch (unit.toLowerCase()) {
    'g' || 'ml' => amount >= 100 ? 10.0 : 5.0,
    _ => 0.5,
  };
  final adjusted = amount + step * direction;
  return adjusted < 0 ? 0 : adjusted;
}

bool _sameIngredientName(String left, String right) {
  String normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  return normalize(left) == normalize(right);
}

typedef _CookSpeechPhase = CookingVoiceSpeechPhase;

class CookSessionScreen extends StatefulWidget {
  const CookSessionScreen({
    super.key,
    required this.recipe,
    required this.servings,
    this.setupSnapshot,
    this.restoredSession,
    this.alarm,
    this.alarmResolver,
    this.advicePort,
    this.speechInput,
    this.speechOutput,
    this.handsFreeVoiceEnabled = false,
    this.coachControllerFactory,
    this.pendingReviewDraftStore,
    this.cookingSessionStore,
  });

  final Recipe recipe;
  final int servings;
  final CookingSetupSnapshot? setupSnapshot;

  /// 홈의 "이어서 조리하기"로 진입할 때 전달되는 저장 세션.
  final PersistedCookingSession? restoredSession;

  /// 테스트에서 플랫폼 알림 초기화를 대체하기 위한 주입 지점.
  final TimerAlarmPort? alarm;

  /// 권한 요청을 포함한 비동기 알림 초기화의 테스트 주입 지점.
  /// 실제 구현처럼 앱이 시작한 권한-flow 시작/종료를 callback으로 알린다.
  final TimerAlarmResolver? alarmResolver;

  /// 테스트에서는 fake를 주입하고, 실제 앱에서는 백엔드 F-08 API를 사용한다.
  final ExceptionAdvicePort? advicePort;

  /// 테스트에서는 fake를, 실제 앱에서는 네이티브 STT 구현을 사용한다.
  final SpeechInputPort? speechInput;

  /// 테스트에서는 fake를 주입한다. 실제 앱 진입점은 네이티브 TTS를
  /// 명시적으로 전달한다. 포트 수명은 이 화면이 소유한다.
  final SpeechOutputPort? speechOutput;

  /// 조리 설정에서 사용자가 명시적으로 핸즈프리를 선택한 경우에만 true다.
  ///
  /// false이면 마이크를 자동으로 열지 않고 기존 말하기 버튼으로만 시작한다.
  final bool handsFreeVoiceEnabled;

  /// 테스트에서 fake 포트로 구성한 AI 코치 컨트롤러를 주입한다. null이면
  /// ElevenLabs 엔진을 구성한다.
  final CookingCoachEngine Function(CookingCoachStateHandler onStateChanged)?
  coachControllerFactory;

  /// 테스트에서 완료 draft 저장의 성공·실패·지연을 제어하기 위한 주입 지점.
  final PendingReviewDraftGateway? pendingReviewDraftStore;

  /// 테스트에서 active-session 저장·정리 실패를 제어하기 위한 주입 지점.
  final CookingSessionGateway? cookingSessionStore;

  @override
  State<CookSessionScreen> createState() => _CookSessionScreenState();
}

class _CookSessionScreenState extends State<CookSessionScreen>
    with WidgetsBindingObserver {
  late final CookingSessionGateway _store =
      widget.cookingSessionStore ?? const CookingSessionStore();
  late final PendingReviewDraftGateway _pendingReviewDraftStore =
      widget.pendingReviewDraftStore ?? PendingReviewDraftStore();

  int step = 1;
  late final String _sessionId;
  final Map<int, int> _timerSecondsByStep = <int, int>{};

  // 도움 질문(음성 폴백) 상태. 답변은 현재 단계에 묶이므로 단계가 바뀌면 버린다.
  late final ExceptionAdvicePort _advice =
      widget.advicePort ?? HttpExceptionAdvicePort();
  late final SpeechOutputPort _speechOutput =
      widget.speechOutput ?? DemoSpeechOutput();
  // ElevenLabs WebRTC SDK — 에코 캔슬·음성 barge-in 내장.
  // toolHandlers의 이름은 대시보드 client tool 정의와 정확히 일치해야 한다.
  late final CookingCoachEngine _coach =
      widget.coachControllerFactory?.call(_onCoachStateChanged) ??
      ElevenLabsCoachController(
        agentId: const String.fromEnvironment('ELEVENLABS_AGENT_ID'),
        buildRecipePrompt: _coachRecipePrompt,
        onStateChanged: _onCoachStateChanged,
        toolHandlers: {
          'start_timer': (_) => _startTimerFromVoice(),
          'extend_timer': (args) =>
              _extendTimerFromVoice((args['seconds'] as num?)?.toInt() ?? 0),
          'pause_timer': (_) => _pauseTimerFromVoice(),
          'resume_timer': (_) => _resumeTimerFromVoice(),
          'reset_timer': (_) => _resetTimerFromVoice(),
          'next_step': (_) => _moveCookingStep(1, fromVoice: true),
        },
      );
  CookingCoachPhase _coachPhase = CookingCoachPhase.idle;
  String? _coachMessage;
  late final CookingVoiceSessionController _voiceSession;
  static const CookingVoiceRouter _voiceRouter = CookingVoiceRouter();
  String? _helpAnswer;
  bool _helpLoading = false;
  int _helpRequestVersion = 0;
  int? _helpRequestOwnerVersion;

  bool get _helpRequestInFlight =>
      _helpRequestOwnerVersion == _helpRequestVersion;

  String? _voiceMessage;
  bool _disposed = false;
  int _speechOutputVersion = 0;
  bool _speechOutputActive = false;
  bool _initialSpeechOutputComplete = false;

  bool get _speechOutputEnabled => widget.speechOutput != null;

  // 원래 디자인은 그대로 두고 시계(타이머)만 실제로 동작시킨다.
  // 기본 클럭이 WallAnchoredMonotonicClock이라 화면이 꺼져도 시간이 이어진다.
  final LocalTimerController _timer = LocalTimerController();
  TimerAlarmPort? _alarm;
  TimerAlarmRegistration? _alarmRegistration;
  Future<void> _alarmOperationTail = Future<void>.value();
  late final Future<void> _alarmInitialization;
  late AppLifecycleState _appLifecycleState;
  bool _alarmInitializationComplete = false;
  bool _alarmPermissionFlowActive = false;
  bool _alarmPermissionFlowEndedWhileBackgrounded = false;
  bool _firstFrameRendered = false;
  bool _initialHandsFreeStartPending = false;
  bool _manualSpeechStartPending = false;
  TimerStatus _lastStatus = TimerStatus.idle;

  // 마지막으로 저장한 상태. 타이머가 틱마다 알림을 보내므로 의미 있는
  // 변화(단계·타이머 상태·연장)가 있을 때만 저장한다. 남은 시간은 저장
  // 시각과 함께 기록해 복원 시 재계산하므로 매 틱 저장이 필요 없다.
  int? _persistedStep;
  TimerStatus? _persistedTimerStatus;
  Duration? _persistedTimerEffective;

  // 조리 완료 후 화면 전환 중에도 타이머 콜백이 살아 있으므로,
  // 정리한 저장본을 다시 쓰지 않도록 완료 이후에는 저장을 막는다.
  bool _completed = false;
  bool _closingSession = false;
  bool _allowSessionPop = false;
  bool _finishing = false;
  String? _finishError;
  PendingReviewDraft? _completionDraft;
  Future<void> _persistTail = Future<void>.value();
  int _persistVersion = 0;

  bool get _completionLocked => _completionDraft != null;

  // 음성 finish는 오인식 한 번으로 조리가 통째로 끝나는 비가역 동작이라
  // 확인 발화를 한 번 더 받는다. 화면 버튼 탭은 의도가 명시적이므로 확인
  // 없이 즉시 완료한다.
  bool _voiceFinishPending = false;

  @override
  void initState() {
    super.initState();
    _appLifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _voiceSession = CookingVoiceSessionController(
      speechInput: widget.speechInput ?? NativeSpeechInput(),
      handsFreeEnabled: widget.handsFreeVoiceEnabled,
      initialLifecycleState: _appLifecycleState,
      onStateChanged: _onSpeechStateChanged,
      onTranscript: _handleSpeechUtterance,
    );
    WidgetsBinding.instance.addObserver(this);
    _timer.addListener(_onTimerChanged);
    final restored = widget.restoredSession;
    _sessionId = restored?.sessionId ?? generateUuidV4();
    _timerSecondsByStep.addAll(
      restored?.timerSecondsByStep ?? const <int, int>{},
    );
    if (restored == null) {
      _resetTimerForStep();
    } else {
      // 손상된 저장값이 들어와도 단계 범위 안으로 보정한다.
      final restoredStep = restored.stepIndex + 1;
      step = restoredStep < 1
          ? 1
          : restoredStep > widget.recipe.steps.length
          ? widget.recipe.steps.length
          : restoredStep;
      // 저장 이후 흐른 시간이 차감된 스냅샷으로 타이머를 되살린다.
      _timer.restore(restored.timerSnapshotAt(DateTime.now()));
      _lastStatus = _timer.status;
    }
    _alarmInitialization = _initAlarm();
    unawaited(_observeAlarmInitialization());
    _persist();
    _initialSpeechOutputComplete = !_speechOutputEnabled;
    _initialHandsFreeStartPending = _voiceSession.shouldAutoStartHandsFree;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstFrameRendered = true;
      _startPendingSpeechIfReady();
    });
  }

  Future<void> _observeAlarmInitialization() async {
    // Notification and microphone permissions both drive app lifecycle
    // transitions. Keep every speech start behind this single startup gate.
    await _alarmInitialization;
    if (_disposed) {
      return;
    }
    _alarmInitializationComplete = true;
    _startPendingSpeechIfReady();
  }

  void _startPendingSpeechIfReady() {
    if (_disposed ||
        !mounted ||
        !_firstFrameRendered ||
        !_alarmInitializationComplete ||
        _alarmPermissionFlowActive ||
        _appLifecycleState != AppLifecycleState.resumed) {
      return;
    }
    // The first spoken step owns the audio session before hands-free STT. This
    // prevents the recognizer from hearing CookPilot's own guidance.
    if (!_initialSpeechOutputComplete) {
      if (!_speechOutputActive) {
        unawaited(_speakCurrentStep(completesStartup: true));
      }
      return;
    }
    if (_speechOutputActive) {
      return;
    }
    if (_initialHandsFreeStartPending) {
      _initialHandsFreeStartPending = false;
      _manualSpeechStartPending = false;
      unawaited(_voiceSession.startHandsFree());
      return;
    }
    if (_manualSpeechStartPending) {
      _manualSpeechStartPending = false;
      _voiceSession.toggle();
    }
  }

  Future<void> _initAlarm() async {
    // 백그라운드 알림용 로컬 알림을 한 번 초기화(권한 요청 포함)한다.
    TimerAlarmRegistration? registration;
    try {
      final TimerAlarmPort alarm;
      if (widget.alarm case final injected?) {
        alarm = injected;
      } else if (widget.alarmResolver case final resolver?) {
        registration = resolver(_handleAlarmPermissionFlowChanged);
        _alarmRegistration = registration;
        alarm = await registration.alarm;
      } else {
        registration = resolveTimerAlarm(
          onPermissionFlowChanged: _handleAlarmPermissionFlowChanged,
        );
        _alarmRegistration = registration;
        alarm = await registration.alarm;
      }
      if (!mounted || _completionLocked || _completed || _disposed) {
        await _cancelAlarmBestEffort(alarm);
        return;
      }
      _alarm = alarm;
      // 복원된 타이머가 이미 실행 중이면 종료 알림을 다시 예약한다.
      _scheduleAlarm();
    } catch (_) {
      // 알림 권한이나 플러그인 초기화가 실패해도 화면 타이머와 음성 조리는
      // 계속 사용할 수 있다.
    } finally {
      registration?.cancel();
      if (identical(_alarmRegistration, registration)) {
        _alarmRegistration = null;
      }
    }
  }

  void _handleAlarmPermissionFlowChanged(bool active) {
    if (_disposed) {
      return;
    }
    if (active) {
      _alarmPermissionFlowActive = true;
      _alarmPermissionFlowEndedWhileBackgrounded = false;
      return;
    }
    if (!_alarmPermissionFlowActive) {
      return;
    }
    if (_appLifecycleState != AppLifecycleState.resumed) {
      // Android exact-alarm settings may finish its method-channel call while
      // Settings is still foreground. Keep ownership until our app resumes.
      _alarmPermissionFlowEndedWhileBackgrounded = true;
      return;
    }
    _alarmPermissionFlowActive = false;
    _alarmPermissionFlowEndedWhileBackgrounded = false;
    _startPendingSpeechIfReady();
  }

  bool get _hasPendingSpeechStart =>
      _initialHandsFreeStartPending || _manualSpeechStartPending;

  void _cancelPendingSpeechStarts() {
    _initialHandsFreeStartPending = false;
    _manualSpeechStartPending = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 화면을 다시 켜면 잠든 사이 흐른 시간을 반영해 남은 시간을 재계산한다.
    _appLifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _timer.sync();
    }
    final isOwnedPermissionBackgroundState =
        state == AppLifecycleState.hidden || state == AppLifecycleState.paused;
    final preserveOwnedPermissionStart =
        isOwnedPermissionBackgroundState &&
        _alarmPermissionFlowActive &&
        _hasPendingSpeechStart;
    final cancelsPendingSpeech =
        state == AppLifecycleState.detached ||
        (isOwnedPermissionBackgroundState && !preserveOwnedPermissionStart);
    if (cancelsPendingSpeech) {
      _cancelPendingSpeechStarts();
      // 수명이 무한한 확인은 확인이 아니다 — 10분 뒤 복귀한 사용자의 첫
      // "조리 완료"가 재확인 없이 즉시 종료되는 것을 막는다.
      _voiceFinishPending = false;
    }
    _voiceSession.handleLifecycleStateChanged(
      state,
      preservePendingHandsFreeStart:
          preserveOwnedPermissionStart && _initialHandsFreeStartPending,
    );
    if (state != AppLifecycleState.resumed && _speechOutputActive) {
      unawaited(_stopSpeechOutput());
    }
    // 화면을 벗어나면 마이크 스트리밍을 계속 열어 두지 않는다.
    if (state != AppLifecycleState.resumed &&
        state != AppLifecycleState.inactive &&
        _coach.isActive) {
      unawaited(_coach.stop());
    }
    if (state == AppLifecycleState.resumed) {
      if (_alarmPermissionFlowEndedWhileBackgrounded) {
        _alarmPermissionFlowActive = false;
        _alarmPermissionFlowEndedWhileBackgrounded = false;
      }
      _startPendingSpeechIfReady();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelPendingSpeechStarts();
    _alarmRegistration?.cancel();
    _alarmRegistration = null;
    WidgetsBinding.instance.removeObserver(this);
    _timer.removeListener(_onTimerChanged);
    _voiceSession.dispose();
    _coach.dispose();
    _speechOutput.dispose();
    unawaited(_cancelScheduledAlarm());
    _timer.dispose();
    super.dispose();
  }

  _CookSpeechPhase get _speechPhase => _voiceSession.phase;

  bool get _speechIsActive => _voiceSession.isActive;

  Future<void> _deactivateSpeechInput({
    bool forceStop = false,
    String? message,
    bool rearmHandsFree = false,
  }) => rearmHandsFree
      ? _voiceSession.deactivateAndRearmHandsFree(message: message)
      : _voiceSession.deactivate(forceStop: forceStop, message: message);

  Future<void> _speakCurrentStep({bool completesStartup = false}) =>
      _speakSpeechOutput(
        '$step단계. ${widget.recipe.steps[step - 1].description}',
        completesStartup: completesStartup,
      );

  Future<void> _speakSpeechOutput(
    String text, {
    bool completesStartup = false,
  }) async {
    if (!_speechOutputEnabled) {
      if (completesStartup) {
        _initialSpeechOutputComplete = true;
      }
      return;
    }
    if (_disposed ||
        _completed ||
        _completionLocked ||
        !mounted ||
        _appLifecycleState != AppLifecycleState.resumed) {
      if (completesStartup && !_disposed) {
        _initialSpeechOutputComplete = true;
        _startPendingSpeechIfReady();
      }
      return;
    }

    final outputVersion = ++_speechOutputVersion;
    final shouldRearmHandsFree = _voiceSession.shouldAutoStartHandsFree;
    _speechOutputActive = true;
    _voiceSession.setSpeechOutputActive(true);
    try {
      // A recognizer stop already in flight after a command is awaited here.
      // TTS never starts while the microphone still owns the audio session.
      await _deactivateSpeechInput(forceStop: true);
      if (!_ownsSpeechOutput(outputVersion)) {
        return;
      }
      await _speechOutput.speak(text);
    } on Object {
      // Native output is optional enhancement. Visual instructions, timers,
      // and AI answers remain usable when an engine or voice is unavailable.
    } finally {
      if (_ownsSpeechOutput(outputVersion)) {
        _speechOutputActive = false;
        _voiceSession.setSpeechOutputActive(false);
        if (completesStartup) {
          _initialSpeechOutputComplete = true;
        }
        final hadPendingSpeechStart = _hasPendingSpeechStart;
        _startPendingSpeechIfReady();
        if (!hadPendingSpeechStart &&
            shouldRearmHandsFree &&
            _appLifecycleState == AppLifecycleState.resumed) {
          await _voiceSession.startHandsFree();
        }
      }
    }
  }

  Future<void> _stopSpeechOutput({
    bool rearmHandsFree = false,
    bool completesStartup = false,
  }) async {
    if (!_speechOutputEnabled) {
      if (completesStartup) {
        _initialSpeechOutputComplete = true;
      }
      return;
    }
    final outputVersion = ++_speechOutputVersion;
    final shouldRearmHandsFree =
        rearmHandsFree && _voiceSession.shouldAutoStartHandsFree;
    try {
      await _speechOutput.stop();
    } on Object {
      // Session transitions must never wait on a failed native TTS engine.
    }
    if (!_ownsSpeechOutput(outputVersion)) {
      return;
    }
    _speechOutputActive = false;
    _voiceSession.setSpeechOutputActive(false);
    if (completesStartup) {
      _initialSpeechOutputComplete = true;
    }
    final hadPendingSpeechStart = _hasPendingSpeechStart;
    _startPendingSpeechIfReady();
    if (!hadPendingSpeechStart &&
        shouldRearmHandsFree &&
        _appLifecycleState == AppLifecycleState.resumed) {
      await _voiceSession.startHandsFree();
    }
  }

  bool _ownsSpeechOutput(int outputVersion) =>
      mounted &&
      !_disposed &&
      !_completed &&
      outputVersion == _speechOutputVersion;

  void _stopSpeechOutputForSessionEnd() {
    if (!_speechOutputEnabled) {
      return;
    }
    _speechOutputVersion++;
    _speechOutputActive = false;
    _initialSpeechOutputComplete = true;
    _voiceSession.setSpeechOutputActive(false);
    unawaited(_stopSpeechOutputPortBestEffort());
  }

  Future<void> _stopSpeechOutputPortBestEffort() async {
    try {
      await _speechOutput.stop();
    } on Object {
      // Completion, back navigation, and storage recovery must remain usable
      // even when an injected or native output port rejects its stop future.
    }
  }

  void _toggleSpeechInput() {
    if (_coach.isActive) {
      setState(() => _voiceMessage = 'AI 코치를 끄면 말하기 버튼을 쓸 수 있어요.');
      return;
    }
    if (_speechOutputActive) {
      if (_manualSpeechStartPending) {
        _manualSpeechStartPending = false;
        return;
      }
      _manualSpeechStartPending = true;
      unawaited(_stopSpeechOutput(completesStartup: true));
      return;
    }
    if (_speechIsActive) {
      _manualSpeechStartPending = false;
      _voiceSession.toggle();
      return;
    }
    if (_manualSpeechStartPending) {
      _manualSpeechStartPending = false;
      return;
    }
    _manualSpeechStartPending = true;
    _startPendingSpeechIfReady();
  }

  void _onCoachStateChanged(CookingCoachPhase phase, String? message) {
    if (_disposed || !mounted) {
      return;
    }
    setState(() {
      _coachPhase = phase;
      if (message != null) {
        _coachMessage = message;
      }
    });
  }

  /// ElevenLabs 엔진용 시스템 프롬프트 — Gemini 경로에서는 백엔드가
  /// 토큰에 잠가 보내지만, ElevenLabs는 세션 overrides로 직접 넣는다.
  String _coachRecipePrompt() {
    final recipe = widget.recipe;
    final text = StringBuffer()
      ..writeln(
        '당신은 요리 중인 사용자를 돕는 한국어 음성 코치입니다. '
        '짧고 명확하게 답하고, 위험한 조리 행동은 바로잡아 주세요.',
      )
      ..writeln('지금 진행하는 요리: ${recipe.title}')
      ..writeln('재료:');
    for (final ingredient in recipe.ingredients) {
      text.writeln(
        '- ${ingredient.name} ${ingredient.amountLabel}'
        '${ingredient.isRequired ? '' : ' (선택)'}',
      );
    }
    text.writeln('단계:');
    for (final cookStep in recipe.steps) {
      text.write('${cookStep.stepIndex}. ${cookStep.instruction}');
      if (cookStep.timerSeconds case final seconds?) {
        text.write(' (타이머 $seconds초)');
      }
      if (cookStep.cautionNote case final caution? when caution.isNotEmpty) {
        text.write(' (주의: $caution)');
      }
      text.writeln();
    }
    final currentStep = recipe.steps[step - 1];
    text
      ..writeln('사용자는 지금 $step단계를 진행 중입니다: ${currentStep.instruction}')
      ..writeln(
        '단계가 바뀌면 시스템이 컨텍스트 업데이트로 알려줍니다. '
        '항상 가장 최근에 알려진 단계를 기준으로 안내하세요.',
      )
      ..writeln(
        '타이머를 시작·연장·일시정지·재개·리셋해 달라는 요청은 직접 대답하지 '
        '말고 반드시 해당 도구(start_timer, extend_timer, pause_timer, '
        'resume_timer, reset_timer)를 호출한 뒤, 도구가 돌려준 message를 '
        '읽어주세요. 사용자가 이 단계를 끝냈다고 하거나 다음 단계로 가자고 '
        '하면 next_step 도구를 호출하세요.',
      );
    return text.toString();
  }

  /// 마이크는 하나뿐이다 — 코치를 켜기 전에 명령 STT와 TTS를 먼저 내리고,
  /// 코치가 꺼질 때까지 핸즈프리 재가동도 막는다.
  void _toggleCoach() {
    if (_coach.isActive) {
      unawaited(_coach.stop());
      return;
    }
    _cancelPendingSpeechStarts();
    _voiceSession.disableAutomaticRearm();
    if (_speechIsActive) {
      unawaited(_deactivateSpeechInput(forceStop: true));
    }
    unawaited(_stopSpeechOutput(completesStartup: true));
    unawaited(_coach.start(widget.recipe.id));
  }

  void _onSpeechStateChanged(_CookSpeechPhase phase, String? message) {
    if (_disposed || !mounted) {
      return;
    }
    setState(() {
      // 완료 확인을 기다리는 동안에는 "듣고 있어요" 같은 진행 문구가 확인
      // 질문을 덮어쓰지 않는다. 다만 마이크가 죽는 실패는 음성으로 답할 수
      // 없으므로 확인을 접고 실패 안내(직접 입력 등)를 그대로 보여준다.
      final micUnusable =
          phase == _CookSpeechPhase.permissionDenied ||
          phase == _CookSpeechPhase.unavailable;
      if (micUnusable) {
        _voiceFinishPending = false;
      }
      if (message != null && !_voiceFinishPending) {
        _voiceMessage = message;
      }
    });
  }

  void _handleSpeechUtterance(String transcript) {
    final intent = _voiceRouter.route(
      transcript,
      recipeTitle: widget.recipe.title,
      ingredientNames: [
        for (final ingredient in widget.recipe.ingredients) ingredient.name,
      ],
      currentStepInstruction: widget.recipe.steps[step - 1].instruction,
    );
    _applyVoiceIntent(intent, transcript: transcript);
  }

  void _applyVoiceIntent(VoiceIntent intent, {required String transcript}) {
    if (_disposed || _completed || _completionLocked || !mounted) {
      return;
    }
    // 짧은 토큰 오탐("잠깐만요"→pauseTimer)의 실사용 빈도를 베타에서 관측해
    // 단독 발화 판정 도입 여부를 데이터로 결정하기 위한 로그.
    debugPrint('voice intent: "$transcript" -> ${intent.type.name}');
    // 완료 확인 대기 중 다른 명령이 오면 확인을 취소한다. ignore(소음·잡담)는
    // 사용자의 번복이 아니므로 확인 상태를 유지한다.
    if (intent.type != VoiceIntentType.finish &&
        intent.type != VoiceIntentType.ignore) {
      _voiceFinishPending = false;
    }
    switch (intent.type) {
      case VoiceIntentType.next:
        _moveCookingStep(1, fromVoice: true);
      case VoiceIntentType.previous:
        _moveCookingStep(-1, fromVoice: true);
      case VoiceIntentType.repeat:
        _setVoiceMessage(
          '현재 안내를 다시 보여드릴게요. '
          '${widget.recipe.steps[step - 1].description}',
        );
        unawaited(_speakCurrentStep());
      case VoiceIntentType.currentStep:
        _setVoiceMessage(
          '현재는 $step단계예요. '
          '${widget.recipe.steps[step - 1].description}',
        );
        unawaited(_speakCurrentStep());
      case VoiceIntentType.startTimer:
        _startTimerFromVoice();
      case VoiceIntentType.extendTimer:
        _extendTimerFromVoice(intent.seconds);
      case VoiceIntentType.pauseTimer:
        _pauseTimerFromVoice();
      case VoiceIntentType.resumeTimer:
        _resumeTimerFromVoice();
      case VoiceIntentType.finish:
        _handleVoiceFinish();
      case VoiceIntentType.exceptionQuestion:
        unawaited(_requestAdvice(transcript));
      case VoiceIntentType.ignore:
        if (_voiceFinishPending) {
          _setVoiceMessage('완료 확인 중이에요. 완료하려면 “조리 완료”라고 말해주세요.');
        } else {
          _setVoiceMessage('명령을 이해하지 못했어요. 다시 말하거나 직접 입력을 이용해주세요.');
        }
    }
  }

  void _handleVoiceFinish() {
    if (_voiceFinishPending) {
      _voiceFinishPending = false;
      unawaited(_finishCooking());
      return;
    }
    _voiceFinishPending = true;
    // 마지막 단계 이전의 "조리 완료"는 "이 단계 끝났어"(다음 단계)일 가능성이
    // 높지만, 중도 종료도 정당한 의도라 자동 변환하지 않고 질문이 두 갈래를
    // 안내한다. "다음"이라 답하면 위의 확인 취소 규칙이 그대로 이동을 처리한다.
    // 핸즈프리 사용자는 화면을 보지 않으므로 확인 질문을 소리로도 읽어준다.
    final totalSteps = widget.recipe.steps.length;
    final prompt = step >= totalSteps
        ? '조리를 완료할까요? 완료하려면 “조리 완료”라고 한 번 더 말해주세요.'
        : '아직 마지막 단계가 아니에요($step/$totalSteps단계). 그래도 완료할까요? '
              '완료하려면 “조리 완료”, 다음 단계로 가려면 “다음”이라고 말해주세요.';
    _setVoiceMessage(prompt);
    unawaited(_speakSpeechOutput(prompt));
  }

  void _setVoiceMessage(String message) {
    if (_disposed || _completed || _completionLocked || !mounted) {
      return;
    }
    setState(() => _voiceMessage = message);
  }

  // 반환값은 코치(client tool) 경로가 도구 응답으로 읽어주는 결과 문장이다.
  // STT·버튼 경로는 무시한다.
  String _moveCookingStep(int delta, {required bool fromVoice}) {
    if (_completed || _completionLocked) {
      return '지금은 단계를 이동할 수 없어요.';
    }
    // 화면 버튼 이동도 완료 확인의 번복이다(음성 경로는 _applyVoiceIntent가
    // 이미 취소함).
    _voiceFinishPending = false;
    final target = step + delta;
    if (target < 1) {
      return _voiceResult('첫 단계예요. 이전 단계가 없어요.');
    }
    if (target > widget.recipe.steps.length) {
      return _voiceResult('마지막 단계예요. 완료했다면 “조리 완료”라고 말해주세요.');
    }
    // 화면 버튼으로 이동할 때도 진행 중인 음성 세션을 끊어, 이전 단계에서
    // 시작된 인식 결과가 새 단계에 적용되지 않도록 한다.
    _manualSpeechStartPending = false;
    // Silent/test sessions preserve the original STT-only handoff. Native TTS
    // sessions serialize this same stop inside _speakSpeechOutput instead.
    if (!_speechOutputEnabled && _speechIsActive) {
      unawaited(_deactivateSpeechInput(rearmHandsFree: true));
    }
    _helpRequestVersion++;
    setState(() {
      step = target;
      _helpAnswer = null;
      _helpLoading = false;
      _voiceMessage = fromVoice ? '$target단계로 이동했어요.' : null;
    });
    _resetTimerForStep(keepRecordedDuration: true);
    _persist();
    _notifyCoachOfCurrentStep();
    // 코치가 살아 있으면 로컬 TTS를 내지 않는다 — 코치 음성과 겹치고,
    // TTS 소리가 코치 마이크로 들어가 대화를 오염시킨다. 새 단계 안내는
    // 도구 응답을 코치가 읽는 것으로 대신한다.
    if (!_coach.isActive) {
      // 새 단계 발화가 마이크 정지와 이전 TTS 취소를 직렬화한다. 발화가
      // 끝난 뒤에만 opt-in 된 핸즈프리를 다시 연다.
      unawaited(_speakCurrentStep());
    }
    return '$target단계로 이동했어요. 새 단계 안내: '
        '${widget.recipe.steps[target - 1].instruction}';
  }

  bool get _currentStepHasTimer =>
      widget.recipe.steps[step - 1].timerDuration > Duration.zero;

  /// 코치가 살아 있으면 단계 이동을 실시간으로 알려 세션 컨텍스트를 맞춘다.
  void _notifyCoachOfCurrentStep() {
    if (!_coach.isActive) {
      return;
    }
    final current = widget.recipe.steps[step - 1];
    _coach.updateContext(
      '사용자가 $step단계로 이동했습니다. 현재 단계 안내: ${current.instruction}',
    );
  }

  // 타이머 음성 조작 4종은 결과 문장을 반환한다 — STT 경로는 화면 표시로,
  // 코치(client tool) 경로는 도구 응답으로 같은 문장을 재사용한다.
  String _startTimerFromVoice() {
    if (!_currentStepHasTimer) {
      return _voiceResult('현재 단계에는 설정된 타이머가 없어요.');
    }
    _timer.sync();
    switch (_timer.status) {
      case TimerStatus.idle:
        _timer.start();
        _scheduleAlarm();
        return _voiceResult('타이머를 시작했어요.');
      case TimerStatus.paused:
        _timer.resume();
        _scheduleAlarm();
        return _voiceResult('일시정지한 타이머를 다시 시작했어요.');
      case TimerStatus.running:
        return _voiceResult('타이머가 이미 실행 중이에요.');
      case TimerStatus.elapsed:
        return _voiceResult('타이머가 이미 끝났어요. 시간을 추가하거나 리셋해주세요.');
    }
  }

  String _extendTimerFromVoice(int requestedSeconds) {
    if (!_currentStepHasTimer) {
      return _voiceResult('현재 단계에는 연장할 타이머가 없어요.');
    }
    final seconds = requestedSeconds > 0 ? requestedSeconds : 60;
    final extension = Duration(seconds: seconds);
    _extendCurrentTimer(extension);
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    final amount = switch ((minutes, remainder)) {
      (> 0, 0) => '$minutes분',
      (0, > 0) => '$remainder초',
      _ => '$minutes분 $remainder초',
    };
    final objectParticle = remainder == 0 ? '을' : '를';
    return _voiceResult('타이머에 $amount$objectParticle 추가했어요.');
  }

  String _pauseTimerFromVoice() {
    if (!_currentStepHasTimer) {
      return _voiceResult('현재 단계에는 일시정지할 타이머가 없어요.');
    }
    _timer.sync();
    if (_timer.status != TimerStatus.running) {
      return _voiceResult(
        _timer.status == TimerStatus.elapsed
            ? '타이머가 이미 끝났어요.'
            : '현재 실행 중인 타이머가 없어요.',
      );
    }
    _timer.pause();
    unawaited(_cancelScheduledAlarm());
    return _voiceResult('타이머를 일시정지했어요.');
  }

  String _resumeTimerFromVoice() {
    if (!_currentStepHasTimer) {
      return _voiceResult('현재 단계에는 다시 시작할 타이머가 없어요.');
    }
    if (_timer.status != TimerStatus.paused) {
      return _voiceResult('일시정지된 타이머가 없어요.');
    }
    _timer.resume();
    _scheduleAlarm();
    return _voiceResult('타이머를 다시 시작했어요.');
  }

  String _resetTimerFromVoice() {
    if (!_currentStepHasTimer) {
      return _voiceResult('현재 단계에는 리셋할 타이머가 없어요.');
    }
    // 연장했던 시간까지 버리고 레시피 프리셋 시간으로 되돌린다(정지 상태).
    _resetTimerForStep();
    setState(() {});
    return _voiceResult('타이머를 처음 시간으로 되돌렸어요. 시작하려면 말씀해주세요.');
  }

  String _voiceResult(String message) {
    _setVoiceMessage(message);
    return message;
  }

  Future<void> _finishCooking() async {
    if (_completed || _finishing || !mounted) {
      return;
    }
    PendingReviewDraft draft;
    try {
      draft = _completionDraft ??= PendingReviewDraft(
        clientSessionId: _sessionId,
        cookedAt: DateTime.now(),
        setupSnapshot: _reviewSnapshot(),
        timerSecondsByStep: Map<int, int>.unmodifiable(_timerSecondsByStep),
        rating: 5,
        comment: '',
        nextTimeNote: '',
        approvedPersonalVersionCreation: false,
      );
    } on Object {
      setState(() {
        _finishError = '조리 완료 정보를 준비하지 못했습니다. 잠시 후 다시 시도해주세요.';
      });
      return;
    }

    setState(() {
      _finishing = true;
      _finishError = null;
    });
    _completed = true;
    _stopSpeechOutputForSessionEnd();
    // draft 저장을 기다리는 동안 타이머가 만료되거나, 늦게 초기화된 OS
    // 알림이 다시 예약되지 않도록 완료 시작 시점에 즉시 정지·취소한다.
    if (_timer.status == TimerStatus.running) {
      _timer.pause();
    }
    final alarmCancellation = _cancelScheduledAlarm();
    // 저장을 기다리는 동안 늦은 음성·도움 응답이 frozen draft의 문맥을
    // 바꾸지 못하게 최초 완료 요청 시점에 즉시 무효화한다.
    _helpRequestVersion++;
    _cancelPendingSpeechStarts();
    _voiceSession.complete();
    unawaited(_coach.stop());
    try {
      // 후기 화면으로 넘어가기 전에 완료 사실과 실행 snapshot을 먼저
      // 보존한다. 실패하면 진행 중 세션을 그대로 둔 채 같은 draft로 재시도한다.
      await _pendingReviewDraftStore.save(draft);
      // 예약 작업이 이미 플러그인 안에서 진행 중이어도 그 완료 뒤 취소가
      // 실행되도록 직렬화 큐를 기다린다. 후기 화면에는 알람이 실제로
      // 정리된 뒤에만 진입한다.
      await alarmCancellation;
    } on Object {
      if (!mounted) {
        return;
      }
      _completed = false;
      setState(() {
        _finishing = false;
        _finishError = '조리 완료 정보를 저장하지 못했습니다. 다시 시도해주세요.';
      });
      _persist(force: true);
      return;
    }

    // pending review가 이제 완료 이후의 canonical 복구 단위다. 이 시점부터
    // 타이머 callback이 active cooking session을 다시 쓰지 못하게 막는다.
    try {
      // init/timer callback에서 이미 시작된 active-session 저장이 clear 뒤
      // 늦게 끝나 세션을 되살리지 않도록, 이 화면의 저장 큐를 먼저 비운다.
      await _persistTail;
      await _store.clear();
    } on Object {
      // pending draft 저장이 성공했으므로 active session 정리 실패는 전환을
      // 막지 않는다. Home은 pending review를 항상 우선한다.
    }
    if (!mounted) {
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ReviewScreen(
          initialDraft: draft,
          pendingReviewDraftStore: _pendingReviewDraftStore,
          cookingSessionStore: _store,
        ),
      ),
    );
  }

  void _closeCookingSession() {
    if (!mounted || _closingSession) {
      return;
    }
    _closingSession = true;
    // Invalidate callbacks and begin closing the microphone before the route
    // transition reveals the previous screen.
    _cancelPendingSpeechStarts();
    _stopSpeechOutputForSessionEnd();
    _voiceSession.complete();
    setState(() => _allowSessionPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  void _onTimerChanged() {
    final status = _timer.status;
    if (_disposed || _completed || _completionLocked) {
      _lastStatus = status;
      return;
    }
    if (status == TimerStatus.elapsed && _lastStatus != TimerStatus.elapsed) {
      _alarm?.signalTimerElapsed();
      unawaited(_cancelScheduledAlarm());
    }
    _lastStatus = status;
    _persist();
  }

  void _persist({bool force = false}) {
    if (_completed) {
      return;
    }
    if (!force &&
        step == _persistedStep &&
        _timer.status == _persistedTimerStatus &&
        _timer.effectiveDuration == _persistedTimerEffective) {
      return;
    }
    _persistedStep = step;
    _persistedTimerStatus = _timer.status;
    _persistedTimerEffective = _timer.effectiveDuration;
    final snapshot = _timer.snapshot();
    final persistedSession = PersistedCookingSession(
      sessionId: _sessionId,
      recipeId: widget.recipe.id,
      recipeTitle: widget.recipe.title,
      servings: widget.servings,
      setupSnapshot: widget.setupSnapshot,
      stepIndex: step - 1,
      sessionStatus: CookingSessionStatus.cooking.name,
      timerOriginalMs: snapshot.originalDuration.inMilliseconds,
      timerEffectiveMs: snapshot.effectiveDuration.inMilliseconds,
      timerRemainingMs: snapshot.remaining.inMilliseconds,
      timerStatus: snapshot.status.name,
      savedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      timerSecondsByStep: Map.unmodifiable(_timerSecondsByStep),
    );
    final persistVersion = ++_persistVersion;
    final previousPersist = _persistTail;
    _persistTail = (() async {
      await previousPersist;
      try {
        await _store.save(persistedSession);
      } on Object {
        // 최신 저장도 실패한 경우 dedupe 표식을 되돌려 같은 상태를 다시
        // 저장할 수 있게 한다. 더 최신 요청의 표식은 건드리지 않는다.
        if (_persistVersion == persistVersion) {
          _persistedStep = null;
          _persistedTimerStatus = null;
          _persistedTimerEffective = null;
        }
      }
    })();
  }

  void _resetTimerForStep({bool keepRecordedDuration = false}) {
    if (_completionLocked) {
      return;
    }
    final recordedSeconds = keepRecordedDuration
        ? _timerSecondsByStep[step - 1]
        : null;
    if (!keepRecordedDuration) {
      _timerSecondsByStep.remove(step - 1);
    }
    final duration = recordedSeconds == null
        ? widget.recipe.steps[step - 1].timerDuration
        : Duration(seconds: recordedSeconds);
    _timer.reset(duration, autoStart: false);
    _lastStatus = _timer.status;
    unawaited(_cancelScheduledAlarm());
  }

  void _scheduleAlarm() {
    if (_disposed || _completed || _completionLocked || !mounted) {
      return;
    }
    final alarm = _alarm;
    if (alarm == null ||
        _timer.status != TimerStatus.running ||
        _timer.remaining <= Duration.zero) {
      return;
    }
    final scheduledAt = DateTime.now().add(_timer.remaining);
    unawaited(
      _enqueueAlarmOperation(() async {
        if (_disposed ||
            _completed ||
            _completionLocked ||
            _timer.status != TimerStatus.running) {
          return;
        }
        await alarm.scheduleTimerElapsed(scheduledAt);
      }),
    );
  }

  Future<void> _cancelScheduledAlarm() {
    final alarm = _alarm;
    if (alarm == null) {
      return Future<void>.value();
    }
    return _enqueueAlarmOperation(alarm.cancelScheduledAlarm);
  }

  Future<void> _enqueueAlarmOperation(Future<void> Function() operation) {
    final previous = _alarmOperationTail;
    final next = () async {
      try {
        await previous;
      } on Object {
        // 각 작업은 아래에서 자체 오류를 흡수하지만, 큐는 이전 구현의
        // 예외가 남아 있어도 다음 취소까지 반드시 진행한다.
      }
      try {
        await operation();
      } on Object {
        // 알림 플러그인 실패가 타이머 UI·완료 저장을 막지 않는다.
      }
    }();
    _alarmOperationTail = next;
    return next;
  }

  Future<void> _cancelAlarmBestEffort(TimerAlarmPort? alarm) async {
    if (alarm == null) {
      return;
    }
    try {
      await alarm.cancelScheduledAlarm();
    } on Object {
      // 알림 플러그인 취소 실패가 완료 저장이나 후기 전환을 막지 않는다.
    }
  }

  void _toggleTimer() {
    if (_completionLocked) {
      return;
    }
    switch (_timer.status) {
      case TimerStatus.idle:
        _timer.start();
        _scheduleAlarm();
      case TimerStatus.paused:
        _timer.resume();
        _scheduleAlarm();
      case TimerStatus.running:
        _timer.pause();
        unawaited(_cancelScheduledAlarm());
      case TimerStatus.elapsed:
        break;
    }
  }

  void _addMinute() {
    if (_completionLocked) {
      return;
    }
    // add()는 정지/종료 상태여도 타이머를 다시 진행시킨다.
    _extendCurrentTimer(const Duration(minutes: 1));
  }

  void _extendCurrentTimer(Duration extension) {
    if (_completionLocked) {
      return;
    }
    _timerSecondsByStep[step - 1] =
        _timer.effectiveDuration.inSeconds + extension.inSeconds;
    _timer.add(extension);
    _scheduleAlarm();
  }

  Future<void> _openHelpSheet() async {
    if (_completionLocked) {
      return;
    }
    _cancelPendingSpeechStarts();
    _voiceSession.disableAutomaticRearm();
    if (_speechIsActive) {
      unawaited(_deactivateSpeechInput(message: '음성 입력을 멈췄어요. 질문을 직접 입력해주세요.'));
    }
    final question = await HelpQuestionSheet.show(context);
    if (question == null || !mounted) {
      return;
    }
    await _requestAdvice(question);
  }

  Future<void> _requestAdvice(String question) async {
    final normalizedQuestion = question.trim();
    if (_disposed ||
        _completed ||
        _completionLocked ||
        !mounted ||
        _helpRequestInFlight ||
        normalizedQuestion.isEmpty) {
      return;
    }
    if (normalizedQuestion.characters.length >
        maxExceptionAdviceQuestionLength) {
      setState(() {
        _helpLoading = false;
        _helpAnswer = '질문은 $maxExceptionAdviceQuestionLength자 이하로 줄여주세요.';
      });
      return;
    }
    // A new owned question supersedes any step/advice speech already playing.
    // The network request does not wait for best-effort native cancellation.
    unawaited(_stopSpeechOutput(rearmHandsFree: true, completesStartup: true));
    final requestVersion = ++_helpRequestVersion;
    final requestedStep = step;
    _helpRequestOwnerVersion = requestVersion;
    setState(() {
      _helpLoading = true;
      _helpAnswer = null;
    });
    ExceptionAdvice advice;
    try {
      advice = await _advice.requestAdvice(
        ExceptionAdviceContext(
          sessionId: _sessionId,
          recipeId: widget.recipe.id,
          recipeVersionId: 'mvp',
          stepIndex: requestedStep - 1,
          requestContextVersion: requestVersion,
          utterance: normalizedQuestion,
          recentEvents: const [],
        ),
      );
    } catch (_) {
      if (!_ownsCurrentHelpRequest(requestVersion, requestedStep)) {
        _releaseHelpRequest(requestVersion);
        return;
      }
      setState(() {
        _helpRequestOwnerVersion = null;
        _helpLoading = false;
        _helpAnswer = '답변을 불러오지 못했어요. 버튼과 타이머는 계속 사용할 수 있어요.';
      });
      return;
    }
    // 기다리는 사이 단계가 바뀌었거나 새 요청이 시작됐으면 낡은 답변을
    // 표시하지 않고 새 요청의 진행 상태도 건드리지 않는다.
    if (!_ownsCurrentHelpRequest(requestVersion, requestedStep)) {
      _releaseHelpRequest(requestVersion);
      return;
    }
    setState(() {
      _helpRequestOwnerVersion = null;
      _helpLoading = false;
      _helpAnswer = advice.message;
    });
    // Use the server's separately safety-filtered speech channel, and only
    // after requestVersion + requestedStep ownership has passed above.
    unawaited(_speakSpeechOutput(advice.speechText));
  }

  bool _ownsCurrentHelpRequest(int requestVersion, int requestedStep) =>
      mounted &&
      !_disposed &&
      !_completed &&
      _helpRequestOwnerVersion == requestVersion &&
      _helpRequestVersion == requestVersion &&
      step == requestedStep;

  void _releaseHelpRequest(int requestVersion) {
    if (_helpRequestOwnerVersion == requestVersion) {
      _helpRequestOwnerVersion = null;
    }
  }

  String _timerLabel(int stepMinutes) {
    if (stepMinutes <= 0) {
      return '타이머 없음';
    }
    return switch (_timer.status) {
      TimerStatus.idle => '타이머 시작',
      TimerStatus.running => '일시정지',
      TimerStatus.paused => '계속',
      TimerStatus.elapsed => '시간 종료',
    };
  }

  String get _speechTitle => switch (_speechPhase) {
    _CookSpeechPhase.idle => '음성으로 조리하기',
    _CookSpeechPhase.starting => '마이크 준비 중',
    _CookSpeechPhase.listening => '듣는 중',
    _CookSpeechPhase.stopping => '마이크 정리 중',
    _CookSpeechPhase.permissionDenied => '마이크 권한 필요',
    _CookSpeechPhase.retryRequired => '다시 말해주세요',
    _CookSpeechPhase.unavailable => '음성 입력 사용 불가',
  };

  String get _speechBody =>
      _voiceMessage ?? '단계 이동, 현재 안내, 타이머 조작을 말로 할 수 있어요.';

  String get _speechButtonLabel => switch (_speechPhase) {
    _CookSpeechPhase.starting || _CookSpeechPhase.listening => '듣기 중지',
    _CookSpeechPhase.stopping => '중지 중',
    _CookSpeechPhase.permissionDenied => '권한 다시 확인',
    _CookSpeechPhase.retryRequired => '다시 말하기',
    _CookSpeechPhase.unavailable => '다시 시도',
    _CookSpeechPhase.idle => '말하기',
  };

  IconData get _speechIcon => switch (_speechPhase) {
    _CookSpeechPhase.listening => Icons.graphic_eq_rounded,
    _CookSpeechPhase.permissionDenied => Icons.mic_off_rounded,
    _CookSpeechPhase.unavailable => Icons.error_outline_rounded,
    _ => Icons.mic_rounded,
  };

  @override
  Widget build(BuildContext context) {
    // 코치가 켜져 있어도 조리 UI(단계·타이머)를 그대로 보여준다 — 코치 상태는
    // 코치 버튼 라벨과 coach-status 문구가 나타낸다. 타이머 tool call이
    // 실제로 화면 타이머를 움직이는 것을 눈으로 확인할 수 있어야 한다.
    final current = widget.recipe.steps[step - 1];
    final vm = CookSessionViewModel(
      recipeTitle: widget.recipe.title,
      servings: widget.servings,
      stepNumber: step,
      stepCount: widget.recipe.steps.length,
      stepTitle: current.title,
      stepDescription: current.description,
      stepImageUrl: current.imageUrl.isNotEmpty
          ? current.imageUrl
          : widget.recipe.imageUrl,
      timer: _timer,
      hasTimer: current.timerDuration > Duration.zero,
      timerActionLabel: () => _timerLabel(current.minutes),
      speechPhase: _speechPhase,
      speechIcon: _speechIcon,
      speechTitle: _speechTitle,
      speechBody: _speechBody,
      speechButtonLabel: _speechButtonLabel,
      coachPhase: _coachPhase,
      coachActive: _coach.isActive,
      coachMessage: _coachMessage,
      helpLoading: _helpLoading,
      helpAnswer: _helpAnswer,
      helpRequestInFlight: _helpRequestInFlight,
      finishing: _finishing,
      locked: _completionLocked,
      finishError: _finishError,
      onClose: _closeCookingSession,
      onToggleTimer: _toggleTimer,
      onAddMinute: _addMinute,
      onResetTimer: _resetTimerForStep,
      onToggleSpeech: _toggleSpeechInput,
      onAskHelp: _openHelpSheet,
      onToggleCoach: _toggleCoach,
      onAdvance: () {
        if (step == widget.recipe.steps.length) {
          unawaited(_finishCooking());
        } else {
          _moveCookingStep(1, fromVoice: false);
        }
      },
      onPrevStep: () => _moveCookingStep(-1, fromVoice: false),
    );
    return PopScope(
      key: const Key('cooking-completion-pop-scope'),
      canPop: _allowSessionPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_finishing) {
          _closeCookingSession();
        }
      },
      // 배치만 갈아끼운다. 상태·타이머·음성은 이 클래스가 그대로 갖고 있다.
      child: ValueListenableBuilder<CookLayout>(
        valueListenable: activeCookLayout,
        builder: (context, layout, _) => layout.build(context, vm),
      ),
    );
  }

  CookingSetupSnapshot _reviewSnapshot() {
    final snapshot = widget.setupSnapshot;
    if (snapshot != null) return snapshot;
    return CookingSetupSnapshot(
      recipeId: widget.recipe.id,
      title: widget.recipe.title,
      description: widget.recipe.description,
      imageUrl: widget.recipe.imageUrl,
      baseServings: widget.recipe.baseServings > 0
          ? widget.recipe.baseServings
          : 1,
      targetServings: widget.servings,
      source: CookingRecipeSource.base,
      personalVersionId: null,
      ingredients: [
        for (final ingredient in widget.recipe.ingredients)
          CookingSetupIngredient(
            originalIngredientId: ingredient.originalIngredientId,
            originalName: ingredient.name,
            name: ingredient.name,
            amount: ingredient.amount,
            baselineAmount: ingredient.amount,
            baselineUnit: ingredient.unit,
            baselineIsRequired: ingredient.isRequired,
            unit: ingredient.unit,
            isRequired: ingredient.isRequired,
          ),
      ],
      steps: [
        for (final step in widget.recipe.steps)
          CookingSetupStep(
            originalStepId: step.originalStepId,
            stepIndex: step.stepIndex,
            instruction: step.instruction,
            timerSeconds: step.timerSeconds,
            cautionNote: step.cautionNote,
            imageUrl: step.imageUrl,
          ),
      ],
    );
  }
}

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.initialDraft,
    this.pendingReviewDraftStore,
    this.reviewRepository,
    this.personalVersionApprovalGateway,
    this.cookingSessionStore,
    this.reviewPhotoPicker,
    this.reviewPhotoFileStore,
    this.reviewPhotoUploader,
    this.homeBuilder,
  });

  final PendingReviewDraft initialDraft;
  final PendingReviewDraftGateway? pendingReviewDraftStore;
  final ReviewRepository? reviewRepository;
  final PersonalVersionApprovalGateway? personalVersionApprovalGateway;
  final CookingSessionGateway? cookingSessionStore;
  final ReviewPhotoPickerPort? reviewPhotoPicker;
  final ReviewPhotoFileGateway? reviewPhotoFileStore;
  final ReviewPhotoUploadPort? reviewPhotoUploader;

  /// 저장 뒤 돌아갈 홈 화면. 테스트에서 실제 홈의 네트워크 로딩을 대체한다.
  final WidgetBuilder? homeBuilder;

  CookingSetupSnapshot get setupSnapshot => initialDraft.setupSnapshot;
  String get clientSessionId => initialDraft.clientSessionId;
  DateTime get cookedAt => initialDraft.cookedAt;
  Map<int, int> get timerSecondsByStep => initialDraft.timerSecondsByStep;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen>
    with WidgetsBindingObserver {
  static const _autosaveDelay = Duration(milliseconds: 300);

  late PendingReviewDraft _draft;
  late int rating;
  late bool _approvedPersonalVersionCreation;
  late final PendingReviewDraftGateway _pendingReviewDraftStore;
  late final ReviewRepository _reviewRepository;
  late final PersonalVersionApprovalGateway _personalVersionApprovalGateway;
  late final CookingSessionGateway _cookingSessionStore;
  late final ReviewPhotoPickerPort _photoPicker;
  late final ReviewPhotoFileGateway _photoFileStore;
  late final ReviewPhotoUploadPort _photoUploader;
  late final TextEditingController _commentController;
  late final TextEditingController _nextTimeController;
  Timer? _autosaveTimer;

  // 사진은 첨부 즉시 백그라운드 업로드를 시작한다(선업로드). 저장 버튼에서
  // 몰아서 올리면 여러 장이 수십 초를 막고, 서버 멱등 때문에 첫 리뷰 POST
  // 전에 업로드가 전부 끝나 있어야 하기 때문이다. 아래 상태는 전부
  // draft에 저장하지 않는 화면 세션 한정 값이다.
  static const _maxConcurrentUploads = 3;
  late List<String> _photoPaths;
  final Map<String, String> _absolutePathByRelative = {};
  final Map<String, String> _uploadedUrlByPath = {};
  final Map<String, Future<void>> _uploadFutures = {};
  final Set<String> _uploadingPaths = {};
  final Set<String> _failedUploadPaths = {};
  final List<String> _uploadQueue = [];
  String? _missingPhotoNotice;
  bool _saving = false;
  bool _finalized = false;
  bool _leaving = false;
  bool _allowPop = false;
  bool _completedReviewWithoutPersonalVersion = false;
  ReviewSaveResult? _submittedReview;
  ReviewSaveResult? _saved;
  PersonalVersionApprovalResult? _personalVersionResult;
  String? _draftSaveError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _draft = widget.initialDraft;
    if (_draft.acceptedReviewId case final String acceptedReviewId) {
      _submittedReview = ReviewSaveResult(
        id: acceptedReviewId,
        createdPersonalVersionId: null,
      );
    }
    rating = _draft.rating;
    _approvedPersonalVersionCreation = _draft.approvedPersonalVersionCreation;
    _commentController = TextEditingController(text: _draft.comment);
    _nextTimeController = TextEditingController(text: _draft.nextTimeNote);
    _pendingReviewDraftStore =
        widget.pendingReviewDraftStore ?? PendingReviewDraftStore();
    _reviewRepository = widget.reviewRepository ?? ReviewRepository();
    _personalVersionApprovalGateway =
        widget.personalVersionApprovalGateway ?? PersonalVersionApprovalApi();
    _cookingSessionStore =
        widget.cookingSessionStore ?? const CookingSessionStore();
    _photoPicker = widget.reviewPhotoPicker ?? NativeReviewPhotoPicker();
    _photoFileStore = widget.reviewPhotoFileStore ?? ReviewPhotoFileStore();
    _photoUploader = widget.reviewPhotoUploader ?? ReviewPhotoUploadApi();
    _photoPaths = List<String>.of(_draft.photoPaths);
    unawaited(_restorePhotos());
  }

  bool get _reviewLocked =>
      _saving || _leaving || _submittedReview != null || _saved != null;

  /// 복원된 draft의 사진 중 기기에서 사라진 파일을 걸러내고, 썸네일용
  /// 절대경로를 캐시한 뒤 선업로드를 시작한다.
  Future<void> _restorePhotos() async {
    // 사진 없는 후기가 절대 다수다 — 이 경우 파일 시스템을 아예 건드리지
    // 않아 기존(사진 이전) 플로우의 동작·실패 표면을 그대로 유지한다.
    if (_photoPaths.isEmpty) {
      return;
    }
    final List<String> pruned;
    try {
      pruned = await _photoFileStore.pruneMissing(_photoPaths);
      for (final relativePath in pruned) {
        _absolutePathByRelative[relativePath] = await _photoFileStore
            .resolveAbsolutePath(relativePath);
      }
    } on Object {
      // 문서 디렉토리를 열지 못하면 목록을 보존한다. 썸네일은 placeholder로
      // 남고, 업로드가 실패하면 장별 재시도 배지가 안내한다.
      return;
    }
    final missingCount = _photoPaths.length - pruned.length;
    if (!mounted) {
      return;
    }
    setState(() {
      _photoPaths = pruned;
      if (missingCount > 0) {
        _missingPhotoNotice = '사진 $missingCount장을 기기에서 찾지 못해 제외했어요.';
      }
    });
    if (missingCount > 0 && !_finalized) {
      // 조용히 지우지 않고 안내한 뒤, 남은 목록을 draft에 반영한다.
      unawaited(_flushDraft(surfaceError: false));
    }
    // 서버가 이미 후기를 수락했으면(멱등 재전송은 photoUrls를 무시) 업로드가
    // 무의미하다.
    if (_submittedReview == null && _saved == null) {
      for (final relativePath in pruned) {
        _enqueueUpload(relativePath);
      }
    }
  }

  void _enqueueUpload(String relativePath) {
    if (_uploadedUrlByPath.containsKey(relativePath) ||
        _uploadingPaths.contains(relativePath) ||
        _uploadQueue.contains(relativePath)) {
      return;
    }
    _failedUploadPaths.remove(relativePath);
    _uploadQueue.add(relativePath);
    _pumpUploadQueue();
  }

  void _pumpUploadQueue() {
    while (_uploadingPaths.length < _maxConcurrentUploads &&
        _uploadQueue.isNotEmpty) {
      final relativePath = _uploadQueue.removeAt(0);
      _uploadingPaths.add(relativePath);
      _uploadFutures[relativePath] = _runUpload(relativePath);
    }
  }

  Future<void> _runUpload(String relativePath) async {
    try {
      final absolutePath =
          _absolutePathByRelative[relativePath] ??
          await _photoFileStore.resolveAbsolutePath(relativePath);
      final url = await _photoUploader.upload(absolutePath);
      // 업로드 중 삭제된 사진의 늦은 성공은 버린다.
      if (_photoPaths.contains(relativePath)) {
        _uploadedUrlByPath[relativePath] = url;
      }
    } on Object {
      if (_photoPaths.contains(relativePath)) {
        _failedUploadPaths.add(relativePath);
      }
    } finally {
      _uploadingPaths.remove(relativePath);
      // Map.remove의 반환값(이미 끝난 이 Future 자신)은 대기 대상이 아니다.
      unawaited(_uploadFutures.remove(relativePath));
      if (mounted) {
        setState(() {});
      }
      _pumpUploadQueue();
    }
  }

  /// [relativePaths] 전부의 업로드 완료를 보장한다.
  /// 한 장이라도 실패하면 사용자 안내 문구를 반환하고, 성공하면 null.
  Future<String?> _ensurePhotosUploaded(List<String> relativePaths) async {
    for (final relativePath in relativePaths) {
      _enqueueUpload(relativePath);
    }
    // 동시 업로드 상한 때문에 큐에서 대기 중인 장이 있으므로, 진행 중인
    // 업로드가 끝날 때마다 남은 장을 다시 확인한다.
    while (true) {
      final inFlight = [
        for (final relativePath in relativePaths)
          if (_uploadFutures[relativePath] case final Future<void> future)
            future,
      ];
      if (inFlight.isEmpty) {
        break;
      }
      await Future.wait(inFlight);
    }
    final allUploaded = relativePaths.every(_uploadedUrlByPath.containsKey);
    if (!allUploaded) {
      return '사진을 업로드하지 못했습니다. 실패한 사진을 확인한 뒤 다시 시도해주세요.';
    }
    return null;
  }

  Future<void> _addPhoto() async {
    if (_reviewLocked ||
        _photoPaths.length >= PendingReviewDraft.maximumPhotoCount) {
      return;
    }
    final source = await _pickPhotoSource();
    if (source == null || !mounted) {
      return;
    }
    final String? pickedPath;
    try {
      pickedPath = await _photoPicker.pick(source);
    } on ReviewPhotoPickException catch (error) {
      _showPhotoMessage(switch (error.failure) {
        ReviewPhotoPickFailure.permissionDenied =>
          '설정 > CookPilot에서 카메라 권한을 허용해주세요.',
        ReviewPhotoPickFailure.unavailable => '사진을 가져오지 못했어요. 잠시 후 다시 시도해주세요.',
      });
      return;
    }
    if (pickedPath == null || !mounted) {
      return;
    }
    final String relativePath;
    try {
      // 픽커 결과는 OS가 지울 수 있는 캐시 경로라 즉시 문서 디렉토리로 복사한다.
      relativePath = await _photoFileStore.importPhoto(
        clientSessionId: _draft.clientSessionId,
        sourcePath: pickedPath,
      );
      _absolutePathByRelative[relativePath] = await _photoFileStore
          .resolveAbsolutePath(relativePath);
    } on Object {
      _showPhotoMessage('사진을 기기에 저장하지 못했어요. 저장 공간을 확인해주세요.');
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _photoPaths = [..._photoPaths, relativePath];
      _draftSaveError = null;
      _saveError = null;
    });
    _enqueueUpload(relativePath);
    // 텍스트와 달리 파일 첨부는 debounce 이득이 없고 유실 방지가 우선이다.
    unawaited(_flushDraft(surfaceError: false));
  }

  void _removePhoto(String relativePath) {
    if (_reviewLocked) {
      return;
    }
    setState(() {
      _photoPaths = _photoPaths
          .where((path) => path != relativePath)
          .toList(growable: false);
      _uploadedUrlByPath.remove(relativePath);
      _failedUploadPaths.remove(relativePath);
      _uploadQueue.remove(relativePath);
    });
    unawaited(_photoFileStore.deletePhoto(relativePath));
    unawaited(_flushDraft(surfaceError: false));
  }

  Future<ReviewPhotoSource?> _pickPhotoSource() {
    return showModalBottomSheet<ReviewPhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        key: const Key('review-photo-source-sheet'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('review-photo-source-camera'),
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('카메라로 촬영'),
              onTap: () => Navigator.of(context).pop(ReviewPhotoSource.camera),
            ),
            ListTile(
              key: const Key('review-photo-source-gallery'),
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.of(context).pop(ReviewPhotoSource.gallery),
            ),
            SizedBox(height: context.space.snugGap),
          ],
        ),
      ),
    );
  }

  void _showPhotoMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_finalized) {
      unawaited(_flushDraft(surfaceError: false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosaveTimer?.cancel();
    if (!_finalized) {
      try {
        final latest = _currentDraft();
        unawaited(
          _pendingReviewDraftStore
              .save(latest)
              .onError((Object _, StackTrace _) {}),
        );
      } on Object {
        // 입력 검증 오류는 화면에서 이미 안내한다. dispose 중에는 UI를
        // 갱신할 수 없으므로 기존에 저장된 마지막 정상 draft를 유지한다.
      }
    }
    _commentController.dispose();
    _nextTimeController.dispose();
    super.dispose();
  }

  PendingReviewDraft _currentDraft() {
    return _draft.copyWith(
      rating: rating,
      comment: _commentController.text,
      nextTimeNote: _nextTimeController.text,
      approvedPersonalVersionCreation: _approvedPersonalVersionCreation,
      photoPaths: _photoPaths,
    );
  }

  void _scheduleAutosave() {
    if (_finalized ||
        _saving ||
        _leaving ||
        _submittedReview != null ||
        _saved != null) {
      return;
    }
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDelay, () => unawaited(_flushDraft()));
  }

  void _onTextChanged(String _) {
    if (!mounted ||
        _saving ||
        _leaving ||
        _submittedReview != null ||
        _saved != null) {
      return;
    }
    setState(() {
      _draftSaveError = null;
      _saveError = null;
    });
    _scheduleAutosave();
  }

  void _setRating(int value) {
    if (_saving ||
        _leaving ||
        _submittedReview != null ||
        _saved != null ||
        rating == value) {
      return;
    }
    setState(() {
      rating = value;
      _draftSaveError = null;
      _saveError = null;
    });
    _scheduleAutosave();
  }

  void _setPersonalVersionApproval(bool value) {
    if (_saving ||
        _leaving ||
        _submittedReview != null ||
        _saved != null ||
        _approvedPersonalVersionCreation == value) {
      return;
    }
    setState(() {
      _approvedPersonalVersionCreation = value;
      _draftSaveError = null;
      _saveError = null;
    });
    _scheduleAutosave();
  }

  Future<bool> _flushDraft({bool surfaceError = true}) async {
    if (_finalized) {
      return true;
    }
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    try {
      final latest = _currentDraft();
      await _pendingReviewDraftStore.save(latest);
      _draft = latest;
      if (surfaceError && mounted && _draftSaveError != null) {
        setState(() => _draftSaveError = null);
      }
      return true;
    } on Object {
      if (surfaceError && mounted) {
        setState(() {
          _draftSaveError = '작성 중인 후기를 기기에 저장하지 못했습니다. 다시 시도해주세요.';
        });
      }
      return false;
    }
  }

  Future<void> _leaveAfterDraftFlush() async {
    if (_leaving || _saving || !mounted) {
      return;
    }
    setState(() => _leaving = true);
    if (!_finalized && !await _flushDraft()) {
      if (mounted) {
        setState(() => _leaving = false);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  List<String> get _changeLabels {
    final changes = <String>[];
    for (final ingredient in _draft.setupSnapshot.ingredients) {
      if (ingredient.omitted) {
        changes.add('${ingredient.originalName} 생략');
      } else if (ingredient.isSubstituted) {
        changes.add('${ingredient.originalName} → ${ingredient.name}');
      } else if (!_sameAmount(ingredient.amount, ingredient.baselineAmount)) {
        changes.add(
          '${ingredient.name} '
          '${_formatAmount(ingredient.baselineAmount, ingredient.unit)} → '
          '${_formatAmount(ingredient.amount, ingredient.unit)}',
        );
      }
    }
    for (final MapEntry(key: index, value: seconds)
        in _draft.timerSecondsByStep.entries) {
      if (index < 0 || index >= _draft.setupSnapshot.steps.length) continue;
      final original = _draft.setupSnapshot.steps[index].timerSeconds;
      if (original != seconds) {
        changes.add('${index + 1}단계 타이머 ${_secondsLabel(seconds)}');
      }
    }
    return changes;
  }

  PersonalVersionApprovalRequiresReanchor? get _personalVersionPreflightBlock {
    if (!_approvedPersonalVersionCreation || _saved != null) {
      return null;
    }
    return switch (preflightPersonalVersionApproval(_draft.setupSnapshot)) {
      PersonalVersionApprovalRequiresReanchor block => block,
      PersonalVersionApprovalReady() => null,
    };
  }

  bool get _requiresReviewOnlyRecovery =>
      _draft.acceptedReviewId != null &&
      _submittedReview != null &&
      _personalVersionPreflightBlock != null &&
      _saved == null;

  Future<void> _save({bool completeBlockedAsReviewOnly = false}) async {
    if (_saving || _leaving || _saved != null) return;
    setState(() {
      _saving = true;
      _saveError = null;
      _draftSaveError = null;
    });
    if (!await _flushDraft()) {
      if (mounted) {
        setState(() => _saving = false);
      }
      return;
    }
    final submittedDraft = _draft;
    final personalVersionPreflightBlock =
        submittedDraft.approvedPersonalVersionCreation
        ? switch (preflightPersonalVersionApproval(
            submittedDraft.setupSnapshot,
          )) {
            PersonalVersionApprovalRequiresReanchor block => block,
            PersonalVersionApprovalReady() => null,
          }
        : null;
    final canCompleteBlockedAsReviewOnly =
        completeBlockedAsReviewOnly &&
        personalVersionPreflightBlock != null &&
        submittedDraft.acceptedReviewId != null &&
        _submittedReview != null;
    if (personalVersionPreflightBlock != null &&
        !canCompleteBlockedAsReviewOnly) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError =
              '${personalVersionPreflightBlock.message} '
              '개인 버전 저장 선택을 끄면 후기는 정상 저장할 수 있어요.';
        });
      }
      return;
    }
    // 서버는 같은 clientSessionId 재전송의 photoUrls를 무시하므로, 사진은
    // 첫 리뷰 POST 전에 전부 업로드돼 있어야 한다. 한 장이라도 실패하면
    // 제출을 멈춘다 — 사진 없이 저장되면 그 후기에는 영구히 첨부할 수 없다.
    var photoUrls = const <String>[];
    if (_submittedReview == null && submittedDraft.photoPaths.isNotEmpty) {
      final uploadFailureMessage = await _ensurePhotosUploaded(
        submittedDraft.photoPaths,
      );
      if (uploadFailureMessage != null) {
        if (mounted) {
          setState(() {
            _saving = false;
            _saveError = uploadFailureMessage;
          });
        }
        return;
      }
      photoUrls = [
        for (final relativePath in submittedDraft.photoPaths)
          _uploadedUrlByPath[relativePath]!,
      ];
    }
    var reviewAccepted = _submittedReview != null;
    try {
      final result =
          _submittedReview ??
          await _reviewRepository.submit(
            clientSessionId: submittedDraft.clientSessionId,
            cookedAt: submittedDraft.cookedAt,
            snapshot: submittedDraft.setupSnapshot,
            rating: submittedDraft.rating,
            comment: submittedDraft.comment,
            nextTimeNote: submittedDraft.nextTimeNote,
            photoUrls: photoUrls,
          );
      _submittedReview = result;
      reviewAccepted = true;
      // 수락된 리뷰 id는 승인 여부와 무관하게 즉시 기록한다. 비승인 경로에서도
      // clear 실패 후 재진입이 같은 리뷰를 다시 POST하지 않게 하는 1차
      // 방어다(서버 clientSessionId 멱등은 2차 방어).
      if (submittedDraft.acceptedReviewId == null) {
        _draft = submittedDraft.copyWith(acceptedReviewId: result.id);
        if (!await _flushDraft()) {
          if (mounted) {
            setState(() => _saving = false);
          }
          return;
        }
      }
      PersonalVersionApprovalResult? personalVersionResult;
      if (submittedDraft.approvedPersonalVersionCreation &&
          !canCompleteBlockedAsReviewOnly) {
        personalVersionResult = await _personalVersionApprovalGateway
            .createFromApprovedReview(
              reviewId: result.id,
              snapshot: submittedDraft.setupSnapshot,
            );
      }

      // 늦게 끝난 autosave가 clear 뒤 draft를 되살리지 못하게 먼저 막는다.
      _autosaveTimer?.cancel();
      _autosaveTimer = null;
      _finalized = true;

      final cleanupErrors = <String>[];
      try {
        await _pendingReviewDraftStore.clear();
      } on Object {
        cleanupErrors.add('후기 임시 저장');
      }
      try {
        await _cookingSessionStore.clear();
      } on Object {
        cleanupErrors.add('조리 세션');
      }
      if (submittedDraft.photoPaths.isNotEmpty) {
        try {
          await _photoFileStore.clearSession(submittedDraft.clientSessionId);
        } on Object {
          cleanupErrors.add('후기 사진 파일');
        }
      }
      if (!mounted) return;
      final cleanupWarning = cleanupErrors.isEmpty
          ? null
          : '${cleanupErrors.join('·')} 정리를 완료하지 못해 홈에 다시 표시될 수 있어요.';
      setState(() {
        _saved = result;
        _personalVersionResult = personalVersionResult;
        _completedReviewWithoutPersonalVersion = canCompleteBlockedAsReviewOnly;
        _saving = false;
      });
      // 저장 성공은 홈으로 돌아가면 끝이라 이 화면에 결과를 남기지 않는다.
      // 스낵바는 루트 ScaffoldMessenger가 띄우므로 화면 교체 뒤에도 살아남는다.
      final messenger = ScaffoldMessenger.of(context);
      _goHome();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const Key('review-saved-snack-bar'),
            content: Text(
              cleanupWarning == null
                  ? _successMessage
                  : '$_successMessage $cleanupWarning',
            ),
          ),
        );
    } on ReviewApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error.message;
      });
    } on PersonalVersionApprovalApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError =
            '후기는 저장했지만 개인 버전을 만들지 못했습니다. '
            '${error.message} 같은 내용으로 다시 시도할 수 있어요.';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = reviewAccepted
            ? '후기는 저장했지만 개인 버전을 만들지 못했습니다. '
                  '같은 내용으로 다시 시도할 수 있어요.'
            : '후기를 저장하지 못했습니다. 잠시 후 다시 시도해주세요.';
      });
    }
  }

  void _goHome() {
    final home = widget.homeBuilder ?? (_) => const MainShell();
    unawaited(
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: home),
        (route) => false,
      ),
    );
  }

  String get _successMessage {
    if (_completedReviewWithoutPersonalVersion) {
      return '후기는 저장했고 개인 버전은 만들지 않았어요.';
    }
    if (!_draft.approvedPersonalVersionCreation) {
      return '후기만 저장했어요. 개인 버전은 만들지 않았어요.';
    }
    return switch (_personalVersionResult) {
      PersonalVersionCreated() => '후기와 개인 버전을 저장했어요.',
      PersonalVersionNoChange() => '적용할 변경이 없어 개인 버전은 만들지 않았어요.',
      null => '후기를 저장했어요.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    final changes = _changeLabels;
    final personalVersionPreflightBlock = _personalVersionPreflightBlock;
    final requiresReviewOnlyRecovery = _requiresReviewOnlyRecovery;
    final sourceLabel =
        _draft.setupSnapshot.source == CookingRecipeSource.personal
        ? '개인 버전 기반'
        : '원본 기반';
    final screen = PageShell(
      title: '조리 후 리뷰',
      children: [
        Text(
          '조리 완료! 어땠나요?',
          style: type.titleLarge.copyWith(
            color: color.ink,
            fontWeight: type.black,
          ),
        ),
        SizedBox(height: space.sectionGap),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: space.hairGap,
                children: [
                  for (var i = 1; i <= 5; i++)
                    PressableScale(
                      scale: 0.8,
                      child: IconButton(
                        onPressed:
                            _saving ||
                                _leaving ||
                                _submittedReview != null ||
                                _saved != null
                            ? null
                            : () => _setRating(i),
                        icon: AnimatedSwitcher(
                          duration: AppMotion.fast,
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          child: Icon(
                            Icons.star_rounded,
                            key: ValueKey(i <= rating),
                            color: i <= rating ? color.accent : color.line,
                            size: space.iconXl,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: space.itemGap),
            Text(
              '$rating / 5',
              style: type.body.copyWith(fontWeight: type.black),
            ),
          ],
        ),
        const SectionTitle('이번 조리 요약'),
        InfoStrip(
          icon: Icons.summarize_rounded,
          title: '${_draft.setupSnapshot.targetServings}인분 · $sourceLabel',
          body: changes.isEmpty
              ? '선택한 레시피 그대로 조리했어요. 후기는 조리 기록에 저장돼요.'
              : changes.join(' · '),
        ),
        const SectionTitle('이번 요리 메모'),
        TextField(
          key: const Key('review-comment-field'),
          controller: _commentController,
          enabled:
              !_saving &&
              !_leaving &&
              _submittedReview == null &&
              _saved == null,
          minLines: 3,
          maxLines: 5,
          inputFormatters: const [
            _CodePointLengthLimitingTextInputFormatter(
              PendingReviewDraft.maximumCommentCodePoints,
            ),
          ],
          onChanged: _onTextChanged,
          decoration: InputDecoration(
            hintText: '맛과 조리 결과를 기록해보세요.',
            helperText:
                '${_commentController.text.runes.length}/'
                '${PendingReviewDraft.maximumCommentCodePoints}',
          ),
        ),
        const SectionTitle('다음에는'),
        TextField(
          key: const Key('review-next-time-field'),
          controller: _nextTimeController,
          enabled:
              !_saving &&
              !_leaving &&
              _submittedReview == null &&
              _saved == null,
          minLines: 2,
          maxLines: 4,
          inputFormatters: const [
            _CodePointLengthLimitingTextInputFormatter(
              PendingReviewDraft.maximumNextTimeNoteCodePoints,
            ),
          ],
          onChanged: _onTextChanged,
          decoration: InputDecoration(
            hintText: '다음 조리에 기억할 점을 남겨주세요.',
            helperText:
                '${_nextTimeController.text.runes.length}/'
                '${PendingReviewDraft.maximumNextTimeNoteCodePoints}',
          ),
        ),
        const SectionTitle('요리 사진'),
        if (_missingPhotoNotice case final String notice) ...[
          InfoStrip(
            key: const Key('review-photo-missing-notice'),
            icon: Icons.image_not_supported_outlined,
            title: '일부 사진을 제외했어요',
            body: notice,
          ),
          SizedBox(height: space.snugGap),
        ],
        SizedBox(
          height: space.photoTileSize,
          child: ListView(
            key: const Key('review-photo-strip'),
            scrollDirection: Axis.horizontal,
            children: [
              for (final (index, relativePath) in _photoPaths.indexed) ...[
                _ReviewPhotoThumbnail(
                  key: Key('review-photo-$index'),
                  absolutePath: _absolutePathByRelative[relativePath],
                  uploading:
                      _uploadingPaths.contains(relativePath) ||
                      _uploadQueue.contains(relativePath),
                  failed: _failedUploadPaths.contains(relativePath),
                  locked: _reviewLocked,
                  removeKey: Key('review-photo-remove-$index'),
                  retryKey: Key('review-photo-retry-$index'),
                  onRemove: () => _removePhoto(relativePath),
                  onRetry: () => setState(() => _enqueueUpload(relativePath)),
                ),
                SizedBox(width: space.snugGap),
              ],
              if (_photoPaths.length < PendingReviewDraft.maximumPhotoCount)
                _AddPhotoTile(
                  key: const Key('review-photo-add-button'),
                  count: _photoPaths.length,
                  enabled: !_reviewLocked,
                  onTap: () => unawaited(_addPhoto()),
                ),
            ],
          ),
        ),
        SizedBox(height: space.cardPadding),
        SwitchListTile.adaptive(
          key: const Key('personal-version-opt-in'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            '이번 변경을 개인 버전으로 저장',
            style: type.body.copyWith(fontWeight: type.extraBold),
          ),
          subtitle: const Text('승인한 경우에만 다음 조리에 사용할 개인 레시피를 만들어요.'),
          value: _approvedPersonalVersionCreation,
          onChanged:
              _saving || _leaving || _submittedReview != null || _saved != null
              ? null
              : _setPersonalVersionApproval,
        ),
        if (personalVersionPreflightBlock != null) ...[
          SizedBox(height: space.snugGap),
          InfoStrip(
            key: const Key('review-personal-version-preflight-block'),
            icon: Icons.warning_amber_rounded,
            title: requiresReviewOnlyRecovery
                ? '후기는 이미 저장됐어요'
                : '개인 버전 저장 선택을 확인해주세요',
            body: requiresReviewOnlyRecovery
                ? '${personalVersionPreflightBlock.message} '
                      '후기를 다시 보내지 않고 개인 버전 없이 안전하게 완료할 수 있어요.'
                : '${personalVersionPreflightBlock.message} '
                      '개인 버전 저장 선택을 끄면 후기는 정상 저장할 수 있어요.',
          ),
        ],
        if (changes.isNotEmpty) ...[
          const SectionTitle('자동으로 기록한 변경'),
          Wrap(
            spacing: space.snugGap,
            runSpacing: space.snugGap,
            children: [for (final change in changes) Pill(change)],
          ),
        ],
        if (_draftSaveError case final String error) ...[
          SizedBox(height: space.cardPadding),
          InfoStrip(
            key: const Key('review-draft-save-error'),
            icon: Icons.save_outlined,
            title: '임시 저장이 필요해요',
            body: error,
          ),
        ],
        if (_saveError case final String error) ...[
          SizedBox(height: space.cardPadding),
          InfoStrip(
            icon: Icons.error_outline_rounded,
            title: '저장하지 못했어요',
            body: error,
          ),
        ],
        if (!_saving &&
            _submittedReview != null &&
            _saved == null &&
            !requiresReviewOnlyRecovery) ...[
          SizedBox(height: space.snugGap),
          const InfoStrip(
            key: Key('review-approval-retry-state'),
            icon: Icons.restart_alt_rounded,
            title: '후기는 이미 저장됐어요',
            body: '개인 버전 저장만 같은 후기 기록으로 다시 시도할 수 있어요.',
          ),
        ],
      ],
      bottom: PressableScale(
        child: FilledButton(
          onPressed: _saving || _leaving || _saved != null
              ? null
              : requiresReviewOnlyRecovery
              ? () => _save(completeBlockedAsReviewOnly: true)
              : _save,
          child: Text(
            _saving
                ? '저장 중'
                : requiresReviewOnlyRecovery
                ? '개인 버전 없이 완료'
                // 비승인 재진입은 남은 작업이 정리뿐이라 "개인 버전 다시
                // 저장"이 어울리지 않는다.
                : _submittedReview == null || !_approvedPersonalVersionCreation
                ? '조리 기록 저장'
                : '개인 버전 다시 저장',
          ),
        ),
      ),
    );
    return PopScope(
      key: const Key('review-draft-pop-scope'),
      canPop: _allowPop || (_finalized && !_saving),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_leaveAfterDraftFlush());
        }
      },
      child: screen,
    );
  }
}

final class _ReviewPhotoThumbnail extends StatelessWidget {
  const _ReviewPhotoThumbnail({
    super.key,
    required this.absolutePath,
    required this.uploading,
    required this.failed,
    required this.locked,
    required this.removeKey,
    required this.retryKey,
    required this.onRemove,
    required this.onRetry,
  });

  final String? absolutePath;
  final bool uploading;
  final bool failed;
  final bool locked;
  final Key removeKey;
  final Key retryKey;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return SizedBox(
      width: space.photoTileSize,
      height: space.photoTileSize,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(space.radiusLg),
              child: absolutePath == null
                  ? _placeholder(context)
                  : Image.file(
                      File(absolutePath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _placeholder(context),
                    ),
            ),
          ),
          if (uploading)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(space.radiusLg),
                child: ColoredBox(
                  color: color.scrimSoft,
                  child: Center(
                    child: SizedBox(
                      width: space.iconMd,
                      height: space.iconMd,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color.onInverse,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else if (failed)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(space.radiusLg),
                child: Material(
                  color: color.scrimStrong,
                  child: InkWell(
                    key: retryKey,
                    onTap: locked ? null : onRetry,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          color: color.onInverse,
                          size: space.iconLg,
                        ),
                        Text(
                          '재시도',
                          style: type.tiny.copyWith(color: color.onInverse),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (!locked)
            Positioned(
              top: space.hairGap,
              right: space.hairGap,
              child: InkWell(
                key: removeKey,
                onTap: onRemove,
                customBorder: const CircleBorder(),
                child: Container(
                  padding: EdgeInsets.all(space.hairGap),
                  decoration: BoxDecoration(
                    color: color.scrimStrong,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: space.iconSm,
                    color: color.onInverse,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context) => ColoredBox(
    color: context.color.line,
    child: Icon(Icons.image_outlined, color: context.color.muted),
  );
}

final class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({
    super.key,
    required this.count,
    required this.enabled,
    required this.onTap,
  });

  final int count;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return SizedBox(
      width: space.photoTileSize,
      height: space.photoTileSize,
      child: Material(
        color: color.wash,
        borderRadius: BorderRadius.circular(space.radiusLg),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(space.radiusLg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_a_photo_rounded,
                color: enabled ? color.accent : color.muted,
              ),
              SizedBox(height: space.hairGap),
              Text(
                '$count/${PendingReviewDraft.maximumPhotoCount}',
                style: type.small.copyWith(
                  fontWeight: type.bold,
                  color: color.slate,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _CodePointLengthLimitingTextInputFormatter
    extends TextInputFormatter {
  const _CodePointLengthLimitingTextInputFormatter(this.maximumCodePoints);

  final int maximumCodePoints;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.runes.length <= maximumCodePoints) {
      return newValue;
    }
    // 이미 입력한 내용이 있으면 초과 편집 전체를 거절한다. 새 문자열의 앞부분을
    // 잘라 쓰면 최대 길이에서 중간 삽입할 때 사용자가 건드리지 않은 마지막
    // 글자가 사라지고 IME composing 범위도 깨질 수 있다.
    if (oldValue.text.isNotEmpty &&
        oldValue.text.runes.length <= maximumCodePoints) {
      return oldValue;
    }
    final truncated = String.fromCharCodes(
      newValue.text.runes.take(maximumCodePoints),
    );
    final baseOffset = newValue.selection.baseOffset
        .clamp(0, truncated.length)
        .toInt();
    final extentOffset = newValue.selection.extentOffset
        .clamp(0, truncated.length)
        .toInt();
    final composing = newValue.composing;
    final truncatedComposing =
        composing.isValid &&
            composing.start <= truncated.length &&
            composing.end <= truncated.length
        ? composing
        : TextRange.empty;
    return TextEditingValue(
      text: truncated,
      selection: TextSelection(
        baseOffset: baseOffset,
        extentOffset: extentOffset,
      ),
      composing: truncatedComposing,
    );
  }
}

bool _sameAmount(double? left, double? right) {
  if (left == null || right == null) return left == right;
  return (left - right).abs() < 0.0001;
}

String _secondsLabel(int seconds) {
  if (seconds % 60 == 0) return '${seconds ~/ 60}분';
  return '${seconds ~/ 60}분 ${seconds % 60}초';
}
