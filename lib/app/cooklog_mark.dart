import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

// 로고는 테마를 타지 않는 브랜드 색으로 고정한다. 디자인 스위처로 팔레트를
// 바꿔도 로고 색이 흔들리면 브랜드가 아니라 아이콘으로 보인다.
const _brandInk = Color(0xFF17130F);
const _brandAccent = Color(0xFFF04E23);
const _brandMuted = Color(0xFF8D867F);

/// cooklog 심볼 — 냄비와 김.
///
/// 이미지가 아니라 직접 그린다. 김 세 줄을 따로 움직여야 로딩 표시로 쓸 수 있고
/// (`CookLogLoader`), 어떤 크기에서도 깨지지 않는다.
///
/// 좌표는 원본 SVG 의 64×64 뷰박스를 그대로 쓰고 캔버스에서 배율만 맞춘다.
class CookLogMark extends StatelessWidget {
  const CookLogMark({super.key, this.size = 28, this.steam});

  final double size;

  /// 김이 오르는 위상(0~1). 로딩에서만 굴린다.
  /// null 이면 원본 로고 그대로 — 세 줄이 정지해 있다.
  final double? steam;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CookLogPainter(phase: steam)),
    );
  }
}

class _CookLogPainter extends CustomPainter {
  const _CookLogPainter({this.phase});

  /// null 이면 정지, 값이 있으면 그 위상으로 김이 오른다.
  final double? phase;

  /// 김 세 줄. (시작x, 끝x, y, 기본 투명도). 0 번이 맨 위(가장 오래된 김)다.
  static const _steamLines = [
    (27.5, 44.0, 11.0, 1.0),
    (19.0, 40.0, 20.0, 0.72),
    (23.0, 36.0, 29.0, 0.45),
  ];

  /// 아래 줄부터 차례로 밝아진다 — 그래야 올라가는 것처럼 보인다.
  /// 완전히 꺼지지는 않는다(하한 0.3). 한 번이라도 비면 냄비만 남아 로고가
  /// 아닌 다른 것으로 보인다.
  double _brightness(int index) {
    final t = phase;
    if (t == null) return 1;

    final center = (_steamLines.length - 1 - index) / _steamLines.length;
    var distance = (t - center).abs();
    distance = math.min(distance, 1 - distance);
    final pulse = (1 - distance / 0.4).clamp(0.0, 1.0);
    return 0.3 + 0.7 * pulse;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);

    for (var i = 0; i < _steamLines.length; i++) {
      final (startX, endX, y, baseOpacity) = _steamLines[i];
      final brightness = _brightness(i);

      final paint = Paint()
        ..color = _brandAccent.withValues(alpha: baseOpacity * brightness)
        ..strokeWidth = 5.2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      // 밝아질수록 살짝 떠오른다.
      final lift = (1 - brightness) * 1.6;
      canvas.drawLine(Offset(startX, y + lift), Offset(endX, y + lift), paint);

      if (i == 0) {
        canvas.drawCircle(
          Offset(21.5, y + lift),
          2.6,
          Paint()..color = _brandAccent.withValues(alpha: brightness),
        );
      }
    }

    final pot = Paint()..color = _brandInk;
    canvas.drawPath(_potPath(), pot);
    canvas.drawRRect(
      RRect.fromLTRBR(4, 43, 11, 48.4, const Radius.circular(2.7)),
      pot,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(53, 43, 60, 48.4, const Radius.circular(2.7)),
      pot,
    );
    canvas.restore();
  }

  Path _potPath() {
    return Path()
      ..moveTo(13, 40)
      ..lineTo(51, 40)
      ..arcToPoint(const Offset(53.5, 42.5), radius: const Radius.circular(2.5))
      ..lineTo(53.5, 44.5)
      ..arcToPoint(const Offset(40.5, 57.5), radius: const Radius.circular(13))
      ..lineTo(23.5, 57.5)
      ..arcToPoint(const Offset(10.5, 44.5), radius: const Radius.circular(13))
      ..lineTo(10.5, 42.5)
      ..arcToPoint(const Offset(13, 40), radius: const Radius.circular(2.5))
      ..close();
  }

  @override
  bool shouldRepaint(_CookLogPainter oldDelegate) => oldDelegate.phase != phase;
}

/// 김이 계속 오르는 심볼. 티커를 여기 한 곳에서만 돌린다.
///
/// 모션을 끈 사용자에게는 티커를 아예 시작하지 않는다 — 보이지도 않는
/// 애니메이션에 프레임을 쓰지 않는다.
class SteamingCookLogMark extends StatefulWidget {
  const SteamingCookLogMark({super.key, this.size = 28});

  final double size;

  @override
  State<SteamingCookLogMark> createState() => _SteamingCookLogMarkState();
}

class _SteamingCookLogMarkState extends State<SteamingCookLogMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  bool _motionOff = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 설정을 읽을 수 있는 가장 이른 시점이 여기다.
    final motionOff = MediaQuery.disableAnimationsOf(context);
    if (motionOff == _motionOff && (motionOff || _controller.isAnimating)) {
      return;
    }
    _motionOff = motionOff;
    if (motionOff) {
      _controller.stop();
    } else {
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 모션을 끈 사용자에게는 원본 로고 그대로.
    if (_motionOff) return CookLogMark(size: widget.size);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) =>
          CookLogMark(size: widget.size, steam: _controller.value),
    );
  }
}

/// 로딩 표시. 냄비에서 김이 하나씩 올라온다.
///
/// 빙글빙글 도는 원 대신 이걸 쓰는 이유: 기다리는 동안에도 브랜드가 보이고,
/// "끓고 있다"가 이 앱에서 기다림의 은유로 맞는다.
class CookLogLoader extends StatelessWidget {
  const CookLogLoader({super.key, this.size = 44, this.label});

  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final mark = SteamingCookLogMark(size: size);
    if (label == null) return Center(child: mark);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          const SizedBox(height: 10),
          Text(
            label!,
            style: const TextStyle(color: _brandMuted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
