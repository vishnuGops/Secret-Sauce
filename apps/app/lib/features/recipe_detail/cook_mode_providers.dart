import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One step timer. Immutable; the notifier replaces it on every tick.
class CookTimer {
  const CookTimer({
    required this.total,
    required this.remaining,
    required this.running,
  });

  final Duration total;
  final Duration remaining;
  final bool running;

  bool get isDone => remaining <= Duration.zero;

  /// 0..1, for the ring. A timer that has run out reads full, not empty.
  double get elapsedFraction {
    if (total.inSeconds <= 0) return 1;
    final gone = total.inSeconds - remaining.inSeconds;
    return (gone / total.inSeconds).clamp(0.0, 1.0);
  }

  CookTimer copyWith({Duration? remaining, bool? running, Duration? total}) =>
      CookTimer(
        total: total ?? this.total,
        remaining: remaining ?? this.remaining,
        running: running ?? this.running,
      );
}

/// Everything one cooking session holds.
class CookSessionState {
  const CookSessionState({
    required this.stepIndex,
    required this.startedAt,
    this.timers = const {},
    this.ringing = const {},
    this.finished = false,
  });

  /// Which step the cook is standing on, 0-based into [flattenCookSteps]'s list.
  final int stepIndex;

  /// When cook mode opened — the finish screen compares this against the
  /// recipe's own estimate. Set once, from the wall clock, at construction.
  final DateTime startedAt;

  /// Timers by step id. Several may run at once **by design**: a chill or a bake
  /// keeps counting while you move on to the next step, which is the whole
  /// reason a step timer beats a kitchen timer. One periodic tick drives them
  /// all, so the count is independent of how many there are.
  final Map<String, CookTimer> timers;

  /// Step ids whose timer has reached zero and has not been acknowledged. The
  /// alarm is a UI state, not an event, so it survives a rebuild and a step
  /// change — a bake that finishes while you are reading step 3 is still ringing
  /// when you look up.
  final Set<String> ringing;

  final bool finished;

  CookSessionState copyWith({
    int? stepIndex,
    Map<String, CookTimer>? timers,
    Set<String>? ringing,
    bool? finished,
  }) => CookSessionState(
    stepIndex: stepIndex ?? this.stepIndex,
    startedAt: startedAt,
    timers: timers ?? this.timers,
    ringing: ringing ?? this.ringing,
    finished: finished ?? this.finished,
  );
}

/// Drives one recipe's cooking session: where the cook is, and every timer.
///
/// The ticking is **one** `Timer.periodic`, started when the first timer runs
/// and cancelled when the last one stops, rather than one per step timer. That
/// is not just tidiness: a per-timer periodic left running after `dispose` is
/// the classic widget-test "Timer is still pending" failure, and there is only
/// one thing to cancel here.
class CookSessionNotifier extends FamilyNotifier<CookSessionState, String> {
  Timer? _ticker;

  @override
  CookSessionState build(String recipeId) {
    ref.onDispose(() => _ticker?.cancel());
    return CookSessionState(stepIndex: 0, startedAt: DateTime.now());
  }

  /// Moves to [index] and leaves the finish screen.
  ///
  /// The index check is on the *pair*, not on the index alone: "not done — back
  /// to the last step" targets the step the cook is already standing on, so an
  /// early return on `index == stepIndex` would clear nothing and leave the
  /// finish screen up. Caught by its own test.
  void goTo(int index) {
    if (index == state.stepIndex && !state.finished) return;
    state = state.copyWith(stepIndex: index, finished: false);
  }

  void next(int stepCount) {
    if (state.stepIndex >= stepCount - 1) {
      state = state.copyWith(finished: true);
      return;
    }
    state = state.copyWith(stepIndex: state.stepIndex + 1);
  }

  void previous() {
    if (state.finished) {
      state = state.copyWith(finished: false);
      return;
    }
    if (state.stepIndex == 0) return;
    state = state.copyWith(stepIndex: state.stepIndex - 1);
  }

  void finish() => state = state.copyWith(finished: true);

  /// Starts (or restarts) [stepId]'s timer at [total], or resumes a paused one.
  void startTimer(String stepId, Duration total) {
    final existing = state.timers[stepId];
    final resume =
        existing != null && !existing.running && !existing.isDone
            ? existing.copyWith(running: true)
            : CookTimer(total: total, remaining: total, running: true);
    _writeTimer(stepId, resume);
    _syncTicker();
  }

  void pauseTimer(String stepId) {
    final t = state.timers[stepId];
    if (t == null) return;
    _writeTimer(stepId, t.copyWith(running: false));
    _syncTicker();
  }

  void resetTimer(String stepId) {
    final t = state.timers[stepId];
    if (t == null) return;
    _writeTimer(
      stepId,
      CookTimer(total: t.total, remaining: t.total, running: false),
    );
    _dismissAlarm(stepId);
    _syncTicker();
  }

  /// `+1 min`. Also un-rings a timer that had just run out, since extending it
  /// is the answer to "not done yet".
  void addMinute(String stepId) {
    final t = state.timers[stepId];
    if (t == null) return;
    _writeTimer(
      stepId,
      t.copyWith(
        total: t.total + const Duration(minutes: 1),
        remaining: t.remaining + const Duration(minutes: 1),
        running: true,
      ),
    );
    _dismissAlarm(stepId);
    _syncTicker();
  }

  /// Acknowledges the alarm without touching the timer, so the step can still
  /// show `0:00 · done`.
  void dismissAlarm(String stepId) {
    _dismissAlarm(stepId);
  }

  void _dismissAlarm(String stepId) {
    if (!state.ringing.contains(stepId)) return;
    state = state.copyWith(ringing: {...state.ringing}..remove(stepId));
  }

  void _writeTimer(String stepId, CookTimer timer) {
    state = state.copyWith(timers: {...state.timers, stepId: timer});
  }

  void _syncTicker() {
    final anyRunning = state.timers.values.any((t) => t.running && !t.isDone);
    if (anyRunning && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else if (!anyRunning) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _tick() {
    final next = <String, CookTimer>{};
    final ringing = {...state.ringing};
    var rangNow = false;
    for (final entry in state.timers.entries) {
      final t = entry.value;
      if (!t.running || t.isDone) {
        next[entry.key] = t;
        continue;
      }
      final remaining = t.remaining - const Duration(seconds: 1);
      if (remaining <= Duration.zero) {
        next[entry.key] = t.copyWith(remaining: Duration.zero, running: false);
        ringing.add(entry.key);
        rangNow = true;
      } else {
        next[entry.key] = t.copyWith(remaining: remaining);
      }
    }
    state = state.copyWith(timers: next, ringing: ringing);
    if (rangNow) _alarm();
    _syncTicker();
  }

  /// The chime. `SystemSound` and `HapticFeedback` are Flutter's own platform
  /// channels, so this needs no dependency — and that is also its limit: it only
  /// fires while the app is in the foreground. Cook mode's copy says "keep this
  /// screen open" rather than promising an alarm that survives the screen going
  /// off, which would need a real notification plugin and platform config.
  void _alarm() {
    unawaited(SystemSound.play(SystemSoundType.alert));
    unawaited(HapticFeedback.vibrate());
  }
}

/// One cooking session per recipe.
///
/// Deliberately **not** `autoDispose`: the session holds the timers, and a chill
/// step's 60 minutes must not be thrown away because the cook backed out to
/// check the ingredient list. It is disposed when the provider scope is — i.e.
/// on app exit — which is the same session lifetime the ingredient and step
/// check-offs already have.
final cookSessionProvider =
    NotifierProvider.family<CookSessionNotifier, CookSessionState, String>(
      CookSessionNotifier.new,
    );
