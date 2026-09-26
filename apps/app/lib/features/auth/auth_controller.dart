import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Handles the auth **form** submissions and exposes their [AsyncValue] state.
///
/// Sign-out is deliberately not here (OPT-A3): it is triggered from the web
/// account menu and the profile screen, neither of which is part of this
/// feature, and it has no form state to own — both call
/// `authRepositoryProvider.signOut()` directly rather than importing this file.
class AuthController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> signIn({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repo.signIn(email: email, password: password),
    );
  }

  /// Null when the sign-up failed (the error is in [state]); otherwise whether
  /// the new account is signed in or waiting on its confirmation mail
  /// (UX-018).
  Future<SignUpOutcome?> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    state = const AsyncLoading();
    SignUpOutcome? outcome;
    state = await AsyncValue.guard(() async {
      outcome = await _repo.signUp(
        email: email,
        password: password,
        displayName: displayName,
      );
    });
    return outcome;
  }
}

final authControllerProvider =
    AutoDisposeAsyncNotifierProvider<AuthController, void>(AuthController.new);
