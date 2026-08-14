import 'package:flutter/material.dart';

import '../design/design_catalog.dart';
import '../design/design_spec.dart';
import '../design/design_tokens.dart';

/// Shared easing curves and durations, tuned per the "ease-out for entering,
/// ease-in-out for on-screen movement" rule of thumb. Keep every ad-hoc
/// animation in the app pulling from here so motion feels like one system.
class AppMotion {
  const AppMotion._();

  /// Entering / exiting elements. Starts fast, feels responsive.
  static const easeOut = Cubic(0.23, 1, 0.32, 1);

  /// Elements moving or morphing on screen (progress bars, step swaps).
  static const easeInOut = Cubic(0.77, 0, 0.175, 1);

  static const fast = Duration(milliseconds: 120);
  static const short = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 260);
  static const long = Duration(milliseconds: 400);
}

class _CookPilotPageTransitionsBuilder extends PageTransitionsBuilder {
  const _CookPilotPageTransitionsBuilder();

  // 시각 효과뿐 아니라 라우트 애니메이션 자체를 0ms로 만들어, 전환 중
  // 이전 화면이 오버레이에 남아 티커를 돌리는 구간을 없앤다.
  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 화면 전환 애니메이션 없이 즉시 전환한다. 저사양 기기에서 전환·진입
    // 애니메이션이 겹치며 씹히는 문제로 장식용 모션은 전부 걷어냈다.
    return child;
  }
}

TextTheme _buildTextTheme(DesignSpec spec) {
  final t = spec.type;
  return TextTheme(
    headlineLarge: t.headlineLarge,
    headlineMedium: t.headline,
    headlineSmall: t.titleLarge,
    titleLarge: t.title,
    titleMedium: t.subtitle,
    titleSmall: t.label,
    bodyLarge: t.bodyLarge,
    bodyMedium: t.body,
    bodySmall: t.caption,
    labelLarge: t.label,
    labelMedium: t.small,
    labelSmall: t.tiny,
  ).apply(bodyColor: spec.palette.ink, displayColor: spec.palette.ink);
}

/// [spec]이 정한 토큰만으로 앱 테마를 조립한다.
///
/// 여기에는 색·크기 리터럴이 하나도 없어야 한다. 새 값이 필요하면 테마가
/// 아니라 [DesignSpec]에 토큰을 추가할 것.
ThemeData buildCookPilotTheme([DesignSpec spec = defaultDesignSpec]) {
  final c = spec.palette;
  final t = spec.type;
  final d = spec.density;

  final colorScheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: c.brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.ink,
    surface: c.card,
    onSurface: c.ink,
  );

  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: c.surface,
    useMaterial3: true,
    fontFamily: t.fontFamily,
    extensions: [CookPilotTokens(spec)],
    textTheme: _buildTextTheme(spec),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _CookPilotPageTransitionsBuilder(),
        TargetPlatform.iOS: _CookPilotPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: c.surface,
      foregroundColor: c.ink,
      elevation: 0,
      titleTextStyle: t.lead.copyWith(color: c.ink),
    ),
    cardTheme: CardThemeData(
      color: c.card,
      elevation: 3,
      shadowColor: c.shadow,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.symmetric(vertical: d.hairGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(d.radiusXl),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: Size.fromHeight(d.controlHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(d.radiusLg),
        ),
        textStyle: t.subtitle,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: Size.fromHeight(d.controlHeight),
        side: BorderSide(color: c.line, width: 1.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(d.radiusLg),
        ),
        textStyle: t.bodyLarge.copyWith(
          fontWeight: t.semiBold,
          letterSpacing: t.tightTracking * 0.33,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.slate, textStyle: t.label),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.card,
      hintStyle: TextStyle(color: c.muted),
      labelStyle: TextStyle(color: c.slate),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(d.radiusLg),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(d.radiusLg),
        borderSide: BorderSide(color: c.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(d.radiusLg),
        borderSide: BorderSide(color: c.accent, width: 1.6),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.card,
      indicatorColor: c.accentSoft,
      surfaceTintColor: Colors.transparent,
      shadowColor: c.shadow,
      elevation: 3,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? c.accent : c.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => t.small.copyWith(
          fontWeight: states.contains(WidgetState.selected) ? t.bold : t.medium,
          color: states.contains(WidgetState.selected) ? c.ink : c.muted,
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.wash,
    ),
    dividerTheme: DividerThemeData(color: c.line),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? c.accent
            : Colors.transparent,
      ),
      side: BorderSide(color: c.muted, width: 1.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(d.radiusSm),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(d.radiusXl + d.tightGap),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: c.ink),
    ),
  );
}
