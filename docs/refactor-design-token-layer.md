# refactor/design-token-layer

## 문제 상황

디자인이 화면 코드에 절반쯤 박혀 있어, 다른 디자인을 시험해 보려면 화면을 뜯어야 했다.

- `lib/app/app_theme.dart`가 색·타이포·버튼·카드 스타일을 갖고 있어서 절반은 이미 격리돼 있었다.
- 나머지 절반은 `lib/features/mvp/` 4개 파일(6,961줄)에 그대로 박혀 있었다.
  - `AppColors.xxx` 직접 참조 119곳 (테마를 거치지 않음)
  - 인라인 `TextStyle(` 64곳, 리터럴 `fontSize` 37곳
  - 하드코딩 `EdgeInsets` 41곳, `SizedBox` 간격 116곳
  - 생 `Color(0xFF...)` 10곳
- `lib/design/cookpilot_spacing.dart`는 37개 파일 중 한 곳(`help_question_sheet.dart`)만 쓰는 사실상 죽은 코드였다.

값이 이렇게 흩어져 있으면 "따뜻한 톤 말고 다른 걸 보고 싶다"가 6,961줄을 훑는 작업이 된다.

## 검토한 대안

| 안 | 얻는 것 | 비용 |
|---|---|---|
| A. 테마 스왑 가능하게 (채택) | 색·타이포·밀도 변주를 화면 수정 없이 비교 | 반나절 |
| B. 화면별 헤드리스 컨트롤러 | A + 레이아웃이 다른 화면을 같은 로직에 붙일 수 있음 | 화면당 1~2일, 위젯 테스트 수정 필요 |
| C. 컴포넌트 팩 인터페이스 | 타일·카드 렌더링 교체 | AGENTS.md의 "단일 용도 추상화 금지"에 걸리고, 정작 바꾸고 싶은 레이아웃은 못 바꿈 |

A를 골랐다. **A만으로는 레이아웃·구성 변주는 안 된다.** 레이아웃은 여전히 상태 로직과 같은
`StatefulWidget` 안에 살아 있어서, 대안 레이아웃을 붙이려면 B가 필요하다. A를 먼저 끝내고
레이아웃은 그 위에서 다시 판단하기로 했다.

## 최종 결정

### 구조

```
lib/design/
  design_spec.dart      # DesignSpec = DesignPalette + DesignTypography + DesignDensity
  design_catalog.dart   # 시험 중인 안 4종. 여기에 추가하면 스위처에 자동 노출
  design_tokens.dart    # CookPilotTokens(ThemeExtension) + BuildContext 확장
  design_switcher.dart  # 디버그 전용 런타임 전환 오버레이
lib/app/app_theme.dart  # buildCookPilotTheme(spec) -> ThemeData. 리터럴 0개
```

화면은 `context.color` / `context.type` / `context.space` 세 게터로만 디자인 값을 읽는다.
`AppColors`와 `AppShape`는 삭제했고, `cookpilot_spacing.dart`도 함께 지웠다.

### 토큰 이름은 역할로 붙인다

`brown`/`cream` 같은 색상명이 아니라 `ink`/`surface`/`accentSoft`처럼 역할로 이름 붙였다.
어두운 안으로 갈아끼워도 이름이 거짓말이 되지 않아야 하기 때문이다. 여백도 `gap12`가 아니라
`itemGap`/`sectionGap`/`cardPadding`이다. 촘촘한 안은 `sectionGap`만 줄이면 전 화면이 함께
촘촘해진다.

### `DesignTypography`는 색을 담지 않는다

크기·굵기·자간·행간만 갖는다. 색은 팔레트의 몫이고, 필요한 곳에서 `.copyWith(color:)`로 얹는다.
이렇게 해야 같은 타입 스케일을 밝은 안과 어두운 안이 함께 쓸 수 있다.

### 브랜드 색은 팔레트 밖에 둔다

카카오 로그인 버튼 색(`BrandColors.kakao`, `kakaoInk`)은 카카오 브랜드 가이드에 묶여 있어
디자인 안이 바뀌어도 고정이다. `DesignPalette`가 아니라 `BrandColors`에 뒀다.

### `CookPilotTokens.lerp`는 중간값을 만들지 않는다

디자인 안은 통째로 갈아끼우는 단위라 팔레트 절반과 밀도 절반을 섞은 상태는 의미가 없다.
전환 애니메이션 도중에는 `t < 0.5`를 기준으로 한쪽 안을 그대로 쓴다.

### 테마 없는 위젯 테스트는 기본 안으로 떨어진다

`context.tokens`는 `ThemeExtension`이 없으면 `defaultDesignSpec`으로 폴백한다.
기존 위젯 테스트 20여 개가 `MaterialApp(theme: ...)` 없이 화면을 띄우고 있어서,
`!`로 단정하면 전부 깨진다. 폴백 덕분에 테스트를 한 줄도 고치지 않았다.

### 런타임 전환 UI

`MaterialApp.builder`에 `DesignSwitcherOverlay`를 물렸다. 라우트 바깥이라 모든 화면 위에 뜬다.
디자인을 비교하려고 화면 코드를 건드릴 필요가 없다. `kDebugMode`에서만, 그리고 카탈로그에
안이 2개 이상일 때만 나타난다.

### 시험용 디자인 안 4종

| id | 축 | 내용 |
|---|---|---|
| `warm-kitchen` | 기준 | 기존 디자인. 크림 + 테라코타 |
| `midnight-prep` | 색만 | 어두운 주방. 형태·밀도는 기준과 동일 |
| `crisp-paper` | 색+타이포+형태 | 고대비, 각진 모서리, 얇은 제목, 촘촘한 여백 |
| `roomy-kitchen` | 밀도만 | 팔레트는 기준 그대로, 글자·여백만 확대 |

`midnight-prep`과 `roomy-kitchen`은 한 축만 움직인다. "색만 바꿨을 때", "글자만 키웠을 때"를
각각 단독으로 판단하기 위해서다.

## 검증

- `dart format --set-exit-if-changed` 통과
- `flutter analyze` 경고 0
- `flutter test` 398개 전부 통과 (기존 393 + 신규 5). **기존 테스트는 한 줄도 고치지 않았다.**
- `test/design/design_spec_test.dart`가 지키는 것
  - 카탈로그의 모든 안이 토큰을 실은 `ThemeData`를 만든다
  - 안의 id가 겹치지 않는다
  - 테마가 없으면 기본 안으로 떨어진다
  - **안을 바꾸면 화면이 실제로 그리는 색·글자 크기가 함께 바뀐다** — 디자인이 다시 화면에
    박히면 이 테스트가 깨진다
- 화면 파일에 `AppColors` / `fontSize:` / 생 `Color(0x` / 리터럴 `EdgeInsets` 잔여 0건 (grep 확인)

## 이후 작업에서 지킬 것

1. **화면 코드에 색·크기 리터럴을 쓰지 않는다.** 새 값이 필요하면 화면이 아니라 `DesignSpec`에
   토큰을 추가하고, 카탈로그의 모든 안에 값을 채운다. `DesignDensity`/`DesignPalette`가 전부
   `required` 필드인 것은 이걸 강제하기 위해서다.
2. **`buildCookPilotTheme`에도 리터럴을 두지 않는다.** 테마는 spec을 조립만 한다.
3. 새 안을 시험하려면 `design_catalog.dart`에 `DesignSpec`을 추가한다. 화면은 손대지 않는다.
4. 레이아웃 변주가 필요해지면 그때 B(화면별 헤드리스 컨트롤러)를 화면 하나씩 진행한다.
   한 번에 전 화면을 바꾸지 않는다.

## 남은 것 / 알려진 차이

- **레이아웃은 아직 격리되지 않았다.** 카드 vs 리스트, 히어로 vs 그리드 같은 구성 변경은
  이번 작업 범위 밖이다.
- 픽셀 단위 스냅: 흩어져 있던 값을 스케일로 모으면서 일부 자리가 1~4px 움직였다.
  아이콘 `26 → 22`, `36 → 40`, `20 → 18`, 여백 `26 → 24`, `14 → 12`, `17 → 16` 등.
  의도한 정리이고, 기준 안(`warm-kitchen`)의 인상은 그대로다.
- `AspectRatio(16/11)` 같은 비율은 토큰화하지 않고 위젯에 남겨 뒀다. 필요해지면 그때 옮긴다.
- 현재 브랜치가 `main`이라 커밋하지 않았다. AGENTS.md에 따라 `refactor/design-token-layer`
  브랜치를 만들어 PR로 올릴 것.
