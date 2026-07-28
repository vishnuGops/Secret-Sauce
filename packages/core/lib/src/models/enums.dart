/// Domain enums mirroring the Postgres enums exactly.
library;

import 'package:json_annotation/json_annotation.dart';

enum Difficulty {
  @JsonValue('easy')
  easy,
  @JsonValue('medium')
  medium,
  @JsonValue('hard')
  hard;

  String get label => switch (this) {
        Difficulty.easy => 'Easy',
        Difficulty.medium => 'Medium',
        Difficulty.hard => 'Hard',
      };
}

enum RecipeVisibility {
  @JsonValue('private')
  private,
  @JsonValue('public')
  public;

  bool get isPublic => this == RecipeVisibility.public;
}

enum SharePermission {
  @JsonValue('view')
  view,
  @JsonValue('edit')
  edit;
}

enum SuggestionStatus {
  @JsonValue('open')
  open,
  @JsonValue('accepted')
  accepted,
  @JsonValue('rejected')
  rejected;
}
