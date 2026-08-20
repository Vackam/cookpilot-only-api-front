import 'dart:async';

import 'package:cookpilot/features/cooking/application/coach_transcript_store.dart';
import 'package:cookpilot/features/cooking/application/cooking_coach_controller.dart';
import 'package:cookpilot/features/cooking/application/cooking_ports.dart';
import 'package:cookpilot/features/cooking/application/monotonic_clock.dart';

final class FakeSpeechInput implements SpeechInputPort {
  int startCount = 0;
  int stopCount = 0;
  Object? startError;
  Object? stopError;
  SpeechInputFailure? startFailure;
  bool activateBeforeStartError = false;
  bool autoReady = true;
  bool hangOnStop = false;
  Completer<void>? pendingStop;
  void Function()? onStart;
  SpeechInputReadyHandler? onReady;
  SpeechUtteranceHandler? onUtterance;
  SpeechInputFailureHandler? onFailure;
  final List<SpeechUtteranceHandler> utteranceHandlers =
      <SpeechUtteranceHandler>[];

  @override
  void start({
    required SpeechInputReadyHandler onReady,
    required SpeechUtteranceHandler onUtterance,
    required SpeechInputFailureHandler onFailure,
  }) {
    startCount += 1;
    final currentError = startError;
    if (currentError != null && !activateBeforeStartError) {
      throw currentError;
    }
    this.onReady = onReady;
    this.onUtterance = onUtterance;
    this.onFailure = onFailure;
    utteranceHandlers.add(onUtterance);
    onStart?.call();
    if (currentError != null) {
      throw currentError;
    }
    final currentFailure = startFailure;
    if (currentFailure != null) {
      onFailure(currentFailure);
      return;
    }
    if (autoReady) {
      onReady();
    }
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    if (hangOnStop) {
      pendingStop ??= Completer<void>();
      await pendingStop!.future;
    }
    final currentError = stopError;
    if (currentError != null) {
      throw currentError;
    }
  }

  void emitUtterance(String utterance, {String? utteranceId}) {
    onUtterance?.call(utterance, utteranceId);
  }

  void emitReady() {
    onReady?.call();
  }

  void emitFailure(SpeechInputFailure failure) {
    onFailure?.call(failure);
  }

  void completePendingStop() {
    final completion = pendingStop;
    if (completion != null && !completion.isCompleted) {
      completion.complete();
    }
  }
}

final class FakeTimerAlarm implements TimerAlarmPort {
  int signalCount = 0;
  int cancelCount = 0;
  final List<DateTime> scheduledAt = <DateTime>[];

  DateTime? get lastScheduledAt =>
      scheduledAt.isEmpty ? null : scheduledAt.last;

  @override
  void signalTimerElapsed() => signalCount += 1;

  @override
  Future<void> scheduleTimerElapsed(DateTime at) async => scheduledAt.add(at);

  @override
  Future<void> cancelScheduledAlarm() async => cancelCount += 1;
}

final class FakeMonotonicClock implements MonotonicClock {
  Duration _elapsed = Duration.zero;
  bool _isRunning = false;

  @override
  Duration get elapsed => _elapsed;

  @override
  bool get isRunning => _isRunning;

  void elapse(Duration duration) {
    if (_isRunning) {
      _elapsed += duration;
    }
  }

  @override
  void reset() => _elapsed = Duration.zero;

  @override
  void start() => _isRunning = true;

  @override
  void stop() => _isRunning = false;
}

final class FakeSpeechOutput implements SpeechOutputPort {
  final List<String> spoken = <String>[];
  int stopCount = 0;
  int disposeCount = 0;
  Object? error;
  Object? stopError;
  bool hangOnStop = false;
  Completer<void>? pendingStop;

  @override
  Future<void> speak(String text) {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    spoken.add(text);
    return Future<void>.value();
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    if (hangOnStop) {
      pendingStop ??= Completer<void>();
      await pendingStop!.future;
    }
    final currentStopError = stopError;
    if (currentStopError != null) {
      throw currentStopError;
    }
  }

  @override
  void dispose() {
    disposeCount += 1;
    completePendingStop();
  }

  void completePendingStop() {
    final completion = pendingStop;
    if (completion != null && !completion.isCompleted) {
      completion.complete();
    }
  }
}

final class DeferredSpeechOutput implements SpeechOutputPort {
  final List<String> spoken = <String>[];
  final List<Completer<void>> completions = <Completer<void>>[];
  int stopCount = 0;
  int disposeCount = 0;
  bool hangOnStop = false;
  Completer<void>? pendingStop;

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    final completer = Completer<void>();
    completions.add(completer);
    return completer.future;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    if (hangOnStop) {
      pendingStop ??= Completer<void>();
      await pendingStop!.future;
    }
    for (final completion in completions) {
      if (!completion.isCompleted) {
        completion.complete();
      }
    }
  }

  @override
  void dispose() {
    disposeCount += 1;
    completePendingStop();
    for (final completion in completions) {
      if (!completion.isCompleted) {
        completion.complete();
      }
    }
  }

  void completePendingStop() {
    final completion = pendingStop;
    if (completion != null && !completion.isCompleted) {
      completion.complete();
    }
  }
}

final class FakeExceptionAdvicePort implements ExceptionAdvicePort {
  FakeExceptionAdvicePort({
    this.response = const ExceptionAdvice(message: '불을 낮추고 30초 더 확인하세요.'),
    this.error,
  });

  final ExceptionAdvice response;
  Object? error;
  final List<ExceptionAdviceContext> requests = <ExceptionAdviceContext>[];

  @override
  Future<ExceptionAdvice> requestAdvice(ExceptionAdviceContext context) async {
    requests.add(context);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return response;
  }
}

final class DeferredExceptionAdvicePort implements ExceptionAdvicePort {
  final completer = Completer<ExceptionAdvice>();
  ExceptionAdviceContext? request;

  @override
  Future<ExceptionAdvice> requestAdvice(ExceptionAdviceContext context) {
    request = context;
    return completer.future;
  }
}

final class QueuedExceptionAdvicePort implements ExceptionAdvicePort {
  final List<ExceptionAdviceContext> requests = <ExceptionAdviceContext>[];
  final List<Completer<ExceptionAdvice>> completions =
      <Completer<ExceptionAdvice>>[];

  @override
  Future<ExceptionAdvice> requestAdvice(ExceptionAdviceContext context) {
    requests.add(context);
    final completer = Completer<ExceptionAdvice>();
    completions.add(completer);
    return completer.future;
  }
}

/// 코치 대화 로그의 저장·복원·정리 호출을 관찰한다.
final class FakeCoachTranscriptStore implements CoachTranscriptGateway {
  FakeCoachTranscriptStore({this.stored, this.failSave = false});

  /// 앱 시작 시점에 이미 저장돼 있던 로그.
  CoachTranscript? stored;
  bool failSave;

  final List<CoachTranscript> saved = <CoachTranscript>[];
  int saveAttempts = 0;
  int loadCount = 0;
  int clearCount = 0;

  @override
  Future<void> save(CoachTranscript transcript) async {
    saveAttempts++;
    if (failSave) {
      throw StateError('save failed');
    }
    saved.add(transcript);
    stored = transcript;
  }

  @override
  Future<CoachTranscript?> load() async {
    loadCount++;
    return stored;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    stored = null;
  }
}

/// 세션을 열지 않고 시작 시점 프롬프트만 붙잡는 코치 엔진.
final class FakeCoachEngine implements CookingCoachEngine {
  FakeCoachEngine({required this.onStateChanged, required this.buildPrompt});

  final CookingCoachStateHandler onStateChanged;
  final String Function() buildPrompt;

  /// start()마다 그 시점의 프롬프트를 그대로 기록한다.
  final List<String> startPrompts = <String>[];
  final List<String> contextUpdates = <String>[];

  CookingCoachPhase _phase = CookingCoachPhase.idle;

  @override
  CookingCoachPhase get phase => _phase;

  @override
  bool get isActive => _phase != CookingCoachPhase.idle;

  @override
  Future<void> start(String recipeId) async {
    startPrompts.add(buildPrompt());
    _emit(CookingCoachPhase.live, '코치가 듣고 있어요.');
  }

  @override
  void interrupt() {}

  @override
  void updateContext(String text) {
    if (_phase == CookingCoachPhase.live) {
      contextUpdates.add(text);
    }
  }

  @override
  Future<void> stop() async {
    _emit(CookingCoachPhase.idle, 'AI 코치를 껐어요.');
  }

  @override
  void dispose() {
    _phase = CookingCoachPhase.idle;
  }

  void _emit(CookingCoachPhase phase, String? message) {
    _phase = phase;
    onStateChanged(phase, message);
  }
}
