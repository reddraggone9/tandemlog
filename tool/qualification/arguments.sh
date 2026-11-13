# Explicit paths supplied by qualification.py; no historical run dependencies.
ARGS=(--repo "$Q/source" --request "$Q/request.json" --output "$Q/invocation"
      --dart "$DART" --native-library "$NATIVE" --sqlite-library "$SQLITE"
      --controller "$CTRL" --controller-sha256 "$R8_SHA")
