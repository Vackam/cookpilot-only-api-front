import 'package:flutter/material.dart';

import '../../../design/design_tokens.dart';
import '../mvp_widgets.dart';
import 'cook_layout.dart';
import 'cook_session_view_model.dart';

/// 지금까지 써 온 배치. 세로 스크롤 목록 위에 사진·설명·타이머·음성을 차례로 쌓는다.
///
/// 다른 배치를 비교할 때의 기준선이라, 배치 분리 전 화면과 픽셀 단위로 같게 둔다.
class ClassicCookLayout extends CookLayout {
  const ClassicCookLayout() : super(id: 'classic', label: '기본 배치');

  @override
  Widget build(BuildContext context, CookSessionViewModel vm) {
    final color = context.color;
    final type = context.type;
    final space = context.space;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: vm.finishing ? null : vm.onClose,
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(
          '${vm.recipeTitle} · ${vm.servings}인분',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            space.screenPaddingX,
            space.snugGap,
            space.screenPaddingX,
            space.majorGap,
          ),
          children: [
            Row(
              children: [
                Text(
                  vm.stepCounterLabel,
                  style: type.body.copyWith(fontWeight: type.black),
                ),
                SizedBox(width: space.blockGap),
                Expanded(
                  child: Text(
                    '자동 저장됨',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.body.copyWith(color: color.slate),
                  ),
                ),
              ],
            ),
            SizedBox(height: space.snugGap),
            LinearProgressIndicator(value: vm.progress),
            SizedBox(height: space.sectionGap),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FoodImage(
                  image: vm.stepImageUrl,
                  width: double.infinity,
                  height: space.stepImageHeight,
                  radius: space.radiusXl,
                ),
                SizedBox(height: space.sectionGap),
                Text(
                  vm.stepTitle,
                  style: type.titleLarge.copyWith(
                    color: color.ink,
                    fontWeight: type.black,
                  ),
                ),
                SizedBox(height: space.snugGap),
                Text(
                  vm.stepDescription,
                  style: type.body.copyWith(color: color.slate),
                ),
              ],
            ),
            SizedBox(height: space.sectionGap),
            Container(
              padding: EdgeInsets.all(space.screenPaddingX),
              decoration: BoxDecoration(
                color: color.inverseSurface,
                borderRadius: BorderRadius.circular(space.radiusXl),
                boxShadow: [
                  BoxShadow(
                    color: color.shadow,
                    blurRadius: space.shadowBlur,
                    offset: Offset(0, space.shadowLift),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    '남은 시간',
                    style: type.body.copyWith(color: color.onInverseMuted),
                  ),
                  SizedBox(height: space.snugGap),
                  // 시계만 실제로 동작하는 부분: 타이머 상태에 맞춰 매초 갱신된다.
                  AnimatedBuilder(
                    animation: vm.timer,
                    builder: (context, _) => Text(
                      formatRemaining(vm.timer.remaining),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.numeric.copyWith(color: color.onInverse),
                    ),
                  ),
                  SizedBox(height: space.itemGap),
                  AnimatedBuilder(
                    animation: vm.timer,
                    builder: (context, _) => PressableScale(
                      child: FilledButton(
                        onPressed: vm.canToggleTimer ? vm.onToggleTimer : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: color.accent,
                          minimumSize: Size.fromHeight(
                            space.compactControlHeight,
                          ),
                        ),
                        child: Text(vm.timerActionLabel()),
                      ),
                    ),
                  ),
                  SizedBox(height: space.itemGap),
                  // 시계 보조 컨트롤: 1분 추가 / 리셋. 다크 카드에 맞춘 아웃라인 버튼.
                  AnimatedBuilder(
                    animation: vm.timer,
                    builder: (context, _) {
                      final style = OutlinedButton.styleFrom(
                        foregroundColor: color.onInverse,
                        side: BorderSide(color: color.inverseLine),
                        minimumSize: Size.fromHeight(space.avatarSize),
                      );
                      return Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: vm.canAddMinute
                                  ? vm.onAddMinute
                                  : null,
                              icon: Icon(Icons.add_rounded, size: space.iconMd),
                              label: const Text('1분 추가'),
                              style: style,
                            ),
                          ),
                          SizedBox(width: space.itemGap),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: vm.canResetTimer
                                  ? vm.onResetTimer
                                  : null,
                              icon: Icon(
                                Icons.refresh_rounded,
                                size: space.iconMd,
                              ),
                              label: const Text('리셋'),
                              style: style,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: space.blockGap),
            InfoStrip(
              key: const Key('voice-input-status'),
              icon: vm.speechIcon,
              title: vm.speechTitle,
              body: vm.speechBody,
            ),
            SizedBox(height: space.itemGap),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('voice-input-toggle'),
                    onPressed: vm.canToggleSpeech ? vm.onToggleSpeech : null,
                    icon: Icon(
                      vm.speechIsActive
                          ? Icons.stop_rounded
                          : Icons.mic_rounded,
                      size: space.iconMd,
                    ),
                    label: Text(vm.speechButtonLabel),
                  ),
                ),
                SizedBox(width: space.itemGap),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('help-request'),
                    onPressed: vm.canAskHelp ? vm.onAskHelp : null,
                    icon: Icon(Icons.keyboard_rounded, size: space.iconMd),
                    label: const Text('직접 입력'),
                  ),
                ),
                SizedBox(width: space.itemGap),
                Expanded(
                  child: FilledButton.tonalIcon(
                    key: const Key('coach-toggle'),
                    onPressed: vm.canToggleCoach ? vm.onToggleCoach : null,
                    icon: Icon(
                      vm.coachActive
                          ? Icons.stop_rounded
                          : Icons.headset_mic_rounded,
                      size: space.iconMd,
                    ),
                    label: Text(vm.coachButtonLabel),
                  ),
                ),
              ],
            ),
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
              style: type.caption.copyWith(color: color.slate),
            ),
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
            if (vm.finishError case final String error) ...[
              SizedBox(height: space.blockGap),
              InfoStrip(
                key: const Key('cooking-completion-error'),
                icon: Icons.error_outline_rounded,
                title: '완료 정보를 저장하지 못했어요',
                body: error,
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.fromLTRB(
          space.screenPaddingX,
          space.snugGap,
          space.screenPaddingX,
          space.screenPaddingX,
        ),
        child: PressableScale(
          child: FilledButton(
            onPressed: vm.canAdvance ? vm.onAdvance : null,
            child: Text(vm.advanceLabel),
          ),
        ),
      ),
    );
  }
}
