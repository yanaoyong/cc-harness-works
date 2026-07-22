#!/usr/bin/env bash
# PreToolUse guard: first creation of .harness/changes/<card> requires an exact pending CCA.
# The Python parser treats payload/command text only as data (SEC-1: no eval/bash -c).
set -uo pipefail

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0
command -v python3 >/dev/null 2>&1 || {
  printf '%s\n' '[harness:card_creation_guard] blocked: Python unavailable; cannot safely classify a possible card creation.' >&2
  exit 2
}

CCA_PAYLOAD="$payload" python3 - <<'PY'
import fcntl, json, os, re, shlex, subprocess, sys, time
from pathlib import Path

payload = json.loads(os.environ.get("CCA_PAYLOAD", "{}"))
tool = str(payload.get("tool_name") or payload.get("tool") or "")
tool_input = payload.get("tool_input") or {}
if not isinstance(tool_input, dict):
    tool_input = {}
sid = re.sub(r"[^A-Za-z0-9._-]", "", str(payload.get("session_id") or "nosid")) or "nosid"
prompt_id = re.sub(r"[^A-Za-z0-9._-]", "", str(payload.get("prompt_id") or ""))
root_arg = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()

CARD_RE = re.compile(r"^[a-z][a-z0-9]*(?:-[a-z0-9]+)+-[0-9]{8}$")
CREATE_CMDS = {"mkdir", "cp", "install", "mv", "rsync", "tar", "unzip", "git"}
FILE_TOOLS = {"Write", "Edit", "NotebookEdit", "write_file", "create_directory", "move_file",
              "mcp__filesystem__write_file", "mcp__filesystem__create_directory", "mcp__filesystem__move_file"}

def deny(msg):
    print(f"[harness:card_creation_guard] blocked: {msg}", file=sys.stderr)
    raise SystemExit(2)

def git(*args):
    return subprocess.check_output(["git", "-C", root_arg, *args], text=True, stderr=subprocess.DEVNULL).strip()

def normalize_remote(url):
    url = url.strip()
    m = re.match(r"git@([^:]+):(.+)$", url)
    if m:
        url = "ssh://git@" + m.group(1) + "/" + m.group(2)
    url = re.sub(r"^[a-z]+://(?:[^/@]+@)?", "", url, flags=re.I)
    url = url.split("?", 1)[0].split("#", 1)[0].rstrip("/")
    return re.sub(r"\.git$", "", url, flags=re.I).lower()

try:
    root = str(Path(git("rev-parse", "--show-toplevel")).resolve(strict=False))
    common = str((Path(root_arg) / git("rev-parse", "--git-common-dir")).resolve(strict=False))
    gitdir = str((Path(root_arg) / git("rev-parse", "--git-dir")).resolve(strict=False))
except Exception:
    root = ""
changes_hint = ".harness/changes"

def has_changes_signal(value):
    return changes_hint in value or re.search(r"(?:^|[/\"'\\s])changes(?:[/\"'\\s]|$)", value) is not None

# Return creation destinations, never source operands. If changes-domain creation semantics cannot
# be proved from the argv shape, caller fails closed. Dynamic shell syntax is never evaluated.
def bash_candidates(command):
    command_signal = has_changes_signal(command)
    if not command_signal:
        return False, [], False
    if re.search(r"\$\(|`|\$\{|(?<!\\)[*?\[]|(?<!\\)[{}]", command):
        return True, [], True
    try:
        tokens = shlex.split(command, posix=True)
    except ValueError:
        return True, [], True
    if any(tok in (";", "&&", "||", "|") for tok in tokens):
        return True, [], True
    cmd_indexes = [i for i, tok in enumerate(tokens) if os.path.basename(tok) in CREATE_CMDS]
    if len(cmd_indexes) != 1:
        return True, [], True
    i = cmd_indexes[0]
    cmd = os.path.basename(tokens[i])
    rest = tokens[i + 1:]
    positional = []
    option_values = {}
    ambiguous_options = False
    end_options = False
    no_arg_options = {
        "mkdir": {"-p", "--parents", "-v", "--verbose"},
        "cp": {"-a", "--archive", "-f", "--force", "-i", "--interactive", "-n", "--no-clobber",
               "-p", "--preserve", "-r", "-R", "--recursive", "-v", "--verbose"},
        "mv": {"-f", "--force", "-i", "--interactive", "-n", "--no-clobber", "-v", "--verbose"},
        "rsync": {"-a", "--archive", "-r", "--recursive", "-v", "--verbose", "-q", "--quiet",
                  "-z", "--compress", "--delete", "--dry-run", "-n"},
        "install": {"-d", "--directory", "-D", "--compare", "-p", "--preserve-timestamps",
                    "-v", "--verbose"},
    }
    arg_options = {
        "cp": {"-t", "--target-directory", "-S", "--suffix"},
        "mv": {"-t", "--target-directory", "-S", "--suffix"},
        "rsync": {"--exclude", "--include", "--filter", "--files-from", "--rsync-path"},
        "install": {"-t", "--target-directory", "-m", "--mode", "-o", "--owner", "-g", "--group",
                    "-S", "--suffix"},
        "tar": {"-C", "--directory"},
        "unzip": {"-d"},
    }
    n = 0
    while n < len(rest):
        tok = rest[n]
        if not end_options and tok == "--":
            end_options = True
            n += 1
            continue
        if not end_options and tok.startswith("-") and tok != "-":
            name = tok.split("=", 1)[0]
            if "=" in tok and name in arg_options.get(cmd, set()):
                option_values[name] = tok.split("=", 1)[1]
            elif name in arg_options.get(cmd, set()):
                if n + 1 >= len(rest):
                    return True, [], True
                option_values[name] = rest[n + 1]
                n += 1
            elif name not in no_arg_options.get(cmd, set()):
                ambiguous_options = True
            n += 1
            continue
        positional.append(tok)
        n += 1

    target_directory = option_values.get("-t") or option_values.get("--target-directory")
    paths = []
    if cmd == "mkdir":
        paths = positional
    elif cmd == "install" and any(x in rest for x in ("-d", "--directory")):
        paths = positional
    elif cmd in ("cp", "mv", "install", "rsync"):
        if target_directory:
            paths = [target_directory]
        elif len(positional) >= 2:
            paths = [positional[-1]]
    elif cmd == "tar":
        paths = [option_values.get("-C") or option_values.get("--directory")]
    elif cmd == "unzip":
        paths = [option_values.get("-d")]
    elif cmd == "git":
        if not rest or rest[0] not in ("clone", "worktree"):
            return True, [], True
        paths = [positional[-1]] if positional else []
    paths = [p for p in paths if p]
    target_signal = any(has_changes_signal(p) for p in paths)
    if not target_signal and not ambiguous_options:
        return False, [], False
    return True, paths, ambiguous_options or not bool(paths)

def file_candidates():
    keys = ("file_path", "path", "notebook_path", "destination")
    vals = [tool_input.get(k) for k in keys if isinstance(tool_input.get(k), str)]
    signal = any(changes_hint in v or re.search(r"(?:^|/)changes(?:/|$)", v) for v in vals)
    return signal, vals, signal and not vals

if tool in ("Bash", "bash"):
    command = tool_input.get("command")
    if not isinstance(command, str):
        raise SystemExit(0)
    signal, candidates, ambiguous = bash_candidates(command)
elif tool in FILE_TOOLS or any(tool.endswith(x) for x in ("write_file", "create_directory", "move_file")):
    signal, candidates, ambiguous = file_candidates()
else:
    # Unknown registered tools with no changes signal are outside the guard domain.
    serialized = json.dumps(tool_input, ensure_ascii=False)
    signal = changes_hint in serialized
    if not signal:
        raise SystemExit(0)
    candidates, ambiguous = [], True
if not signal:
    raise SystemExit(0)
if not root:
    deny("cannot resolve the current project root for a changes-domain creation")
if ambiguous:
    deny("changes-domain target is dynamic, compound, or otherwise not uniquely decidable")

changes = str(Path(root, ".harness", "changes").resolve(strict=False))
project_id = None
try:
    remotes = git("remote").splitlines()
    if "origin" in remotes:
        remote = normalize_remote(git("remote", "get-url", "origin"))
    else:
        vals = sorted(set(normalize_remote(git("remote", "get-url", r)) for r in remotes))
        if len(vals) != 1:
            raise ValueError
        remote = vals[0]
    if not remote:
        raise ValueError
    project_id = f"root={root}|common={common}|remote={remote}"
except Exception:
    deny("canonical project remote identity is unavailable or ambiguous")

def classify(raw, allow_descendant=False):
    if not raw or any(ord(c) < 32 or c.isspace() for c in raw) or ".." in raw:
        deny("invalid/empty changes-domain target")
    if any(c in raw for c in "*$?[]{}\n\r\t"):
        deny("dynamic/glob target in changes domain")
    if raw.startswith("-"):
        deny("leading-option target in changes domain")
    path = raw if os.path.isabs(raw) else os.path.join(root, raw)
    lexical = os.path.abspath(path)
    changes_abs = os.path.abspath(os.path.join(root, ".harness", "changes"))
    try:
        rel = os.path.relpath(lexical, changes_abs)
    except ValueError:
        return None
    if rel == os.pardir or rel.startswith(os.pardir + os.sep):
        return None
    parts = rel.split(os.sep)
    if not parts or parts[0] in ("", "."):
        deny("empty card target")
    if len(parts) > 1 and not allow_descendant:
        deny("target is not exactly .harness/changes/<basename>")
    card = parts[0]
    card_path = os.path.join(changes_abs, card)
    if card == "_TEMPLATE" or not CARD_RE.fullmatch(card):
        deny("card basename is not canonical")
    # Existing cards are allowed only when the card itself is a normal directory and neither it nor
    # the changes parent resolves through a symlink. Descendant file writes then need no CCA.
    if os.path.islink(card_path):
        deny("card target is a symlink")
    if os.path.lexists(card_path):
        if not os.path.isdir(card_path) or str(Path(card_path).parent.resolve(strict=False)) != changes:
            deny("existing card target is not a normal in-project directory")
        return ("existing", card, card_path)
    if str(Path(card_path).parent.resolve(strict=False)) != changes:
        deny("changes parent resolves through a symlink or outside current project")
    return ("new", card, card_path)

allow_descendant = True
classified = [x for x in (classify(v, allow_descendant) for v in candidates) if x]
# Deduplicate repeated operands, but mixed existing+new and multiple cards remain forbidden.
unique = {(kind, card, path) for kind, card, path in classified}
if not unique:
    deny("changes-domain creation was detected but no exact card target was provable")
if len(unique) != 1:
    deny("one tool call may address only one card; mixed/multiple card targets are forbidden")
kind, card, target = next(iter(unique))
if kind == "existing":
    raise SystemExit(0)

state_root = os.environ.get("HARNESS_STATE_DIR") or os.path.join(root, ".harness", "state")
ledger = os.path.join(state_root, "card_create_authorizations.jsonl")
lock_path = os.path.join(state_root, "card_create_authorizations.lock")
if not os.path.isdir(state_root) or not os.path.isfile(ledger):
    deny("card-create authorization ledger is missing")
card_id = f"{project_id}::{card}"
with open(lock_path, "a+", encoding="utf-8") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    records = []
    try:
        with open(ledger, encoding="utf-8", errors="strict") as fh:
            for line in fh:
                if line.strip():
                    records.append(json.loads(line))
    except Exception:
        deny("card-create authorization state is unreadable")
    consumed = {r.get("authorization_id") for r in records if r.get("type") == "consumed"}
    pending = [r for r in records if r.get("type") == "pending"
               and r.get("gate") == "card-create"
               and r.get("session_id") == sid
               and r.get("canonical_project_id") == project_id
               and r.get("worktree_id") == gitdir
               and r.get("canonical_card_id") == card_id
               and r.get("authorization_id") not in consumed]
    if not pending:
        deny("no unconsumed CCA matches this project/card/worktree/session")
    auth = max(pending, key=lambda r: int(r.get("created_ns") or 0))
    consumed_record = {
        "type": "consumed", "gate": "card-create", "consumed_ns": time.time_ns(),
        "authorization_id": auth.get("authorization_id"), "session_id": sid,
        "canonical_project_id": project_id, "worktree_id": gitdir,
        "canonical_card_id": card_id, "card": card, "prompt_id": prompt_id,
    }
    try:
        with open(ledger, "a", encoding="utf-8") as out:
            out.write(json.dumps(consumed_record, ensure_ascii=False, separators=(",", ":")) + "\n")
            out.flush()
            os.fsync(out.fileno())
    except Exception:
        deny("could not durably consume CCA")
# No rollback exists: once this append+fsync succeeds, tool outcome cannot return authorization.
raise SystemExit(0)
PY
rc=$?
exit "$rc"
