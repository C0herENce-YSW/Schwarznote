#!/bin/sh
# Sets up a local virtualenv on first run, then starts the signing service.
set -e
cd "$(dirname "$0")"
if [ ! -d .venv ]; then
  python3 -m venv .venv
  .venv/bin/pip install -q --upgrade pip
  .venv/bin/pip install -q -r requirements.txt
  .venv/bin/python -m playwright install chromium
fi
exec .venv/bin/python server.py
