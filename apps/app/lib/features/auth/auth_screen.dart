import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/auth/auth_controller.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/routing/pop_or_go.dart';
import 'package:app/widgets/legal_footer.dart';

/// The form's measure.
const double _kFormMaxWidth = 420;

/// Stroke of the submit button's in-flight spinner.
const double _kSpinnerStroke = 2;

/// Combined sign-in / sign-up screen with a mode toggle.

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.startOnSignUp = false});

  /// Which door the visitor came through: `/auth` is sign in, `/auth?mode=signup`
  /// is sign up. Only the initial mode — the toggle still owns it after that.
  final bool startOnSignUp;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  late bool _isSignUp = widget.startOnSignUp;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(authControllerProvider.notifier);
    if (_isSignUp) {
      await controller.signUp(
        email: _email.text.trim(),
        password: _password.text,
        displayName: _name.text.trim(),
      );
    } else {
      await controller.signIn(
        email: _email.text.trim(),
        password: _password.text,
      );
    }
    final state = ref.read(authControllerProvider);
    if (!mounted) return;
    if (state.hasError) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(state.error))));
    } else {
      // Signed in: back where they were if `/auth` was pushed over something,
      // Discover if they landed here cold.
      popOrGo(context, Routes.discover);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
        // B131 / UX-002: every entry here is a `go`, and `/auth` sits outside
        // the shell, so the AppBar found nothing to pop and drew no back button
        // — a signed-out phone user who tapped Like or Profile was stranded.
        // Explicit, and `popOrGo` for the cold-start case.
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => popOrGo(context, Routes.discover),
        ),
        title: const Text('Secret-Sauce'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kFormMaxWidth),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isSignUp ? 'Create your account' : 'Welcome back',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_isSignUp) ...[
                    TextFormField(
                      controller: _name,
                      // `handle_new_user` clamps this to 80 with `left(…, 80)`
                      // rather than letting `profiles_text_lengths` refuse the
                      // signup (32a2) — so without a limit here a long name is
                      // silently truncated and the cook is never told. The field
                      // is where that gets said.
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        counterText: '',
                      ),
                      validator:
                          (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator:
                        (v) =>
                            (v == null || !v.contains('@'))
                                ? 'Enter a valid email'
                                : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator:
                        (v) =>
                            (v == null || v.length < 6)
                                ? 'Min 6 characters'
                                : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: isLoading ? null : _submit,
                    child:
                        isLoading
                            ? const SizedBox(
                              height: AppIconSize.md,
                              width: AppIconSize.md,
                              child: CircularProgressIndicator(
                                strokeWidth: _kSpinnerStroke,
                              ),
                            )
                            : Text(_isSignUp ? 'Sign up' : 'Sign in'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed:
                        isLoading
                            ? null
                            : () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(
                      _isSignUp
                          ? 'Already have an account? Sign in'
                          : "Don't have an account? Sign up",
                    ),
                  ),
                  // Phase 35a. Two jobs, and they are different.
                  //
                  // The sentence is the consent point: the one moment in the
                  // product where somebody agrees to the terms, so it says so
                  // at the moment they do it rather than in a checkbox nobody
                  // reads. It is plain text with the links directly beneath
                  // rather than tappable spans inside it — an inline recogniser
                  // needs a dispose that a StatelessWidget cannot give it, and
                  // a leaked one is a real bug for a cosmetic gain.
                  //
                  // The footer is the access point, and it is here in BOTH
                  // modes because on a phone this is the only signed-out screen
                  // that can carry it: the web chrome has its own bar, and the
                  // compact bottom slot belongs to the NavigationBar.
                  if (_isSignUp) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'By creating an account you agree to the Terms of '
                      'Service and acknowledge the Privacy Policy.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  const LegalFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
