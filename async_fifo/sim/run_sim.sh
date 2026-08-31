#!/usr/bin/env bash
# run_sim.sh -- compile and run the async_fifo testbench with Icarus Verilog.
#
# Usage:
#   ./run_sim.sh                        # default DEPTH=16, DATA_WIDTH=8, random seed=1
#   ./run_sim.sh SEED                   # override random seed
#   ./run_sim.sh SEED DEPTH DATA_WIDTH  # full depth/width/seed sweep point
#
# Requires the `iverilog`/`vvp` module (this repo assumes the `iverilog/14.0` environment module;
# adjust the `module load` line below if your environment provides it differently, or just make
# sure `iverilog`/`vvp` are on PATH).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(dirname "$SCRIPT_DIR")"
RTL_DIR="$PROJ_DIR/rtl"
TB_DIR="$PROJ_DIR/tb"
WORK_DIR="$SCRIPT_DIR/work"

SEED="${1:-1}"
DEPTH="${2:-16}"
DATA_WIDTH="${3:-8}"

if command -v module >/dev/null 2>&1; then
  source /etc/profile.d/modules.sh 2>/dev/null || true
  module load iverilog/14.0 2>/dev/null || true
fi

if ! command -v iverilog >/dev/null 2>&1; then
  echo "ERROR: iverilog not found on PATH (and module load did not provide it)." >&2
  exit 1
fi

mkdir -p "$WORK_DIR"
OUT="$WORK_DIR/tb_async_fifo_seed${SEED}_d${DEPTH}_w${DATA_WIDTH}.out"

echo "=== Compiling (DEPTH=$DEPTH DATA_WIDTH=$DATA_WIDTH) ==="
iverilog -g2012 -Wall \
  -o "$OUT" \
  -P"tb_async_fifo.DEPTH=$DEPTH" \
  -P"tb_async_fifo.DATA_WIDTH=$DATA_WIDTH" \
  "$RTL_DIR/rst_sync.sv" \
  "$RTL_DIR/sync_r2r.sv" \
  "$RTL_DIR/fifo_mem.sv" \
  "$RTL_DIR/wptr_full.sv" \
  "$RTL_DIR/rptr_empty.sv" \
  "$RTL_DIR/fifo_sva_checker.sv" \
  "$RTL_DIR/async_fifo.sv" \
  "$TB_DIR/tb_async_fifo.sv"

echo "=== Running (seed=$SEED) ==="
vvp "$OUT" +seed="$SEED"
