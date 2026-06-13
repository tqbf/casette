# Statistics + Preload Implementation

Status: PASS

Implemented the first two [plans/STAT.md](../plans/STAT.md) batches and the
linked [plans/PRELOAD.md](../plans/PRELOAD.md) worker-preload gate.

Changes:

- `worker.py` installs normal, binomial, Poisson, exponential, and uniform
  helper functions before `_SYMBOL_BASELINE`, plus conservative `TAU`/`PHI`
  constants, so untouched helpers stay hidden from Symbols.
- Friendly compiler Batch G adds 22 distribution commands that lower to those
  helper calls with readable generated Sage.
- A new `StatsFormulaIR` and `StatsFormulaBar` provide compact formula bars
  for the stats commands while preserving partial edits.
- Completion docs, worker-protocol docs, and the STAT/PRELOAD plans now reflect
  the implemented behavior.

Validation: `swift test` 630/630, `make check`, `make build`, and
`v0/03-result-envelope/harness.py --sage /usr/local/bin/sage` 97/97.
