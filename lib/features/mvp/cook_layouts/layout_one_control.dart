import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/design_tokens.dart';
import '../mvp_widgets.dart';
import 'cook_layout.dart';
import 'cook_session_view_model.dart';

/// C안 — 원 컨트롤. 가로 전체화면 2단.
///
/// 왼쪽은 사진, 오른쪽은 조작 패널이다. 조작을 사진 위에 얹지 않는 이유가 둘 있다.
///
/// 1. **사진을 억지로 키우지 않는다.** 비율도 원본 해상도도 그대로 두고, 남는 자리는
///    배경으로 둔다. 잘라서 채우면 조리에 필요한 부분이 밖으로 나가고, 늘려서 채우면
///    없는 픽셀을 만들어 내느라 뭉개진다.
/// 2. **글자가 사진 밝기에 좌우되지 않는다.** 패널은 진짜 표면(`card`) 위라 `ink`/`slate`를
///    그대로 쓸 수 있다. 스크림 위에 글자를 얹던 이전 안은 사진이 밝으면 읽히지 않았다.
///
/// 조작은 여전히 가운데 원 하나다. 안쪽은 AI 코치, 둘레 링은 남은 시간.
/// 탭하면 코치를 켜고 끄고, 길게 누르면 타이머.
class OneControlCookLayout extends CookLayout {
  const OneControlCookLayout() : super(id: 'one-control', label: '원 컨트롤');

  @override
  Widget build(BuildContext context, CookSessionViewModel vm) =>
      _OneControlScreen(vm: vm);
}

/// 이 배치가 살아 있는 동안만 가로·전체화면으로 잠근다.
///
/// 상태를 가진 이유는 그것 하나뿐이다. 배치를 벗어나면 [dispose]가 원래대로 되돌린다.
class _OneControlScreen extends StatefulWidget {
  const _OneControlScreen({required this.vm});

  final CookSessionViewModel vm;

  @override
  State<_OneControlScreen> createState() => _OneControlScreenState();
}

class _OneControlScreenState extends State<_OneControlScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    return Scaffold(
      backgroundColor: color.surface,
      body: SafeArea(
        child: Row(
          children: [
            Expanded(flex: 3, child: _PhotoPane(vm: widget.vm)),
            Expanded(flex: 2, child: _ControlPanel(vm: widget.vm)),
          ],
        ),
      ),
    );
  }
}

/// 사진과 나가기 버튼만 있는 왼쪽 면.
class _PhotoPane extends StatelessWidget {
  const _PhotoPane({required this.vm});

  final CookSessionViewModel vm;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final color = context.color;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        fit: StackFit.expand,
        children: [
          // 사진마다 비율과 해상도가 달라서, 앞의 사진만 놓으면 단계를 넘길 때마다
          // 칸이 들쭉날쭉해진다. 같은 사진을 흐리게 늘려 뒤를 채우면 칸은 늘 꽉
          // 차 보이면서, 앞의 사진은 원본 크기를 그대로 지킬 수 있다.
          if (vm.stepImageUrl.isNotEmpty) ...[
            ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: space.shadowBlur,
                sigmaY: space.shadowBlur,
                tileMode: TileMode.decal,
              ),
              child: FoodImage(image: vm.stepImageUrl, radius: 0),
            ),
            // 배경을 눌러야 앞의 사진 경계가 드러난다.
            ColoredBox(color: color.scrimSoft),
          ],
          Center(
            // 비율도 지키고 원본 해상도도 넘지 않는다. 잘라내면 조리에 필요한
            // 부분이 밖으로 나가고, 늘리면 없는 픽셀을 만들어 내느라 뭉개진다.
            child: GestureDetector(
              onTap: () => _openPhotoViewer(context, vm.stepImageUrl),
              child: FoodImage(
                key: const Key('cook-step-photo'),
                image: vm.stepImageUrl,
                radius: 0,
                neverUpscale: true,
              ),
            ),
          ),
          Positioned(
            left: space.blockGap,
            top: space.blockGap,
            child: _OverlayCircleButton(
              icon: Icons.close_rounded,
              size: space.tapTarget,
              onTap: vm.finishing ? null : vm.onClose,
              semanticLabel: '조리 나가기',
            ),
          ),
          Positioned(
            right: space.blockGap,
            bottom: space.blockGap,
            child: _OverlayCircleButton(
              buttonKey: const Key('photo-zoom'),
              icon: Icons.zoom_out_map_rounded,
              size: space.tapTarget,
              // 사진을 그냥 탭해도 열리지만, 그것만으로는 있는 줄 모른다.
              onTap: vm.stepImageUrl.isEmpty
                  ? null
                  : () => _openPhotoViewer(context, vm.stepImageUrl),
              semanticLabel: '사진 크게 보기',
            ),
          ),
          if (kDebugMode)
            Positioned(
              left: space.blockGap,
              bottom: space.blockGap,
              child: _PhotoSizeBadge(
                image: vm.stepImageUrl,
                slot: constraints.biggest,
              ),
            ),
        ],
      ),
    );
  }
}

void _openPhotoViewer(BuildContext context, String image) {
  if (image.isEmpty) {
    return;
  }
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => _PhotoViewerScreen(image: image),
      ),
    ),
  );
}

/// 사진만 화면 가득 띄우는 확대 화면.
///
/// 원본이 사진 칸보다 큰 단계에서는 조리 화면이 사진을 줄여 그리고 있으므로,
/// 여기서 확대하면 버려지던 디테일이 실제로 드러난다. 원본이 칸보다 작은
/// 단계에서는 크게 보일 뿐 정보가 늘지는 않는다 — 그래도 모양을 알아보는 데는
/// 도움이 되므로 늘리는 것을 막지 않는다.
class _PhotoViewerScreen extends StatelessWidget {
  const _PhotoViewerScreen({required this.image});

  final String image;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return Scaffold(
      backgroundColor: color.inverseSurface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            maxScale: 8,
            child: Center(
              child: FoodImage(image: image, radius: 0, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            left: space.blockGap,
            top: space.blockGap,
            child: _OverlayCircleButton(
              buttonKey: const Key('photo-zoom-close'),
              icon: Icons.close_rounded,
              size: space.tapTarget,
              onTap: () => Navigator.of(context).pop(),
              semanticLabel: '확대 닫기',
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: space.blockGap,
            child: Text(
              '손가락 두 개로 벌리면 더 크게 볼 수 있어요',
              textAlign: TextAlign.center,
              style: type.tiny.copyWith(color: color.onInverseMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// 원본 해상도와 사진 칸 크기를 나란히 보여 주는 디버그 표시.
///
/// 화질이 뭉개지는 원인이 "원본이 작아서"인지 "칸이 커서"인지는 두 숫자를
/// 나란히 봐야 갈린다. 원인을 확인하고 나면 지울 것.
class _PhotoSizeBadge extends StatefulWidget {
  const _PhotoSizeBadge({required this.image, required this.slot});

  final String image;

  /// 사진 칸의 논리 크기. 실제 픽셀은 화면 배율을 곱해 구한다.
  final Size slot;

  @override
  State<_PhotoSizeBadge> createState() => _PhotoSizeBadgeState();
}

class _PhotoSizeBadgeState extends State<_PhotoSizeBadge> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _source;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _PhotoSizeBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _subscribe();
    }
  }

  void _subscribe() {
    _unsubscribe();
    if (widget.image.isEmpty) {
      return;
    }
    final stream = NetworkImage(
      widget.image,
    ).resolve(createLocalImageConfiguration(context));
    // 이미 캐시된 사진은 콜백이 그 자리에서 동기 호출된다. 빌드 중 setState가
    // 되지 않도록 다음 프레임으로 미룬다.
    final listener = ImageStreamListener((info, _) {
      final size = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _source != size) {
          setState(() => _source = size);
        }
      });
    });
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _unsubscribe() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final slotW = (widget.slot.width * ratio).round();
    final slotH = (widget.slot.height * ratio).round();
    final source = _source;
    return Container(
      padding: space.chipInsets,
      decoration: BoxDecoration(
        color: color.overlaySurface,
        borderRadius: BorderRadius.circular(space.radiusSm),
      ),
      child: Text(
        source == null
            ? '원본 ? · 칸 $slotW×$slotH'
            : '원본 ${source.width.round()}×${source.height.round()} · '
                  '칸 $slotW×$slotH',
        style: type.tiny.copyWith(color: color.ink),
      ),
    );
  }
}

/// 오른쪽 조작 패널. 단계 표시 → 설명 → 안내 → 음성 상태 → 조작 원 순.
class _ControlPanel extends StatelessWidget {
  const _ControlPanel({required this.vm});

  final CookSessionViewModel vm;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.card,
        border: Border(left: BorderSide(color: color.line)),
      ),
      child: Padding(
        padding: space.cardInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  vm.stepCounterLabel,
                  style: type.tiny.copyWith(
                    color: color.accent,
                    fontWeight: type.bold,
                  ),
                ),
                const Spacer(),
                _OverlayCircleButton(
                  buttonKey: const Key('help-request'),
                  icon: Icons.keyboard_rounded,
                  size: space.overlayButtonSize,
                  onTap: vm.canAskHelp ? vm.onAskHelp : null,
                  semanticLabel: '직접 입력',
                ),
                SizedBox(width: space.tightGap),
                // 원이 코치 조작을 가져갔으므로 말하기는 여기로 내려왔다.
                _OverlayCircleButton(
                  buttonKey: const Key('voice-input-toggle'),
                  icon: vm.speechIsActive
                      ? Icons.stop_rounded
                      : Icons.mic_rounded,
                  size: space.overlayButtonSize,
                  onTap: vm.canToggleSpeech ? vm.onToggleSpeech : null,
                  semanticLabel: vm.speechButtonLabel,
                ),
              ],
            ),
            SizedBox(height: space.tightGap),
            ClipRRect(
              borderRadius: BorderRadius.circular(space.radiusPill),
              child: LinearProgressIndicator(
                value: vm.progress,
                minHeight: space.hairGap,
              ),
            ),
            SizedBox(height: space.blockGap),
            Expanded(child: _StepBody(vm: vm)),
            SizedBox(height: space.snugGap),
            _SpeechStatusRow(vm: vm),
            SizedBox(height: space.snugGap),
            _ControlRow(vm: vm),
            Text(
              vm.hasTimer ? '탭하면 코치 켜고 끄기 · 길게 누르면 타이머' : '탭하면 코치 켜고 끄기',
              textAlign: TextAlign.center,
              style: type.tiny.copyWith(color: color.muted),
            ),
            SizedBox(height: space.snugGap),
            // 가장 자주 누르는 동작이라 조작 원과 겹치지 않는 자리에 전체 폭으로 둔다.
            PressableScale(
              child: FilledButton(
                onPressed: vm.canAdvance ? vm.onAdvance : null,
                style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(space.compactControlHeight),
                ),
                child: Text(vm.advanceLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 단계 설명과 그때그때 뜨는 안내들. 길어지면 이 영역만 스크롤된다.
class _StepBody extends StatelessWidget {
  const _StepBody({required this.vm});

  final CookSessionViewModel vm;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            vm.stepTitle,
            style: type.title.copyWith(
              color: color.ink,
              fontWeight: type.black,
            ),
          ),
          SizedBox(height: space.tightGap),
          Text(
            vm.stepDescription,
            style: type.bodyLarge.copyWith(color: color.slate),
          ),
          if (vm.finishError case final String error) ...[
            SizedBox(height: space.blockGap),
            InfoStrip(
              key: const Key('cooking-completion-error'),
              icon: Icons.error_outline_rounded,
              title: '완료 정보를 저장하지 못했어요',
              body: error,
            ),
          ],
          if (vm.helpLoading) ...[
            SizedBox(height: space.blockGap),
            const InfoStrip(
              icon: Icons.hourglass_top_rounded,
              title: '답변 준비 중',
              body: '현재 단계에 맞는 답을 확인하고 있어요.',
            ),
          ] else if (vm.helpAnswer case final String answer) ...[
            SizedBox(height: space.blockGap),
            InfoStrip(
              icon: Icons.support_agent_rounded,
              title: '도움 답변',
              body: answer,
            ),
          ],
          if (vm.coachMessage case final coachMessage?) ...[
            SizedBox(height: space.snugGap),
            Text(
              coachMessage,
              key: const Key('coach-status'),
              style: type.caption.copyWith(color: color.slate),
            ),
          ],
          SizedBox(height: space.snugGap),
          Text(
            aiDataDisclosure,
            key: const Key('ai-data-disclosure'),
            style: type.small.copyWith(color: color.muted),
          ),
        ],
      ),
    );
  }
}

/// 음성 상태 한 줄. 원 안에도 마이크 아이콘이 있으므로 여기서는 문구만 짧게 알린다.
class _SpeechStatusRow extends StatelessWidget {
  const _SpeechStatusRow({required this.vm});

  final CookSessionViewModel vm;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return Row(
      key: const Key('voice-input-status'),
      children: [
        Icon(vm.speechIcon, size: space.iconSm, color: color.accent),
        SizedBox(width: space.tightGap),
        Text(
          vm.speechTitle,
          style: type.caption.copyWith(color: color.ink, fontWeight: type.bold),
        ),
        SizedBox(width: space.tightGap),
        Expanded(
          child: Text(
            vm.speechBody,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: type.caption.copyWith(color: color.slate),
          ),
        ),
      ],
    );
  }
}

/// 이전 단계 · 원 컨트롤 · 타이머 보조.
///
/// 겹치는 배치(Stack)를 쓰지 않는다. 좁은 패널에서는 겹친 버튼이 원의 탭 영역을
/// 가려서, 원을 눌러도 다른 버튼이 먹는다.
class _ControlRow extends StatelessWidget {
  const _ControlRow({required this.vm});

  final CookSessionViewModel vm;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    return SizedBox(
      height: space.cookControlSize,
      child: Row(
        children: [
          _OverlayCircleButton(
            icon: Icons.chevron_left_rounded,
            size: space.tapTarget,
            onTap: vm.canGoPrev ? vm.onPrevStep : null,
            semanticLabel: '이전 단계',
          ),
          Expanded(
            child: Center(child: _RingControl(vm: vm)),
          ),
          // 타이머가 없어도 자리를 비워 둬야 원이 왼쪽으로 밀리지 않는다.
          SizedBox(
            width: space.tapTarget,
            child: vm.hasTimer ? _TimerAuxButtons(vm: vm) : null,
          ),
        ],
      ),
    );
  }
}

/// 이 배치의 주 조작점.
///
/// 탭은 AI 코치 켜고 끄기, 길게 누르기는 타이머다. 조리 중 음성 상대는 코치라서
/// 가장 큰 조작점을 코치가 가져간다. 링은 남은 시간이라 시간이 갈수록 줄어든다.
class _RingControl extends StatelessWidget {
  const _RingControl({required this.vm});

  final CookSessionViewModel vm;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return AnimatedBuilder(
      animation: vm.timer,
      builder: (context, _) {
        final live = vm.coachActive;
        return Semantics(
          button: true,
          label: vm.coachButtonLabel,
          hint: vm.hasTimer ? vm.timerActionLabel() : null,
          child: PressableScale(
            child: GestureDetector(
              key: const Key('coach-toggle'),
              onTap: vm.canToggleCoach ? vm.onToggleCoach : null,
              onLongPress: vm.canToggleTimer ? vm.onToggleTimer : null,
              child: CustomPaint(
                painter: _TimerRingPainter(
                  // 링은 남은 비율. 타이머가 없으면 빈 트랙만 남는다.
                  remaining: vm.hasTimer ? 1 - vm.timer.progress : 0,
                  track: color.line,
                  fill: color.accent,
                  thickness: space.tightGap,
                ),
                child: SizedBox(
                  width: space.cookControlSize,
                  height: space.cookControlSize,
                  child: Padding(
                    padding: EdgeInsets.all(space.snugGap),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: live ? color.accent : color.inverseSurface,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            live
                                ? Icons.stop_rounded
                                : Icons.headset_mic_rounded,
                            size: space.iconXl,
                            color: live ? color.onAccent : color.onInverse,
                          ),
                          if (vm.hasTimer)
                            Text(
                              formatRemaining(vm.timer.remaining),
                              style: type.label.copyWith(
                                color: live ? color.onAccent : color.onInverse,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 타이머 보조 조작. 원에 겹칠 수 없어 옆으로 내렸고, 무게를 최대한 뺐다.
class _TimerAuxButtons extends StatelessWidget {
  const _TimerAuxButtons({required this.vm});

  final CookSessionViewModel vm;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return AnimatedBuilder(
      animation: vm.timer,
      builder: (context, _) {
        final style = TextButton.styleFrom(
          foregroundColor: color.slate,
          disabledForegroundColor: color.muted,
          textStyle: type.tiny,
          minimumSize: Size(space.tapTarget, space.tapTarget / 2),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: vm.canAddMinute ? vm.onAddMinute : null,
              style: style,
              child: const Text('+1분'),
            ),
            TextButton(
              onPressed: vm.canResetTimer ? vm.onResetTimer : null,
              style: style,
              child: const Text('리셋'),
            ),
          ],
        );
      },
    );
  }
}

/// 사진 위에도, 패널 위에도 놓이는 원형 아이콘 버튼.
class _OverlayCircleButton extends StatelessWidget {
  const _OverlayCircleButton({
    required this.icon,
    required this.size,
    required this.onTap,
    required this.semanticLabel,
    this.buttonKey,
  });

  final IconData icon;
  final double size;
  final VoidCallback? onTap;
  final String semanticLabel;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final space = context.space;
    return Material(
      color: color.overlaySurface,
      shape: CircleBorder(side: BorderSide(color: color.line)),
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: space.iconLg,
            color: onTap == null ? color.muted : color.ink,
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    );
  }
}

/// 남은 시간을 그리는 링. 12시 방향에서 시작해 시계 방향으로 줄어든다.
class _TimerRingPainter extends CustomPainter {
  const _TimerRingPainter({
    required this.remaining,
    required this.track,
    required this.fill,
    required this.thickness,
  });

  final double remaining;
  final Color track;
  final Color fill;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - thickness) / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = track,
    );
    if (remaining <= 0) {
      return;
    }
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * remaining.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round
        ..color = fill,
    );
  }

  @override
  bool shouldRepaint(_TimerRingPainter oldDelegate) =>
      oldDelegate.remaining != remaining ||
      oldDelegate.track != track ||
      oldDelegate.fill != fill ||
      oldDelegate.thickness != thickness;
}
