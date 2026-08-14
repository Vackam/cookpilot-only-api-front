import 'package:flutter/widgets.dart';

import 'cook_session_view_model.dart';

/// 조리 중 화면의 배치 한 가지.
///
/// 구현체는 배치와 장식만 책임진다. 상태·타이머·음성·저장은 전부
/// [CookSessionViewModel]이 실어 오므로 구현체가 `setState`를 부를 일이 없다.
///
/// 새 배치를 시험하려면 구현체를 하나 더 만들어 `cook_layout_catalog.dart`에
/// 넣는다. 화면 상태 클래스는 손대지 않는다.
@immutable
abstract class CookLayout {
  const CookLayout({required this.id, required this.label});

  /// 저장·비교용 식별자.
  final String id;

  /// 배치 전환 UI에 노출할 이름.
  final String label;

  Widget build(BuildContext context, CookSessionViewModel vm);
}
