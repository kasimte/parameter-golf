#!/bin/bash
# Pull training results from a RunPod instance after a run completes.
#
# Usage:
#   ./scripts/pull_from_pod.sh <HOST> <PORT> [RUN_ID]
#
# Example:
#   ./scripts/pull_from_pod.sh 123.45.67.89 22222
#   ./scripts/pull_from_pod.sh 123.45.67.89 22222 my_run_id
#
# What it pulls:
#   - All .log files from the working directory
#   - The exported model artifact (final_model.int6.ptz)
#   - train_gpt.py (the exact script that ran)
#   - Any .json files (submission metadata)
#   - The full terminal output if saved
#
# Files are saved to: ./pod_results/<RUN_ID or timestamp>/

set -euo pipefail

HOST="${1:?Usage: $0 <HOST> <PORT> [RUN_ID]}"
PORT="${2:?Usage: $0 <HOST> <PORT> [RUN_ID]}"
RUN_ID="${3:-$(date +%Y%m%d_%H%M%S)}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
REMOTE_DIR="${REMOTE_DIR:-/workspace/parameter-golf}"

LOCAL_DIR="./pod_results/${RUN_ID}"
mkdir -p "$LOCAL_DIR"

echo "=== Pulling results from $HOST:$PORT ==="
echo "Remote dir: $REMOTE_DIR"
echo "Local dir:  $LOCAL_DIR"
echo ""

SSH="ssh -o StrictHostKeyChecking=no -i $SSH_KEY root@$HOST -p $PORT"
SCP="scp -o StrictHostKeyChecking=no -i $SSH_KEY -P $PORT"

# 1. List what's available
echo "--- Remote files ---"
$SSH "ls -lh '${REMOTE_DIR}'/*.log '${REMOTE_DIR}'/*.ptz '${REMOTE_DIR}'/*.json 2>/dev/null || echo '(none in root)'"
$SSH "ls -lh '${REMOTE_DIR}'/logs/ 2>/dev/null || echo '(no logs/ dir)'"
echo ""

# 2. Pull training logs (all .log files)
echo "--- Pulling logs ---"
$SCP "root@$HOST:$REMOTE_DIR/*.log" "$LOCAL_DIR/" 2>/dev/null && echo "  Got .log files" || echo "  No .log files in root"
$SCP -r "root@$HOST:$REMOTE_DIR/logs/" "$LOCAL_DIR/logs/" 2>/dev/null && echo "  Got logs/ dir" || echo "  No logs/ dir"

# 3. Pull model artifact
echo "--- Pulling model artifact ---"
$SCP "root@$HOST:$REMOTE_DIR/final_model.int6.ptz" "$LOCAL_DIR/" 2>/dev/null && echo "  Got final_model.int6.ptz" || echo "  No final_model.int6.ptz"

# 4. Pull the training script (exact version that ran)
echo "--- Pulling train_gpt.py ---"
$SCP "root@$HOST:$REMOTE_DIR/train_gpt.py" "$LOCAL_DIR/" 2>/dev/null && echo "  Got train_gpt.py" || echo "  No train_gpt.py in root"

# 5. Pull any JSON metadata
echo "--- Pulling JSON files ---"
$SCP "root@$HOST:$REMOTE_DIR/*.json" "$LOCAL_DIR/" 2>/dev/null && echo "  Got .json files" || echo "  No .json files"

# 6. Capture the last N lines of terminal output (nohup.out or screen log)
echo "--- Pulling terminal output ---"
$SSH "tail -500 '${REMOTE_DIR}'/nohup.out 2>/dev/null || tail -500 /root/nohup.out 2>/dev/null" > "$LOCAL_DIR/terminal_tail.txt" 2>/dev/null && echo "  Got terminal tail" || echo "  No nohup.out found"

# 7. Capture GPU info for the record
echo "--- Capturing GPU info ---"
$SSH "nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1" > "$LOCAL_DIR/gpu_info.txt" 2>/dev/null && echo "  Got GPU info" || echo "  No nvidia-smi"

echo ""
echo "=== Done ==="
echo "Results in: $LOCAL_DIR"
ls -lh "$LOCAL_DIR/"
