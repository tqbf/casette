#!/bin/bash
# Pretends to be sage. For --version it answers; for `-python worker.py` it
# hangs forever without ever emitting a ready banner (boot-hang case).
if [ "$1" = "--version" ]; then
  echo "SageMath version 9.5, Release Date: 2022-01-30"
  exit 0
fi
# Spawn a child that hangs, mirroring sage's bash-wrapper -> worker structure,
# so we also prove the process-GROUP kill reaps the orphaned child.
sleep 100000 &
wait
