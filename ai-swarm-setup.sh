#!/bin/bash
# ai-swarm-setup.sh: Automate Zellij swarm with OpenCode headless, optimized Taskmaster, Grok integration

set -e # Exit on error

PROJECT_ROOT="$(pwd)"
SUBS=("sub-research" "sub-code-review") # Add more as needed
PRD_FILE="prd.txt"
TASKS_FILE=".taskmaster/tasks.json"

# Env vars for speed
export TASKMASTER_FAST_MODE=1 # Skip logs/re-renders
export ZELLIJ_AUTO_EXIT=false # Keep panes alive

# Step 1: Init worktrees & shared files
echo "Initializing worktrees..."
for sub in "${SUBS[@]}"; do
  git worktree add "../$sub" main || true                 # Ignore if exists
  (cd "../$sub" && git checkout -b "$sub-branch" || true) # Isolated branch
done

# Copy shared config
for dir in "$PROJECT_ROOT" "${SUBS[@]/#/${PROJECT_ROOT}/../}"; do
  (cd "$dir" && mkdir -p .claude/agents .claude/commands .taskmaster .githooks)
  cp -r .env .claude/settings.json "$dir" 2>/dev/null || true
done

# Step 2: Optimize Taskmaster (persistent storage + hook)
echo "Optimizing Taskmaster..."
cat >.githooks/pre-commit <<'EOF'
#!/bin/bash
if [[ $TASKMASTER_FAST_MODE ]]; then
  jq '.updated = now' .taskmaster/tasks.json > tmp.json && mv tmp.json .taskmaster/tasks.json
  git add .taskmaster/tasks.json
fi
EOF
chmod +x .githooks/pre-commit
# Copy to subs
for sub in "${SUBS[@]}"; do cp -r .githooks "../$sub/"; done

# Fast sync function
sync_tasks() {
  for sub in "${SUBS[@]}"; do
    (cd "../$sub" && git pull origin main && jq --slurpfile main "$PROJECT_ROOT/$TASKS_FILE" '. += $main[0] | unique_by(.id)' "$TASKS_FILE" >tmp && mv tmp "$TASKS_FILE")
  done
  echo "Tasks synced (delta-only via jq)."
}

# Step 3: Start OpenCode headless server
echo "Launching OpenCode headless (port 4096)..."
opencode serve --port 4096 --hostname 0.0.0.0 & # Background; accessible remotely
OPEN_CODE_PID=$!
sleep 2                                                                                         # Wait for startup
curl -X POST http://localhost:4096/session -d '{"name": "main-orchestrator", "parentID": null}' # Init main session
echo $OPEN_CODE_PID >opencode.pid                                                               # For cleanup

# Step 4: Init Taskmaster with Grok for fast parse
echo "Parsing PRD with Grok Code Fast 1..."
# Use curl for Grok API (via OpenRouter proxy for ease)
curl -s -X POST https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $XAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "x-ai/grok-code-fast-1",
    "messages": [{"role": "user", "content": "Parse this PRD into tasks.json: $(cat $PRD_FILE). Output valid JSON array with id, status, deps."}],
    "max_tokens": 1024
  }' | jq -r '.choices[0].message.content' >tmp-tasks.json

# Merge/validate with Taskmaster init (fast mode)
task-master init --from-json tmp-tasks.json --fast || true
rm tmp-tasks.json
sync_tasks

# Step 5: Zellij layout for swarm (KDL format)
cat >zellij-layout.kdl <<EOF
layout {
    tab name="Main-Orchestrator" {
        pane command="claude" args=["--mcp", "taskmaster-ai,zen"] cwd="$PROJECT_ROOT" {
            name "Main Claude + OpenCode API"
        }
        pane command="watch -n 10 './sync-tasks.sh'" cwd="$PROJECT_ROOT" {
            name "Task Sync Poller"
        }
    }
    $(for sub in "${SUBS[@]}"; do
  echo "tab name=\"$sub\" {"
  echo "    pane command=\"cd ../$sub && claude --agents '{\"$sub-agent\": {\"prompt\": \"Delegate via OpenCode API: curl POST /session/main-orchestrator/message {\\\"text\\\": \\\"Task $id to $sub\\\"}'}}'\" cwd=\"../$sub\" {"
  echo "        name \"$sub Claude Session\""
  echo "    }"
  echo "    pane command=\"tail -f ../$sub/.taskmaster/tasks.json | jq .\" {"
  echo "        name \"$sub Task Monitor\""
  echo "    }"
  echo "}"
done)
}
EOF

# Step 6: Launch Zellij session
echo "Starting Zellij swarm session 'ai-swarm'..."
zellij --layout zellij-layout.kdl a --session ai-swarm

# Cleanup on exit (trap)
trap "kill $OPEN_CODE_PID 2>/dev/null; rm opencode.pid zellij-layout.kdl; sync_tasks" EXIT
