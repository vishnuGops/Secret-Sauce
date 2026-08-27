import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The wall clock cook mode measures against.
///
/// Injectable for one reason: the timers below are **deadline**-based, and
/// `tester.pump(Duration(seconds: 1))` advances Flutter's fake timer queue
/// without moving `DateTime.now()` by a microsecond — so a countdown read from
/// the real clock would sit still in every widget test. The test harness
/// overrides this with `tester.binding.clock.now`, which the same pump does
/// advance.
final cookClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// One step timer. Immutable; the notifier replaces it on every tick.
///
/// A running timer is stored as a **deadline**, not as a counter that a tick
/// decrements (32c4). The two agree while the app is on screen and diverge the
/// moment it is not: a suspended app stops receiving ticks, so a decremented
/// counter would come back from a backgrounded twenty minutes still claiming
/// twenty minutes left, while a deadline is simply in the past. [remaining] is
/// kept alongside as the value the UI reads and the value a paused timer
/// carries; the tick recomputes it from [endsAt] rather than subtracting.
class CookTimer {
  const CookTimer({
    required this.total,
    required this.remaining,
    required this.running,
    this.endsAt,
  });

  final Duration total;
  final Duration remaining;
  final bool running;

  /// When this timer runs out, on the wall clock. Null while paused or done —
  /// a paused timer has no deadline, only a balance.
  final DateTime? endsAt;

  bool get isDone => remaining <= Duration.zero;

  /// 0..1, for the ring. A timer that has run out reads full, not empty.
  double get elapsedFraction {
    if (total.inSeconds <= 0) return 1;
    final gone = total.inSeconds - remaining.inSeconds;
    return (gone / total.inSeconds).clamp(0.0, 1.0);
  }

  /// [endsAt] takes `clearEndsAt` rather than a nullable default, because
  /// "leave it alone" and "there is no deadline any more" are different edits
  /// and a null argument cannot say which one it means.
  CookTimer copyWith({
    Duration? remaining,
    bool? running,
    Duration? total,
    DateTime? endsAt,
    bool clearEndsAt = false,
  }) => CookTimer(
    total: total ?? this.total,
    remaining: remaining ?? this.remaining,
    running: running ?? this.running,
    endsAt: clearEndsAt ? null : (endsAt ?? this.endsAt),
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

  DateTime _now() => ref.read(cookClockProvider)();

  @override
  CookSessionState build(String recipeId) {
    ref.onDispose(() => _ticker?.cancel());
    return CookSessionState(stepIndex: 0, startedAt: _now());
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
  ///
  /// Either way the deadline is stamped here, from the balance that is being
  /// started: a resume owes what was left when it was paused, not the full
  /// duration.
  void startTimer(String stepId, Duration total) {
    final existing = state.timers[stepId];
    final resuming = existing != null && !existing.running && !existing.isDone;
    final balance = resuming ? existing.remaining : total;
    _writeTimer(
      stepId,
      CookTimer(
        total: resuming ? existing.total : total,
        remaining: balance,
        running: true,
        endsAt: _now().add(balance),
      ),
    );
    _syncTicker();
  }

  /// Banks whatever is left *now* and drops the deadline. Without recomputing
  /// here, a pause during the second between two ticks would round in the
  /// cook's favour by up to a second on every pause.
  void pauseTimer(String stepId) {
    final t = state.timers[stepId];
    if (t == null) return;
    _writeTimer(
      stepId,
      t.copyWith(remaining: _remainingOf(t), running: false, clearEndsAt: true),
    );
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
  /// is the answer to "not done yet" — and that case is why the new deadline is
  /// measured from **now** rather than pushed out from the old one: the old
  /// deadline is in the past, and adding a minute to it would buy nothing.
  void addMinute(String stepId) {
    final t = state.timers[stepId];
    if (t == null) return;
    const minute = Duration(minutes: 1);
    final balance = _remainingOf(t) + minute;
    _writeTimer(
      stepId,
      t.copyWith(
        total: t.total + minute,
        remaining: balance,
        running: true,
        endsAt: _now().add(balance),
      ),
    );
    _dismissAlarm(stepId);
    _syncTicker();
  }

  /// What [t] has left on the wall clock: its stored balance when it is not
  /// running, and the distance to its deadline when it is.
  Duration _remainingOf(CookTimer t) {
    if (!t.running || t.endsAt == null) return t.remaining;
    final left = t.endsAt!.difference(_now());
    return left.isNegative ? Duration.zero : left;
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

  /// One pass over every timer, reading the clock rather than counting ticks.
  ///
  /// The periodic is only a *prompt to look*: a tick that arrives late, or not
  /// at all because the app was suspended, changes when the cook is told the
  /// timer expired, never by how much.
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
      final remaining = _remainingOf(t);
      if (remaining <= Duration.zero) {
        next[entry.key] = t.copyWith(
          remaining: Duration.zero,
          running: false,
          clearEndsAt: true,
        );
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
