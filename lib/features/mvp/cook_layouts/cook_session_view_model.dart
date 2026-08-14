import 'package:flutter/material.dart';

import '../../cooking/application/cooking_coach_controller.dart';
import '../../cooking/application/timer_controller.dart';
import '../../cooking/domain/cooking_session_state.dart';
import '../../cooking/presentation/cooking_voice_session_controller.dart';

/// 조리 중 화면이 그릴 값과 실행할 동작.
///
/// 배치([CookLayout] 구현체)는 이 객체만 보고 화면을 그린다. 타이머·STT·코치·
/// 저장 로직은 여전히 `_CookSessionScreenState`가 통째로 갖고 있고 여기로
/// 옮기지 않았다. 지금 필요한 건 배치 교체뿐이라 상태는 건드리지 않는다.
///
/// 타이머는 매 초 갱신되므로 값을 복사하지 않고 컨트롤러를 그대로 넘긴다.
/// 배치는 [timer]를 [AnimatedBuilder]로 감싸 읽는다. 같은 이유로
/// [timerActionLabel]은 문자열이 아니라 함수다.
@immutable
class CookSessionViewModel {
  const CookSessionViewModel({
    required this.recipeTitle,
    required this.servings,
    required this.stepNumber,
    required this.stepCount,
    required this.stepTitle,
    required this.stepDescription,
    required this.stepImageUrl,
    required this.timer,
    required this.hasTimer,
    required this.timerActionLabel,
    required this.speechPhase,
    required this.speechIcon,
    required this.speechTitle,
    required this.speechBody,
    required this.speechButtonLabel,
    required this.coachPhase,
    required this.coachActive,
    required this.coachMessage,
    required this.helpLoading,
    required this.helpAnswer,
    required this.helpRequestInFlight,
    required this.finishing,
    required this.locked,
    required this.finishError,
    required this.onClose,
    required this.onToggleTimer,
    required this.onAddMinute,
    required this.onResetTimer,
    required this.onToggleSpeech,
    required this.onAskHelp,
    required this.onToggleCoach,
    required this.onAdvance,
    required this.onPrevStep,
  });

  final String recipeTitle;
  final int servings;

  /// 1부터 센다.
  final int stepNumber;
  final int stepCount;
  final String stepTitle;
  final String stepDescription;

  /// 단계 사진이 없으면 레시피 대표 사진으로 이미 대체된 값.
  final String stepImageUrl;

  final LocalTimerController timer;

  /// 이 단계에 타이머가 걸려 있는지. 없으면 타이머 조작 전부가 잠긴다.
  final bool hasTimer;

  /// 타이머 상태에 따라 매 틱 달라지므로 함수로 받는다.
  final String Function() timerActionLabel;

  final CookingVoiceSpeechPhase speechPhase;
  final IconData speechIcon;
  final String speechTitle;
  final String speechBody;
  final String speechButtonLabel;

  final CookingCoachPhase coachPhase;

  /// 코치 엔진이 실제로 살아 있는지. [coachPhase]와 잠깐 어긋날 수 있어 따로 받는다.
  final bool coachActive;
  final String? coachMessage;

  final bool helpLoading;
  final String? helpAnswer;
  final bool helpRequestInFlight;

  final bool finishing;

  /// 완료 확인 중이라 조리 조작을 전부 잠근 상태.
  final bool locked;
  final String? finishError;

  final VoidCallback onClose;
  final VoidCallback onToggleTimer;
  final VoidCallback onAddMinute;
  final VoidCallback onResetTimer;
  final VoidCallback onToggleSpeech;
  final VoidCallback onAskHelp;
  final VoidCallback onToggleCoach;

  /// 마지막 단계면 조리 완료, 아니면 다음 단계.
  final VoidCallback onAdvance;
  final VoidCallback onPrevStep;

  bool get isLastStep => stepNumber == stepCount;

  double get progress => stepNumber / stepCount;

  /// 단계 표시 문구. 배치가 달라도 같은 문장을 쓰도록 여기서 만든다.
  String get stepCounterLabel => '$stepNumber / $stepCount 단계';

  String get advanceLabel {
    if (!isLastStep) {
      return '다음 단계';
    }
    return finishing ? '완료 저장 중' : '조리 완료';
  }

  String get coachButtonLabel => switch (coachPhase) {
    CookingCoachPhase.idle => 'AI 코치',
    CookingCoachPhase.connecting => '연결 중…',
    CookingCoachPhase.live => '코치 끄기',
    CookingCoachPhase.stopping => '끄는 중…',
  };

  bool get speechIsActive =>
      speechPhase == CookingVoiceSpeechPhase.starting ||
      speechPhase == CookingVoiceSpeechPhase.listening;

  // 아래 네 게터는 타이머 상태를 읽으므로 AnimatedBuilder 안에서 평가해야 한다.
  bool get canToggleTimer =>
      !locked && hasTimer && timer.status != TimerStatus.elapsed;

  bool get canAddMinute => !locked && hasTimer;

  bool get canResetTimer =>
      !locked && hasTimer && timer.status != TimerStatus.idle;

  bool get canToggleSpeech =>
      !locked && speechPhase != CookingVoiceSpeechPhase.stopping;

  bool get canAskHelp => !locked && !helpRequestInFlight;

  bool get canToggleCoach =>
      !locked &&
      coachPhase != CookingCoachPhase.connecting &&
      coachPhase != CookingCoachPhase.stopping;

  bool get canAdvance => !finishing;

  bool get canGoPrev => !locked && !finishing && stepNumber > 1;
}

/// 남은 시간 표기. 1초 미만이 0으로 보이지 않도록 올림한다.
String formatRemaining(Duration remaining) {
  final totalSeconds = (remaining.inMilliseconds / 1000).ceil().clamp(0, 5999);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

/// AI 전송 고지. 배치가 달라도 같은 문장을 보여야 하므로 한 곳에 둔다.
const aiDataDisclosure =
    'AI 질문은 답변 생성을 위해 Google Gemini로 전송될 수 있어요. '
    '개인정보·건강정보는 말하거나 입력하지 마세요.';
