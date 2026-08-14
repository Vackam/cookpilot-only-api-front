import 'package:flutter/material.dart';

import 'design_catalog.dart';
import 'design_spec.dart';

/// 활성 [DesignSpec]을 위젯 트리에 실어 나르는 테마 확장.
///
/// Flutter의 [ColorScheme]/[TextTheme]은 이 앱이 쓰는 역할(wash, accentSoft,
/// inverseSurface 등)을 담기에 칸이 모자라서 확장을 따로 둔다.
@immutable
class CookPilotTokens extends ThemeExtension<CookPilotTokens> {
  const CookPilotTokens(this.spec);

  final DesignSpec spec;

  DesignPalette get color => spec.palette;

  // 이름이 `type`이 아닌 이유: ThemeExtension이 이미 `type` 게터를 갖고 있다.
  DesignTypography get typography => spec.type;
  DesignDensity get space => spec.density;

  @override
  CookPilotTokens copyWith({DesignSpec? spec}) =>
      CookPilotTokens(spec ?? this.spec);

  /// 디자인 안은 통째로 갈아끼우는 단위라 중간값을 섞지 않는다.
  /// 전환 애니메이션 도중에는 목적지 스펙을 그대로 쓴다.
  @override
  CookPilotTokens lerp(ThemeExtension<CookPilotTokens>? other, double t) {
    if (other is! CookPilotTokens) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}

extension DesignTokensContext on BuildContext {
  /// 활성 디자인 토큰.
  ///
  /// 테마를 붙이지 않고 위젯만 띄우는 테스트에서도 화면이 의도한 디자인으로
  /// 그려지도록, 확장이 없으면 기본 스펙으로 떨어진다.
  CookPilotTokens get tokens =>
      Theme.of(this).extension<CookPilotTokens>() ??
      const CookPilotTokens(defaultDesignSpec);

  DesignPalette get color => tokens.color;
  DesignTypography get type => tokens.typography;
  DesignDensity get space => tokens.space;
}
