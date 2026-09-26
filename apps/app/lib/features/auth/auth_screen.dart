import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/auth/auth_controller.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/routing/pop_or_go.dart';
import 'package:app/widgets/legal_footer.dart';
import 'package:app/widgets/route_title.dart';

/// The form's measure.
const double _kFormMaxWidth = 420;

/// Stroke of the submit button's in-flight spinner.
const double _kSpinnerStroke = 2;

/// Combined sign-in / sign-up screen with a mode toggle.

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.startOnSignUp = false, this.returnTo});

  /// Which door the visitor came through: `/auth` is sign in, `/auth?mode=signup`
  /// is sign up. Only the initial mode — the toggle still owns it after that.
  final bool startOnSignUp;

  /// Where a successful sign-in goes (UX-017): the page that sent the visitor
  /// here, from `?from=`. Already checked by `safeReturnPath` in the route
  /// builder, so it is an in-app path or null — never a URL off the site.
  final String? returnTo;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  late bool _isSignUp = widget.startOnSignUp;

  /// Set after a sign-up that returned no session (UX-018): the address the
  /// confirmation mail went to. The form gives way to "check your inbox".
  String? _awaitingConfirmation;

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
    SignUpOutcome? outcome;
    if (_isSignUp) {
      outcome = await controller.signUp(
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
    } else if (outcome == SignUpOutcome.confirmEmail) {
      // UX-018: GoTrue created the account and returned no session, which is
      // what the hosted project (email confirmation on) always does. Leaving
      // the screen here dropped the new user, signed out, on Discover with no
      // word about the mail they now have to open.
      setState(() => _awaitingConfirmation = _email.text.trim());
    } else if (widget.returnTo != null) {
      // UX-017: back to the recipe, editor or list that sent them here.
      context.go(widget.returnTo!);
    } else {
      // Signed in: back where they were if `/auth` was pushed over something,
      // Discover if they landed here cold.
      popOrGo(context, Routes.discover);
    }
  }

  /// "Check your inbox" — what a sign-up that needs confirming leaves behind.
  Widget _confirmEmail(BuildContext context, String email) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.mark_email_unread_outlined,
          size: AppIconSize.xxl,
          color: scheme.primary,
        ),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          header: true,
          child: Text(
            'Check your inbox',
            style: textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'We sent a confirmation link to $email. Open it to finish creating '
          'your account, then sign in here.',
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed:
              () => setState(() {
                _awaitingConfirmation = null;
                _isSignUp = false;
                _password.clear();
              }),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }

  // UX-051: the tab follows the side the form is on.
  @override
  Widget build(BuildContext context) => RouteTitle(
    page: _isSignUp ? 'Create account' : 'Sign in',
    child: _buildPage(context),
  );

  Widget _buildPage(BuildContext context) {
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
          // Back to the page that sent them (UX-017's `returnTo`) — unless
          // that page is itself guarded, which would bounce straight back
          // here (Phase 37 review).
          onPressed:
              () => popOrGo(context, switch (widget.returnTo) {
                final to? when !Routes.needsAuth(Uri.parse(to).path) => to,
                _ => Routes.discover,
              }),
        ),
        title: const Text('Secret Sauce'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kFormMaxWidth),
            child: switch (_awaitingConfirmation) {
              final email? => _confirmEmail(context, email),
              null => _form(context, isLoading),
            },
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, bool isLoading) {
    // UX-015: one AutofillGroup, so a password manager fills the address and
    // password together and offers to save them after a sign-up; hints on
    // every field; Next/Next/Done on the keyboard, and Enter on the last field
    // submits — on the web that is what a reader presses.
    return AutofillGroup(
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
                autofillHints: const [AutofillHints.name],
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  counterText: '',
                ),
                validator:
                    (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              autocorrect: false,
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
              // `newPassword` on sign-up is what makes a manager offer to
              // generate one; `password` on sign-in makes it offer the saved one.
              autofillHints: [
                _isSignUp ? AutofillHints.newPassword : AutofillHints.password,
              ],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) async {
                if (!isLoading) await _submit();
              },
              decoration: const InputDecoration(labelText: 'Password'),
              validator:
                  (v) =>
                      (v == null || v.length < 6) ? 'Min 6 characters' : null,
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
    );
  }
}
