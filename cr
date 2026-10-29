#!/bin/sh
# Runs the Control Room command, building it first if the code changed.
cd "$(dirname "$0")" && exec swift run --quiet -c release cr "$@"
