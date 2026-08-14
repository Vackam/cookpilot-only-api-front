import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../design/design_tokens.dart';
import 'cook_layout.dart';
import 'cook_layout_catalog.dart';

/// 실행 중인 앱에서 조리 중 화면 배치를 바꿔 보기 위한 디버그 전용 오버레이.
///
/// 디자인 전환 손잡이(`DesignSwitcherOverlay`) 바로 아래에 붙는다. 릴리즈
/// 빌드와 배치가 하나뿐일 때는 [child]를 그대로 통과시킨다.
class CookLayoutSwitcherOverlay extends StatelessWidget {
  const CookLayoutSwitcherOverlay({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode || cookLayoutCatalog.length < 2) {
      return child;
    }
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return Stack(
      children: [
        child,
        Positioned(
          right: 0,
          // 디자인 손잡이 한 칸 아래.
          top:
              MediaQuery.paddingOf(context).top +
              space.sectionBreak +
              space.tapTarget,
          child: ValueListenableBuilder<CookLayout>(
            valueListenable: activeCookLayout,
            builder: (context, current, _) {
              final index = cookLayoutCatalog.indexOf(current);
              final next =
                  cookLayoutCatalog[(index + 1) % cookLayoutCatalog.length];
              return Material(
                color: color.accent,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(space.radiusMd),
                ),
                child: InkWell(
                  onTap: () => activeCookLayout.value = next,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: space.itemGap,
                      vertical: space.tightGap,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.dashboard_customize_outlined,
                          size: space.iconMd,
                          color: color.onAccent,
                        ),
                        SizedBox(width: space.tightGap),
                        Text(
                          current.label,
                          style: type.tiny.copyWith(color: color.onAccent),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
