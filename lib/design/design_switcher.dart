import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'design_catalog.dart';
import 'design_spec.dart';

/// 실행 중인 앱에서 디자인 안을 바꿔 보기 위한 디버그 전용 오버레이.
///
/// `MaterialApp.builder`에 물리기 때문에 모든 화면 위에 뜬다. 덕분에 디자인을
/// 비교하려고 화면 코드를 건드릴 필요가 없다. 릴리즈 빌드에서는 [child]를
/// 그대로 통과시킨다.
class DesignSwitcherOverlay extends StatelessWidget {
  const DesignSwitcherOverlay({
    required this.current,
    required this.onChanged,
    required this.child,
    super.key,
  });

  final DesignSpec current;
  final ValueChanged<DesignSpec> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode || designCatalog.length < 2) {
      return child;
    }
    final index = designCatalog.indexOf(current);
    final next = designCatalog[(index + 1) % designCatalog.length];
    return Stack(
      children: [
        child,
        Positioned(
          right: 0,
          top: MediaQuery.paddingOf(context).top + current.density.sectionBreak,
          child: _SwitcherHandle(
            current: current,
            onTap: () => onChanged(next),
          ),
        ),
      ],
    );
  }
}

/// 누를 때마다 카탈로그의 다음 안으로 넘어가는 손잡이.
///
/// 메뉴가 아니라 순환 버튼인 이유: `MaterialApp.builder`의 자식은 Navigator
/// 바깥이라 팝업 메뉴가 기댈 Overlay가 없다.
class _SwitcherHandle extends StatelessWidget {
  const _SwitcherHandle({required this.current, required this.onTap});

  final DesignSpec current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = current.palette;
    final space = current.density;
    return Material(
      color: color.inverseSurface,
      borderRadius: BorderRadius.horizontal(
        left: Radius.circular(space.radiusMd),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: space.itemGap,
            vertical: space.tightGap,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.palette_outlined,
                size: space.iconMd,
                color: color.onInverse,
              ),
              SizedBox(width: space.tightGap),
              Text(
                current.label,
                style: current.type.tiny.copyWith(color: color.onInverse),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
