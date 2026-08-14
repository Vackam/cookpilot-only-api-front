import 'package:flutter/foundation.dart';

import 'cook_layout.dart';
import 'layout_classic.dart';
import 'layout_one_control.dart';

/// 시험 중인 조리 중 화면 배치 목록. 디버그 빌드의 배치 전환 UI가 이 목록을 그린다.
const cookLayoutCatalog = <CookLayout>[
  ClassicCookLayout(),
  OneControlCookLayout(),
];

/// 앱이 켜질 때 쓰는 배치.
///
/// 기본 배치를 다른 안으로 바꾸면 위젯 테스트가 기대하는 문구·버튼이 달라진다
/// (예: `다음 단계` FilledButton, `직접 입력` 라벨). 승자가 정해지기 전까지는
/// 기준선을 기본값으로 두고, 새 배치는 전환 UI로만 띄운다.
const defaultCookLayout = ClassicCookLayout();

/// 디버그 빌드에서 배치를 바꿔 보기 위한 선택 상태.
///
/// 전역인 이유: 배치 전환 손잡이는 `MaterialApp.builder` 안(라우트 바깥)에 있고
/// 조리 화면은 라우트 안에 있어서, InheritedWidget으로 잇자면 앱 루트부터
/// 화면까지 배선이 필요하다. 릴리즈 빌드에서는 아무도 이 값을 바꾸지 않는다.
final activeCookLayout = ValueNotifier<CookLayout>(defaultCookLayout);
