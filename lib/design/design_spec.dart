import 'package:flutter/widgets.dart';

/// 디자인 안(案) 하나를 이루는 토큰 묶음.
///
/// 화면 코드는 여기 정의된 토큰만 참조하고 실제 값은 절대 알지 못한다.
/// 새 디자인을 시험하려면 `design_catalog.dart`에 [DesignSpec]을 하나 더
/// 만들어 넣기만 하면 된다. 화면은 손대지 않는다.
@immutable
class DesignSpec {
  const DesignSpec({
    required this.id,
    required this.label,
    required this.palette,
    required this.type,
    required this.density,
  });

  /// 저장·비교용 식별자.
  final String id;

  /// 디자인 전환 UI에 노출할 이름.
  final String label;

  final DesignPalette palette;
  final DesignTypography type;
  final DesignDensity density;
}

/// 색 토큰. 역할 이름만 쓰고 색상명(brown, cream 등)은 쓰지 않는다.
/// 어두운 디자인으로 갈아끼워도 이름이 거짓말이 되지 않게 하기 위함.
@immutable
class DesignPalette {
  const DesignPalette({
    required this.brightness,
    required this.ink,
    required this.slate,
    required this.muted,
    required this.surface,
    required this.card,
    required this.line,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.wash,
    required this.success,
    required this.shadow,
    required this.inverseSurface,
    required this.onInverse,
    required this.onInverseMuted,
    required this.inverseLine,
    required this.scrimStrong,
    required this.scrimSoft,
    required this.overlaySurface,
    required this.placeholderFrom,
    required this.placeholderTo,
    required this.placeholderIcon,
  });

  /// 상태바 아이콘 색과 Material ColorScheme 생성에 쓰인다.
  final Brightness brightness;

  /// 본문·제목 텍스트.
  final Color ink;

  /// 보조 텍스트.
  final Color slate;

  /// 힌트·비활성 텍스트.
  final Color muted;

  /// 앱 배경.
  final Color surface;

  /// 카드 표면.
  final Color card;

  /// 헤어라인·테두리.
  final Color line;

  /// 브랜드 포인트.
  final Color accent;

  /// 포인트의 연한 배경 버전(선택 상태, 강조 스트립).
  final Color accentSoft;

  /// [accent] 위에 올라가는 전경색.
  final Color onAccent;

  /// 정보 스트립 등 은은한 배경.
  final Color wash;

  /// 완료·성공.
  final Color success;

  /// 그림자. 배경과 어우러지도록 틴트를 섞는다.
  final Color shadow;

  /// 배경을 뒤집은 강조 카드(조리 타이머 등)의 표면.
  final Color inverseSurface;

  /// [inverseSurface] 위 본문 전경색.
  final Color onInverse;

  /// [inverseSurface] 위 보조 전경색.
  final Color onInverseMuted;

  /// [inverseSurface] 위 테두리.
  final Color inverseLine;

  /// 사진 위 그라데이션의 짙은 쪽.
  final Color scrimStrong;

  /// 사진 위 그라데이션의 옅은 쪽.
  final Color scrimSoft;

  /// 사진 위에 떠 있는 반투명 버튼 표면.
  final Color overlaySurface;

  /// 이미지 자리표시자 그라데이션 시작.
  final Color placeholderFrom;

  /// 이미지 자리표시자 그라데이션 끝.
  final Color placeholderTo;

  /// 이미지 자리표시자 아이콘.
  final Color placeholderIcon;
}

/// 외부 브랜드 규정에 묶여 디자인 안과 무관하게 고정되는 색.
abstract final class BrandColors {
  /// 카카오 로그인 버튼 배경. 카카오 브랜드 가이드상 변경 불가.
  static const kakao = Color(0xFFFEE500);

  /// 카카오 버튼 전경. 위와 같은 이유로 고정.
  static const kakaoInk = Color(0xFF191600);
}

/// 타이포 토큰. 크기 단계와 굵기 단계를 함께 소유한다.
///
/// 각 단계는 색을 담지 않는다. 색은 [DesignPalette]의 몫이고, 필요한 곳에서
/// `.copyWith(color: ...)`로 얹는다.
@immutable
class DesignTypography {
  const DesignTypography({
    required this.fontFamily,
    required this.tightTracking,
    required this.bodyHeight,
    required this.displayHeight,
    required this.regular,
    required this.medium,
    required this.semiBold,
    required this.bold,
    required this.extraBold,
    required this.black,
    required this.microSize,
    required this.tinySize,
    required this.smallSize,
    required this.captionSize,
    required this.bodySize,
    required this.labelSize,
    required this.bodyLargeSize,
    required this.leadSize,
    required this.titleSize,
    required this.titleLargeSize,
    required this.heroTitleSize,
    required this.headlineSize,
    required this.headlineLargeSize,
    required this.numericSize,
  });

  final String fontFamily;

  /// 큰 글자에 적용하는 음수 자간.
  final double tightTracking;

  final double bodyHeight;
  final double displayHeight;

  final FontWeight regular;
  final FontWeight medium;
  final FontWeight semiBold;
  final FontWeight bold;

  /// 제목 기본 굵기.
  final FontWeight extraBold;

  /// 제목 중에서도 한 단계 더 눌러 쓰는 자리.
  final FontWeight black;

  /// 달력 표식 등 최소 표기.
  final double microSize;

  /// 배지·꼬리표.
  final double tinySize;

  /// 보조 메타 정보.
  final double smallSize;

  /// 목록의 보조 설명. 이 앱에서 가장 많이 쓰이는 크기.
  final double captionSize;

  /// 기본 본문.
  final double bodySize;

  /// 버튼·라벨.
  final double labelSize;

  /// 강조 본문.
  final double bodyLargeSize;

  /// 도입 문장.
  final double leadSize;

  /// 소제목.
  final double titleSize;

  /// 섹션 제목.
  final double titleLargeSize;

  /// 대표 카드의 제목.
  final double heroTitleSize;

  /// 화면 제목.
  final double headlineSize;

  /// 큰 화면 제목.
  final double headlineLargeSize;

  /// 타이머처럼 숫자만 크게 보여주는 자리.
  final double numericSize;

  TextStyle _at(double size, FontWeight weight, {double? tracking}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: tracking,
        height: size >= titleLargeSize ? displayHeight : bodyHeight,
      );

  TextStyle get micro => _at(microSize, medium);
  TextStyle get tiny => _at(tinySize, semiBold);
  TextStyle get small => _at(smallSize, medium);
  TextStyle get caption => _at(captionSize, medium);
  TextStyle get body => _at(bodySize, regular);
  TextStyle get label =>
      _at(labelSize, semiBold, tracking: tightTracking * 0.2);
  TextStyle get bodyLarge => _at(bodyLargeSize, regular);
  TextStyle get subtitle =>
      _at(bodyLargeSize, bold, tracking: tightTracking * 0.33);
  TextStyle get lead => _at(leadSize, bold, tracking: tightTracking * 0.3);
  TextStyle get title => _at(titleSize, bold, tracking: tightTracking * 0.7);
  TextStyle get titleLarge =>
      _at(titleLargeSize, extraBold, tracking: tightTracking);
  TextStyle get heroTitle =>
      _at(heroTitleSize, black, tracking: tightTracking * 1.2);
  TextStyle get headline =>
      _at(headlineSize, extraBold, tracking: tightTracking);
  TextStyle get headlineLarge =>
      _at(headlineLargeSize, extraBold, tracking: tightTracking);

  /// 자릿수가 바뀌어도 폭이 흔들리지 않도록 tabular figures를 강제한다.
  TextStyle get numeric => _at(
    numericSize,
    extraBold,
    tracking: tightTracking * 1.7,
  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}

/// 여백·모서리·컨트롤 크기 토큰.
///
/// 값이 아니라 역할로 이름을 붙였기 때문에, 촘촘한 디자인은 [sectionGap]과
/// [cardPadding]만 줄이면 전 화면이 함께 촘촘해진다.
@immutable
class DesignDensity {
  const DesignDensity({
    required this.hairGap,
    required this.tightGap,
    required this.snugGap,
    required this.itemGap,
    required this.blockGap,
    required this.sectionGap,
    required this.majorGap,
    required this.sectionBreak,
    required this.screenPaddingX,
    required this.screenPaddingTop,
    required this.screenPaddingBottom,
    required this.cardPadding,
    required this.chipPaddingX,
    required this.chipPaddingY,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusXl,
    required this.radiusPill,
    required this.controlHeight,
    required this.compactControlHeight,
    required this.tapTarget,
    required this.contentMaxWidth,
    required this.iconSm,
    required this.iconMd,
    required this.iconLg,
    required this.iconXl,
    required this.iconHero,
    required this.thumbSize,
    required this.brandMarkSize,
    required this.avatarSize,
    required this.avatarLargeSize,
    required this.shadowBlur,
    required this.shadowLift,
    required this.softShadowBlur,
    required this.softShadowLift,
    required this.overlayButtonSize,
    required this.cookControlSize,
    required this.heroImageHeight,
    required this.stepImageHeight,
    required this.photoTileSize,
  });

  /// 라벨과 값처럼 붙어 있어야 하는 두 줄 사이.
  final double hairGap;

  /// 한 덩어리 안에서 요소를 떼어 놓는 최소 간격.
  final double tightGap;

  /// 아이콘과 글자처럼 한 줄 안에서 붙는 요소 사이. 이 앱에서 가장 잦은 간격.
  final double snugGap;

  /// 목록 항목 사이.
  final double itemGap;

  /// 카드 내부 블록 사이.
  final double blockGap;

  /// 섹션 사이.
  final double sectionGap;

  /// 화면을 크게 가르는 간격.
  final double majorGap;

  /// 로딩·빈 상태처럼 화면 한복판에 놓이는 것을 아래로 밀어내는 여백.
  final double sectionBreak;

  final double screenPaddingX;
  final double screenPaddingTop;
  final double screenPaddingBottom;

  /// 카드·시트 내부 여백.
  final double cardPadding;

  final double chipPaddingX;
  final double chipPaddingY;

  /// 배지·작은 표식.
  final double radiusSm;

  /// 칩·작은 버튼.
  final double radiusMd;

  /// 입력창·카드 내부 요소.
  final double radiusLg;

  /// 카드·시트 등 바깥 컨테이너.
  final double radiusXl;

  /// 완전한 알약 형태.
  final double radiusPill;

  /// 기본 버튼 높이.
  final double controlHeight;

  /// 보조 버튼 높이.
  final double compactControlHeight;

  /// 최소 터치 영역.
  final double tapTarget;

  /// 넓은 화면에서 본문이 늘어나는 한계.
  final double contentMaxWidth;

  /// 본문 글자 옆에 붙는 아이콘.
  final double iconSm;

  /// 라벨·버튼 아이콘.
  final double iconMd;

  /// 목록 항목의 대표 아이콘.
  final double iconLg;

  /// 빈 상태 안내의 큰 아이콘.
  final double iconXl;

  /// 화면 하나를 대표하는 아이콘.
  final double iconHero;

  /// 목록 썸네일 한 변.
  final double thumbSize;

  /// 로그인 화면 브랜드 마크 한 변.
  final double brandMarkSize;

  /// 카드 앞머리에 놓이는 원형 아이콘 한 변.
  final double avatarSize;

  /// 요약 카드처럼 한 단계 크게 쓰는 원형·사각 아이콘 한 변.
  final double avatarLargeSize;

  /// 떠 있는 요소의 그림자 번짐.
  final double shadowBlur;

  /// 떠 있는 요소의 그림자가 아래로 내려앉는 거리.
  final double shadowLift;

  /// 살짝만 떠 있는 요소의 그림자 번짐.
  final double softShadowBlur;

  /// 살짝만 떠 있는 요소의 그림자가 내려앉는 거리.
  final double softShadowLift;

  /// 사진 위에 얹는 원형 아이콘 버튼 한 변.
  final double overlayButtonSize;

  /// 조리 중 화면에서 조작을 하나로 모은 원형 컨트롤의 지름.
  /// 사진 위에 떠 있고 젖은 손으로 누르는 자리라 다른 버튼보다 크게 잡는다.
  final double cookControlSize;

  /// 상세 화면 상단 대표 사진 높이.
  final double heroImageHeight;

  /// 조리 단계 사진 높이.
  final double stepImageHeight;

  /// 후기 사진 목록의 정사각 타일 한 변.
  final double photoTileSize;

  EdgeInsets get screenPadding => EdgeInsets.fromLTRB(
    screenPaddingX,
    screenPaddingTop,
    screenPaddingX,
    screenPaddingBottom,
  );

  EdgeInsets get cardInsets => EdgeInsets.all(cardPadding);

  EdgeInsets get chipInsets =>
      EdgeInsets.symmetric(horizontal: chipPaddingX, vertical: chipPaddingY);
}
