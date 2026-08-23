import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../app/cooklog_mark.dart';
import '../../design/design_tokens.dart';
import '../recipe/domain/recipe.dart';
import 'shell_tab.dart';

/// Wraps a tappable child and scales it down slightly on press, so buttons
/// and cards feel like they are listening the instant they're touched.
/// Uses [Listener] rather than a gesture detector so it never competes with
/// the child's own tap handling (InkWell, GestureDetector, etc.).
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.scale = 0.97});

  final Widget child;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: reduceMotion ? Duration.zero : AppMotion.fast,
        curve: AppMotion.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// 어디서든 홈으로 돌아가는 로고. 넷플릭스 좌상단 로고와 같은 자리, 같은 뜻이다.
///
/// 깊이 들어간 화면(레시피 상세 → 조리 설정 → …)에서 뒤로가기를 여러 번 누르는 대신
/// 한 번에 처음으로 돌아온다. 조리 중에는 붙이지 않는다 — 진행 중인 세션을 실수로
/// 날릴 수 있어 그 화면은 X 버튼이 확인을 거쳐 닫는다.
/// 루트로 돌아간 뒤 홈 탭까지 간다. 둘 중 하나만 하면 '검색 탭의 루트'에 남는다.
void goHome(BuildContext context) {
  Navigator.of(context).popUntil((route) => route.isFirst);
  shellTabIndex.value = shellHomeTab;
}

class HomeLogoButton extends StatelessWidget {
  const HomeLogoButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: InkWell(
        key: const Key('home-logo'),
        customBorder: const CircleBorder(),
        onTap: () => goHome(context),
        child: const Padding(
          padding: EdgeInsets.all(8),
          // 헤더에서도 김이 계속 오른다. 정지한 로고보다 살아 있어 보인다.
          child: SteamingCookLogMark(size: 34),
        ),
      ),
    );
  }
}

class PageShell extends StatelessWidget {
  const PageShell({
    super.key,
    required this.children,
    this.title,
    this.actions,
    this.bottom,
    this.leading,
    this.accentHeader = false,
    this.homeLogo = false,
    this.bleed,
  });

  /// 좌우 여백 없이 화면 끝까지 채우는 요소. 목록 맨 위에 놓인다.
  ///
  /// 본문은 여백 안에서 읽히는 편이 낫지만, 히어로는 사진이 화면을 꽉 채워야
  /// 시선을 잡는다. 여백 안에 두면 카드 하나로 보인다.
  final Widget? bleed;

  /// 상단 왼쪽에 홈으로 가는 로고를 붙인다.
  final bool homeLogo;

  /// 상단바를 주황으로 채운다. 조리를 마치고 후기로 넘어왔다는 신호를 색으로 준다 —
  /// 조리 화면에서 나온 직후라 색의 왕복이 흐름의 끝을 만든다.
  final bool accentHeader;

  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    final media = MediaQuery.of(context);
    // 좁은 기기에서는 좌우 여백을 한 단계 줄여 본문 폭을 확보한다.
    final horizontalPadding = media.size.width < 390
        ? space.cardPadding
        : space.screenPaddingX;

    return Scaffold(
      appBar: title == null
          ? null
          : AppBar(
              leading: leading,
              titleSpacing: leading == null && homeLogo ? 0 : null,
              title: Row(
                children: [
                  // 넷플릭스처럼 상단 왼쪽. 뒤로가기가 있으면 그 옆에 붙는다.
                  if (homeLogo) ...[
                    const HomeLogoButton(),
                    SizedBox(width: space.hairGap),
                  ],
                  Flexible(
                    child: Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              actions: actions,
              backgroundColor: accentHeader ? color.accent : null,
              foregroundColor: accentHeader ? color.onAccent : null,
              titleTextStyle: accentHeader
                  ? type.lead.copyWith(color: color.onAccent)
                  : null,
            ),
      body: SafeArea(
        child: ListView(
          // 자식을 하나로 묶지 않는다. Column 으로 싸면 목록이 지연 배치를 잃어
          // 화면 밖 열까지 전부 배치된다.
          padding: EdgeInsets.only(bottom: space.majorGap),
          // 목록을 끌면 키보드를 내린다. 검색 화면에서 키보드가 결과를 가리는데
          // iOS 에는 바깥을 눌러 내리는 기본 동작이 없어 내릴 방법이 사라진다.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            ?bleed,
            SizedBox(height: bleed == null ? space.blockGap : space.hairGap),
            for (final child in children)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: child,
              ),
          ],
        ),
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              minimum: EdgeInsets.fromLTRB(
                horizontalPadding,
                space.snugGap,
                horizontalPadding,
                space.screenPaddingX,
              ),
              child: bottom!,
            ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing, this.onMore});

  final String title;
  final Widget? trailing;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return Padding(
      padding: EdgeInsets.only(top: space.majorGap, bottom: space.blockGap),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: type.title.copyWith(
                fontWeight: type.extraBold,
                color: color.ink,
              ),
            ),
          ),
          ?trailing,
          if (onMore != null)
            GestureDetector(
              onTap: onMore,
              child: Row(
                children: [
                  Text(
                    '더보기',
                    style: type.caption.copyWith(
                      color: color.muted,
                      fontWeight: type.semiBold,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: color.muted,
                    size: space.iconMd,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 음식 사진. URL이 비어 있거나 로드에 실패하면 플레이스홀더로 대체된다.
class FoodImage extends StatelessWidget {
  const FoodImage({
    super.key,
    required this.image,
    this.width,
    this.height,
    this.radius,
    this.fit = BoxFit.cover,
    this.neverUpscale = false,
  });

  final String image;
  final double? width;
  final double? height;

  /// 생략하면 디자인 토큰의 기본 모서리를 쓴다.
  final double? radius;

  /// 칸을 잘라 채울지(cover), 비율을 지켜 여백을 남길지(contain).
  final BoxFit fit;

  /// 원본 픽셀보다 크게 늘려 그리지 않는다. [fit]보다 우선한다.
  ///
  /// 사진을 크게 보여주는 자리에서 원본이 칸보다 작으면 늘어나면서 뭉개진다.
  /// 켜면 여백을 남기더라도 원본 해상도를 지킨다.
  final bool neverUpscale;

  Widget _placeholder(BuildContext context) {
    final color = context.color;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.placeholderFrom, color.placeholderTo],
        ),
      ),
      child: Icon(
        Icons.restaurant_rounded,
        color: color.placeholderIcon,
        size: context.space.iconXl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 디코딩 해상도를 표시 크기로 제한한다. 시드 데이터에 원본급 사진(최대 30MP,
    // 장당 디코딩 ~112MB)이 섞여 있어, 제한 없이 디코딩하면 목록 스크롤만으로
    // iOS 메모리 상한(EXC_RESOURCE)에 걸려 앱이 강제 종료된다.
    // width가 double.infinity로 오는 채움형 배치가 있어(조리 화면 등) 유한한
    // 값일 때만 쓰고, 아니면 화면 폭을 상한으로 삼는다.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final logicalWidth = (width != null && width!.isFinite)
        ? width!
        : MediaQuery.sizeOf(context).width;
    final cacheWidth = (logicalWidth * dpr).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? context.space.radiusLg),
      child: image.isEmpty
          ? _placeholder(context)
          : Image.network(
              image,
              width: width,
              height: height,
              cacheWidth: cacheWidth,
              // scale이 원본의 논리 크기를 정한다. 화면 배율을 넣어야 scaleDown이
              // "실제 픽셀 1:1"에서 멈추고, 그 위로는 늘리지 않는다.
              scale: neverUpscale
                  ? MediaQuery.devicePixelRatioOf(context)
                  : 1.0,
              fit: neverUpscale ? BoxFit.scaleDown : fit,
              errorBuilder: (context, error, stack) => _placeholder(context),
            ),
    );
  }
}

/// 평점 뱃지 — 파프리카 별 + 점수 (+선택적 리뷰 수).
class RatingBadge extends StatelessWidget {
  const RatingBadge(this.rating, {super.key, this.reviewCount});

  final double rating;
  final int? reviewCount;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, color: color.accent, size: space.iconSm),
        SizedBox(width: space.hairGap),
        Text(
          rating.toStringAsFixed(1),
          style: type.caption.copyWith(color: color.ink, fontWeight: type.bold),
        ),
        if (reviewCount != null) ...[
          SizedBox(width: space.hairGap),
          Text(
            '(${reviewCount! >= 1000 ? '${(reviewCount! / 1000).toStringAsFixed(1)}k' : reviewCount})',
            style: type.small.copyWith(color: color.muted),
          ),
        ],
      ],
    );
  }
}

/// 이미지 위에 얹는 작은 라벨 칩.
class ImageLabelChip extends StatelessWidget {
  const ImageLabelChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return Container(
      padding: space.chipInsets,
      decoration: BoxDecoration(
        color: color.accent,
        borderRadius: BorderRadius.circular(space.radiusSm),
      ),
      child: Text(
        label,
        style: type.tiny.copyWith(color: color.onAccent, fontWeight: type.bold),
      ),
    );
  }
}

/// 레시피 분류·해시태그처럼 여러 개가 나란히 놓이는 조용한 칩.
///
/// [ImageLabelChip]은 포인트 색이라 한 화면에 하나만 놓을 때 쓴다. 태그는 개수가
/// 많아서 그 색으로 깔면 제목을 이긴다.
class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return Container(
      padding: space.chipInsets,
      decoration: BoxDecoration(
        color: color.wash,
        borderRadius: BorderRadius.circular(space.radiusPill),
        border: Border.all(color: color.line),
      ),
      child: Text(
        label,
        style: type.tiny.copyWith(color: color.slate, fontWeight: type.medium),
      ),
    );
  }
}

/// 검색 결과·목록용 가로형 타일. 실제 음식 썸네일 포함.
class FoodTile extends StatelessWidget {
  const FoodTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.image,
    this.rating,
    this.reviewCount,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String image;
  final double? rating;
  final int? reviewCount;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    final thumb = FoodImage(
      image: image,
      width: space.thumbSize,
      height: space.thumbSize,
    );

    return PressableScale(
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(space.radiusXl),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(space.blockGap),
            child: Row(
              children: [
                thumb,
                SizedBox(width: space.blockGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.subtitle.copyWith(color: color.ink),
                      ),
                      SizedBox(height: space.hairGap),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.caption.copyWith(color: color.slate),
                      ),
                      if (rating != null) ...[
                        SizedBox(height: space.tightGap),
                        RatingBadge(rating!, reviewCount: reviewCount),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 홈 상단 '오늘의 추천' — 화면 끝까지 닿는 히어로. 이 화면의 시그니처 요소다.
/// 눈썹 문구 → 큰 제목 → 메타 한 줄 → 버튼 두 개 순서를 유지한다.
class RecipeHeroCard extends StatelessWidget {
  const RecipeHeroCard({
    super.key,
    required this.recipe,
    this.onTap,
    this.onStart,
    this.onSave,
    this.saving = false,
    this.favorite,
  });

  final Recipe recipe;
  final VoidCallback? onTap;
  final VoidCallback? onStart;
  final VoidCallback? onSave;

  /// 저장 요청이 도는 동안 버튼을 잠근다.
  final bool saving;

  /// 저장 여부를 화면에서 먼저 뒤집어 보여줄 때 쓴다.
  /// null 이면 레시피가 들고 온 값을 그대로 쓴다.
  final bool? favorite;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    final servings = recipe.baseServings.toStringAsFixed(
      recipe.baseServings % 1 == 0 ? 0 : 1,
    );
    final saved = favorite ?? recipe.favorite;
    final meta =
        '${recipe.timerMinutes}분 · ${recipe.steps.length}단계 · $servings인분';

    return GestureDetector(
      onTap: onTap,
      // 히어로는 화면 끝까지 간다. 모서리를 둥글리거나 그림자를 주면
      // 가장자리에 카드 테두리가 생겨 꽉 찬 느낌이 깨진다.
      child: ClipRect(
        child: AspectRatio(
          aspectRatio: 3 / 2,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 사진이 없으면 아이콘 자리표시자 대신 붉은 그라데이션을 깐다.
              // 히어로에 빈 아이콘이 뜨면 로딩 실패처럼 보인다.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE8442B), Color(0xFF8E1F14)],
                  ),
                ),
              ),
              if (recipe.imageUrl.isNotEmpty)
                FoodImage(image: recipe.imageUrl, radius: 0),
              // 하단 텍스트 가독성을 위한 어둠. 위쪽 62%는 건드리지 않는다.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    stops: [0, 0.62],
                    colors: [Color(0x8C000000), Colors.transparent],
                  ),
                ),
              ),
              Positioned(
                left: space.cardPadding,
                right: space.cardPadding,
                bottom: space.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '오늘의 추천',
                      style: type.tiny.copyWith(
                        color: Colors.white70,
                        fontWeight: type.bold,
                        letterSpacing: 1.4,
                      ),
                    ),
                    SizedBox(height: space.snugGap),
                    Text(
                      recipe.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.headlineLarge.copyWith(
                        color: Colors.white,
                        fontWeight: type.black,
                      ),
                    ),
                    SizedBox(height: space.tightGap),
                    Text(
                      meta,
                      style: type.caption.copyWith(
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: space.blockGap),
                    Row(
                      children: [
                        FilledButton.icon(
                          key: const Key('home-hero-start'),
                          onPressed: onStart ?? onTap,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: color.ink,
                            // 테마 기본값이 Size.fromHeight — 폭이 무한이다.
                            // 가로로 늘어놓는 자리라 그대로 두면 레이아웃이 터진다.
                            minimumSize: const Size(0, 44),
                            padding: EdgeInsets.symmetric(
                              horizontal: space.sectionGap,
                              vertical: space.blockGap,
                            ),
                          ),
                          icon: Icon(
                            Icons.play_arrow_rounded,
                            size: space.iconLg,
                          ),
                          label: const Text('요리 시작'),
                        ),
                        SizedBox(width: space.snugGap),
                        FilledButton.icon(
                          key: const Key('home-hero-save'),
                          onPressed: saving ? null : onSave,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white24,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.white10,
                            disabledForegroundColor: Colors.white54,
                            minimumSize: const Size(0, 44),
                            padding: EdgeInsets.symmetric(
                              horizontal: space.sectionGap,
                              vertical: space.blockGap,
                            ),
                          ),
                          icon: Icon(
                            saved ? Icons.bookmark_rounded : Icons.add_rounded,
                            size: space.iconLg,
                          ),
                          label: Text(saved ? '저장됨' : '저장'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 가로로 넘기는 포스터 카드. 넷플릭스식 홈의 기본 단위다.
///
/// 정사각형으로 잡았다. 세로로 길게 자르면 접시가 잘리고, 가로로 눕히면 한 줄에
/// 두 장밖에 못 넣는다. 요리 사진은 접시가 가운데 오는 구도가 대부분이라
/// 1:1 이 가장 덜 잘린다.
class RecipePosterCard extends StatelessWidget {
  const RecipePosterCard({
    super.key,
    required this.title,
    required this.image,
    this.meta,
    this.badge,
    this.progress,
    this.width = 116,
    this.thumbRatio = defaultThumbRatio,
    required this.onTap,
  });

  /// 카드 사진 비율. 정사각형이다.
  static const defaultThumbRatio = 1.0;

  /// 이어하기 열처럼 가로로 넓은 변형에서 바꿔 준다.
  final double thumbRatio;

  final String title;
  final String image;
  final String? meta;
  final String? badge;

  /// 0~1. 이어서 요리하기 카드에만 쓴다.
  final double? progress;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return PressableScale(
      child: InkWell(
        borderRadius: BorderRadius.circular(space.radiusMd),
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 높이를 폭에서 계산하지 않는다. 그리드 셀에서는 폭이 무한으로 들어와
              // (부모가 정해 줌) 곱셈이 무한 높이를 만든다.
              AspectRatio(
                aspectRatio: thumbRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FoodImage(
                      image: image,
                      width: width.isFinite ? width : null,
                      radius: space.radiusMd,
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(space.radiusMd),
                          gradient: const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0x99000000), Color(0x00000000)],
                            stops: [0, 0.55],
                          ),
                        ),
                      ),
                    ),
                    if (badge != null)
                      Positioned(
                        top: space.tightGap,
                        left: space.tightGap,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: space.tightGap,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.accent,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            badge!,
                            style: type.micro.copyWith(
                              color: color.onAccent,
                              fontWeight: type.extraBold,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: space.snugGap,
                      right: space.snugGap,
                      bottom: progress != null ? space.blockGap : space.snugGap,
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: type.small.copyWith(
                          color: Colors.white,
                          height: 1.3,
                          fontWeight: type.bold,
                        ),
                      ),
                    ),
                    if (progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(space.radiusMd),
                          ),
                          child: LinearProgressIndicator(
                            value: progress!.clamp(0, 1),
                            minHeight: 3,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation(color.accent),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (meta != null) ...[
                SizedBox(height: space.tightGap),
                Text(
                  meta!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.tiny.copyWith(color: color.muted, height: 1.35),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 제목 한 줄 + 가로 스크롤 카드 묶음.
///
/// 화면 폭 끝까지 카드가 이어져야 "옆에 더 있다"가 보이므로, 목록만 좌우 여백을
/// 갖고 바깥 패딩은 두지 않는다(호출부가 음수 마진을 쓰지 않아도 되게).
class RecipeRail extends StatelessWidget {
  const RecipeRail({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.cardWidth = 116,
    this.thumbRatio = RecipePosterCard.defaultThumbRatio,
    this.hasMeta = false,
  });

  final String title;
  final List<Widget> children;
  final String? trailing;

  /// 카드 폭. 사진 높이는 여기에 비율을 적용해 구한다.
  final double cardWidth;

  /// 카드 사진 비율. 카드에 준 값과 같아야 열 높이가 맞는다.
  final double thumbRatio;

  /// 카드 아래 한 줄짜리 설명이 붙는지. 붙는 만큼만 높이를 더한다.
  final bool hasMeta;

  /// 열 높이는 카드에서 구한다. 고정값을 쓰면 카드보다 커진 만큼
  /// 열 아래에 빈 띠가 생긴다.
  double get _cardHeight =>
      cardWidth / thumbRatio + (hasMeta ? _metaHeight : 0);
  static const _metaHeight = 6 + 11 * 1.35;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // 열 사이 여백은 좁게 둔다 — 넓으면 한 화면에 한 열밖에 안 들어와
          // 카탈로그가 작아 보인다.
          padding: EdgeInsets.only(top: space.blockGap, bottom: space.snugGap),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: type.label.copyWith(
                    fontWeight: type.extraBold,
                    color: color.ink,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: type.micro.copyWith(
                    letterSpacing: 0.5,
                    color: color.muted,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: _cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.zero,
            itemCount: children.length,
            separatorBuilder: (_, _) => SizedBox(width: space.itemGap),
            itemBuilder: (_, index) => children[index],
          ),
        ),
      ],
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return AnimatedContainer(
      duration: AppMotion.short,
      curve: AppMotion.easeInOut,
      padding: EdgeInsets.symmetric(
        horizontal: space.blockGap,
        vertical: space.snugGap,
      ),
      decoration: BoxDecoration(
        color: selected ? color.accent : color.card,
        borderRadius: BorderRadius.circular(space.radiusPill),
        border: Border.all(color: selected ? color.accent : color.line),
      ),
      child: AnimatedDefaultTextStyle(
        duration: AppMotion.short,
        curve: AppMotion.easeInOut,
        // AnimatedDefaultTextStyle은 테마의 DefaultTextStyle을 대체하므로
        // 타입 토큰(fontFamily 포함)을 통째로 넘기지 않으면 한글이 없는
        // 플랫폼 기본 폰트로 떨어진다.
        style: type.caption.copyWith(
          color: selected ? color.onAccent : color.slate,
          fontWeight: type.semiBold,
        ),
        child: Text(label),
      ),
    );
  }
}

class InfoStrip extends StatelessWidget {
  const InfoStrip({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return Container(
      padding: EdgeInsets.all(space.cardPadding),
      decoration: BoxDecoration(
        color: color.wash,
        borderRadius: BorderRadius.circular(space.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color.accent),
          SizedBox(width: space.itemGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.body.copyWith(
                    fontWeight: type.bold,
                    color: color.ink,
                  ),
                ),
                SizedBox(height: space.hairGap),
                Text(body, style: type.body.copyWith(color: color.slate)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
