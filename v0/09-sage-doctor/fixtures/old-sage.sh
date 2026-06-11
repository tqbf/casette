#!/bin/bash
if [ "$1" = "--version" ]; then
  echo "SageMath version 9.2, Release Date: 2020-10-24"
  exit 0
fi
# No real worker; just hang briefly so the boot check fails cleanly (not our
# focus — this fixture is for the version-floor warning).
sleep 100000 &
wait
