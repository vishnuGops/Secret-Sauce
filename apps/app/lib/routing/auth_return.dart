import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:app/routing/app_router.dart';

/// The query parameter that carries "where to go after signing in" (UX-017).
const String kAuthFromParam = 'from';

/// [raw] if it is a path **inside this app**, otherwise null.
///
/// `?from=` is attacker-controllable — anyone can send a link to
/// `/auth?from=…` — so an unchecked value is an open redirect: sign in, land on
/// a look-alike site. Only a same-app absolute path passes:
///
/// - it starts with exactly one `/` (`//evil.test` is a scheme-relative URL,
///   and `/\evil.test` is one to some browsers);
/// - it parses as a URI with no scheme and no authority;
/// - it is not `/auth` itself, which would loop.
///
/// A rejected value is not an error: the caller falls back to Discover, the
/// same place a sign-in without `from` lands.
String? safeReturnPath(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (!raw.startsWith('/') || raw.startsWith('//') || raw.startsWith(r'/\')) {
    return null;
  }
  // Control characters and backslashes anywhere are refused rather than
  // normalised: nothing the app routes to contains either.
  if (raw.contains(r'\') || raw.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
    return null;
  }
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  if (uri.path == Routes.auth || uri.path.startsWith('${Routes.auth}/')) {
    return null;
  }
  return raw;
}

/// `/auth`, carrying [from] when it is a safe in-app path, and opened on the
/// sign-up side when [signUp] is set.
String authLocation({String? from, bool signUp = false}) {
  final safe = safeReturnPath(from);
  final params = <String, String>{
    if (signUp) 'mode': 'signup',
    if (safe != null) kAuthFromParam: safe,
  };
  return Uri(
    path: Routes.auth,
    queryParameters: params.isEmpty ? null : params,
  ).toString();
}

/// Where the reader actually is, including a page opened with `push`.
///
/// `routerDelegate.currentConfiguration.uri` is the location of the last `go`
/// — a recipe pushed from Discover leaves it saying `/discover`. The pushed
/// page lives in the list as an [ImperativeRouteMatch] carrying its own match
/// list, so the top one is asked first (Phase 37 review: `?from=` pointed back
/// at Discover, and a delete could not tell the reader was still on the
/// recipe).
Uri currentLocation(GoRouter router) {
  final config = router.routerDelegate.currentConfiguration;
  if (config.isEmpty) return config.uri;
  final top = config.last;
  return top is ImperativeRouteMatch ? top.matches.uri : config.uri;
}

/// Send a signed-out visitor to `/auth`, remembering where they were so a
/// successful sign-in brings them back (UX-017) — to the recipe they tried to
/// like, fork or rate, not to Discover.
///
/// The current location comes from the router's own configuration rather than
/// `GoRouterState.of`, which only resolves inside a route's builder subtree —
/// the web top bar is built by the shell and would throw there.
void goToSignIn(BuildContext context, {bool signUp = false}) {
  final router = GoRouter.of(context);
  final here = currentLocation(router).toString();
  router.go(authLocation(from: here, signUp: signUp));
}
