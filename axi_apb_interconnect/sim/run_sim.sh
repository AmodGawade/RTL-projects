#!/usr/bin/env bash
# run_sim.sh -- compile and run the AXI4-Lite/APB interconnect testbench with Icarus Verilog.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(dirname "$SCRIPT_DIR")"
RTL_DIR="$PROJ_DIR/rtl"
TB_DIR="$PROJ_DIR/tb"
WORK_DIR="$SCRIPT_DIR/work"

SEED="${1:-1}"

if command -v module >/dev/null 2>&1; then
  source /etc/profile.d/modules.sh 2>/dev/null || true
  module load iverilog/14.0 2>/dev/null || true
fi

if ! command -v iverilog >/dev/null 2>&1; then
  echo "ERROR: iverilog not found on PATH (and module load did not provide it)." >&2
  exit 1
fi

mkdir -p "$WORK_DIR"
OUT="$WORK_DIR/tb_axi_lite_apb_seed${SEED}.out"

echo "=== Compiling ==="
iverilog -g2012 -Wall \
  -o "$OUT" \
  "$RTL_DIR/axi_lite_pkg.sv" \
  "$RTL_DIR/axi_lite_regfile.sv" \
  "$RTL_DIR/apb_regbank.sv" \
  "$RTL_DIR/axi_lite_to_apb_bridge.sv" \
  "$RTL_DIR/axi_lite_interconnect.sv" \
  "$TB_DIR/tb_axi_lite_apb_interconnect.sv"

echo "=== Running (seed=$SEED) ==="
vvp "$OUT" +seed="$SEED"
