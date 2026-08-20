import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../design/design_tokens.dart';
import '../recipe/domain/recipe.dart';

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

class PageShell extends StatelessWidget {
  const PageShell({
    super.key,
    required this.children,
    this.title,
    this.actions,
    this.bottom,
    this.leading,
  });

  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
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
              title: Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: actions,
            ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            space.blockGap,
            horizontalPadding,
            space.majorGap,
          ),
          children: children,
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

/// 홈 상단 '오늘의 메뉴' — 풀블리드 이미지 위에 그라데이션과 텍스트를 얹은
/// 몰입형 히어로 카드. 이 화면의 시그니처 요소.
class RecipeHeroCard extends StatelessWidget {
  const RecipeHeroCard({super.key, required this.recipe, this.onTap});

  final Recipe recipe;
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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(space.radiusXl),
            boxShadow: [
              BoxShadow(
                color: color.shadow,
                blurRadius: space.shadowBlur,
                offset: Offset(0, space.shadowLift),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(space.radiusXl),
            child: AspectRatio(
              aspectRatio: 16 / 11,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FoodImage(image: recipe.imageUrl, radius: 0),
                  // 하단 텍스트 가독성을 위한 딥브라운 그라데이션.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.45, 1],
                        colors: [Colors.transparent, color.scrimStrong],
                      ),
                    ),
                  ),
                  if (recipe.badge != null)
                    Positioned(
                      left: space.cardPadding,
                      top: space.cardPadding,
                      child: ImageLabelChip(recipe.badge!),
                    ),
                  Positioned(
                    left: space.cardPadding,
                    right: space.cardPadding,
                    bottom: space.cardPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recipe.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.heroTitle.copyWith(
                            color: color.onInverse,
                          ),
                        ),
                        SizedBox(height: space.tightGap),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              color: color.onInverseMuted,
                              size: space.iconSm,
                            ),
                            SizedBox(width: space.hairGap),
                            Text(
                              '${recipe.timerMinutes}분 타이머',
                              style: type.caption.copyWith(
                                color: color.onInverseMuted,
                              ),
                            ),
                            SizedBox(width: space.itemGap),
                            Icon(
                              Icons.people_alt_rounded,
                              color: color.onInverseMuted,
                              size: space.iconSm,
                            ),
                            SizedBox(width: space.hairGap),
                            Text(
                              '${recipe.baseServings.toStringAsFixed(recipe.baseServings % 1 == 0 ? 0 : 1)}인분',
                              style: type.caption.copyWith(
                                color: color.onInverse,
                                fontWeight: type.semiBold,
                              ),
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
        ),
      ),
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
