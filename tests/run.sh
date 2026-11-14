#!/usr/bin/env bash
# Runs every suite.
set -euo pipefail
cd "$(dirname "$0")/.."
echo "== python: discover.py"
python3 -I -m unittest discover -s tests -p "test_*.py"
echo "== node: Model.js, Strings.js"
node --test tests/*.test.mjs
if command -v omarchy >/dev/null; then
  echo "== omarchy plugin validate"
  omarchy plugin validate .
fi
echo "all suites passed"
