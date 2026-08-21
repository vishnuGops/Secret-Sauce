/// Thrown when a write completed without touching a row.
///
/// PostgREST reports an `UPDATE` or `DELETE` that matched **zero** rows as a
/// success (Gotcha 2), so an RLS denial on those verbs is invisible to the
/// client — the twin of B011 on the server side. `INSERT`/`UPSERT` are
/// different: violating a `with check` clause raises `42501`, which surfaces
/// through the caller's `catch` on its own.
///
/// The only way to tell "saved" from "silently discarded" is to ask for the
/// affected rows back with `.select()` and check that the list is non-empty.
/// Repositories on paths where the user may not own the row do exactly that and
/// throw this instead of returning as though the write landed.
class WriteDeniedException implements Exception {
  const WriteDeniedException(this.action, {this.detail});

  /// What was attempted, in words the UI can show — e.g. `'save this recipe'`.
  final String action;

  /// Optional extra context for logs (an id, a table).
  final String? detail;

  /// The sentence a screen shows. Separate from [toString] so `friendlyError`
  /// can surface it without the class name in front of it.
  String get message =>
      'Could not $action — it may have been deleted, or you '
      'may no longer have permission to change it.';

  @override
  String toString() =>
      detail == null
          ? 'WriteDeniedException: $message'
          : 'WriteDeniedException: $message ($detail)';
}
