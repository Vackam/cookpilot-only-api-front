import 'package:flutter/foundation.dart';

/// 셸의 현재 탭.
///
/// 상태를 셸 밖에 두는 이유: 깊이 들어간 화면(레시피 상세 → 조리 설정)에서 홈 로고를
/// 누르면 **루트로 돌아간 뒤 홈 탭까지** 가야 하는데, 그 시점에는 누른 위젯이 이미
/// 사라져 셸의 State 를 찾을 수 없다.
final shellTabIndex = ValueNotifier<int>(0);

const shellHomeTab = 0;
const shellSearchTab = 1;
