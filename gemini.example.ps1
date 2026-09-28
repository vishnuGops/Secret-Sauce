# Shell-only Gemini API key for `melos run covers:gen` (tool/recipe_covers.dart).
#
# Copy to `gemini.local.ps1` (git-ignored via *.local.ps1), paste the key, then
# dot-source it in the shell you run the generator from:
#
#   . .\gemini.local.ps1
#   melos run covers:gen -- --only=fresh-guacamole
#
# Never put the key in a dart-define file (they are compiled into shipped builds,
# B034), in a committed file, or in a chat transcript.
$env:GEMINI_API_KEY = "paste-your-key-here"
