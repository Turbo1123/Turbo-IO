#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
hermes_test_python="${HERMES_PYTHON:-$HOME/.hermes/hermes-agent/venv/bin/python}"
if [ ! -x "$hermes_test_python" ]; then
    hermes_test_python=python3
fi
node --test agent-bridge/*.test.mjs
PYTHONDONTWRITEBYTECODE=1 "$hermes_test_python" -B -m unittest discover -s agent-bridge -p 'test_*.py'
xcrun swift test --package-path rayneo-session --scratch-path artifacts/hermes-tasks/swift-build
