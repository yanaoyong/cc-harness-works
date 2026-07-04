#!/usr/bin/env bash
# =============================================================================
# acceptance-capture.sh — transcript 证据捕获器（含链式分段切片）
# 组件：acceptance-backfill（plugins/harness-core/components/acceptance-backfill）
#
# 用法：
#   acceptance-capture.sh <套件根> <CASE-ID> [--session <jsonl路径>] [--chain <链ID>]
#                         [--no-thinking] [--dry-run]
#
#   <套件根>  ：验收套件目录（相对仓库根或绝对路径均可），如 .harness/acceptance/fullstack-plugin
#   <CASE-ID> ：案例 ID（cases/<CASE-ID>*.md 须在场）
#   --session ：显式指定被测会话 JSONL，跳过 R3.1 自动定位
#   --chain   ：链式切片模式，读 <套件根>/chains.md 与进度文件（R3.6）
#   --no-thinking：渲染时完全去除 thinking（默认渲染为 "[thinking ×N 已省略]" 行）
#   --dry-run ：只做定位/解析/切片校验，不落任何文件
#
# 退出码（组件统一枚举）：
#   0 成功 · 1 断言性失败 · 2 参数错误 · 3 会话定位失败 · 4 transcript 格式不识别 · 5 内部错误
#
# 输出契约：stdout 仅一行 JSON 摘要（case/session/输出路径/备份路径等）；诊断信息一律 stderr。
#
# 硬红线：本脚本绝不写套件 cases/ 目录；产出仅落 results/<CASE-ID>-result.md 与 results/.evidence/**。
#
# R3.6 "跑过头" 实现注记（实现取简单确定者）：
#   本实现为「逐个调用各切各段」——每次调用只切本 CASE-ID 的 [进入锚, 下一成员锚) 区间；
#   会话无论推进多远（越过多少成员锚）均不影响本成员切片的确定性；
#   "链末一次性切片" = 对链内每个成员各调一次本脚本（链首定位后 UUID 已钉进度文件，后续成员零重匹配）。
#   下一成员锚未命中（会话尚未推进到下一成员）→ 切片至文件末并 stderr 注明，不报错。
#
# 依赖：python3（JSON 解析）；无 python3 → exit 5 并明确提示，不静默。
# 兼容：macOS bash 3.2（bash 层零数组/零 4.x 语法，重逻辑全部在内嵌 python3）。
# =============================================================================
set -u

if ! command -v python3 >/dev/null 2>&1; then
  echo "[capture] 错误：未找到 python3（本脚本依赖 python3 做 JSONL 解析）。请安装 python3 后重试。" >&2
  exit 5
fi

# 仓库根推导（零硬编码）：仅当套件根为相对路径时必需；不在 git 仓库内时传空并由 python 侧判定。
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
OS_INFO="$(uname -s 2>/dev/null || echo unknown) $(uname -r 2>/dev/null || true)"

# ${1+"$@"}：bash 3.2 + set -u 下空参安全展开
exec python3 - "$REPO_ROOT" "$OS_INFO" ${1+"$@"} <<'PYEOF'
# -*- coding: utf-8 -*-
"""acceptance-capture.sh 内嵌实现（经 stdin 注入 python3 -）。"""
import sys, os, re, json, glob, shutil, time

E_OK, E_ASSERT, E_ARGS, E_LOCATE, E_FORMAT, E_INTERNAL = 0, 1, 2, 3, 4, 5

USAGE = ("用法: acceptance-capture.sh <套件根> <CASE-ID> "
         "[--session <jsonl路径>] [--chain <链ID>] [--no-thinking] [--dry-run]")


def err(msg):
    sys.stderr.write('[capture] %s\n' % msg)


def die(code, msg=None):
    if msg:
        err(msg)
    sys.exit(code)


def norm_ws(s):
    """归一化空白：连续空白折叠为单空格 + 去首尾。锚匹配/prompt 匹配统一走这里。"""
    return re.sub(r'\s+', ' ', s or '').strip()


def escape_proj_dir(path):
    """Claude Code 项目目录转义（实测规则）：绝对路径中 '/' 与 '.' 均映射为 '-'。"""
    return re.sub(r'[/.]', '-', path)


def now_stamp():
    return time.strftime('%Y%m%d-%H%M%S')


def read_text(path):
    with open(path, 'r', encoding='utf-8', errors='replace') as fh:
        return fh.read()


# ---------------------------------------------------------------- 参数解析
def parse_args(argv):
    # argv: [repo_root, os_info, <套件根>, <CASE-ID>, options...]
    if len(argv) < 2:
        die(E_INTERNAL, '内部错误：包装层参数缺失')
    opts = {
        'repo_root': argv[0], 'os_info': argv[1].strip(),
        'suite': None, 'case': None,
        'session': None, 'chain': None,
        'no_thinking': False, 'dry_run': False,
    }
    rest = argv[2:]
    pos = []
    i = 0
    while i < len(rest):
        a = rest[i]
        if a == '--session':
            if i + 1 >= len(rest):
                die(E_ARGS, '--session 缺少参数值\n' + USAGE)
            opts['session'] = rest[i + 1]; i += 2
        elif a == '--chain':
            if i + 1 >= len(rest):
                die(E_ARGS, '--chain 缺少参数值\n' + USAGE)
            opts['chain'] = rest[i + 1]; i += 2
        elif a == '--no-thinking':
            opts['no_thinking'] = True; i += 1
        elif a == '--dry-run':
            opts['dry_run'] = True; i += 1
        elif a.startswith('-'):
            die(E_ARGS, '未知选项：%s\n%s' % (a, USAGE))
        else:
            pos.append(a); i += 1
    if len(pos) != 2:
        die(E_ARGS, '位置参数须恰为 <套件根> <CASE-ID>（收到 %d 个）\n%s' % (len(pos), USAGE))
    opts['suite'], opts['case'] = pos[0], pos[1]

    # 套件根解析：绝对路径直接用；相对路径挂仓库根
    suite = opts['suite']
    if not os.path.isabs(suite):
        if not opts['repo_root']:
            die(E_ARGS, '套件根为相对路径但当前不在 git 仓库内（仓库根不可得）；请传绝对路径')
        suite = os.path.join(opts['repo_root'], suite)
    suite = os.path.normpath(suite)
    if not os.path.isdir(suite):
        die(E_ARGS, '套件根目录不存在：%s' % suite)
    opts['suite'] = suite

    if opts['session']:
        s = os.path.abspath(opts['session'])
        if not os.path.isfile(s):
            die(E_ARGS, '--session 指定的 JSONL 不存在：%s' % s)
        opts['session'] = s
    return opts


# ---------------------------------------------------------------- case 文件解析
def find_case_file(suite, case_id):
    cases_dir = os.path.join(suite, 'cases')
    exact = os.path.join(cases_dir, case_id + '.md')
    if os.path.isfile(exact):
        return exact
    hits = sorted(glob.glob(os.path.join(cases_dir, case_id + '*.md')))
    if not hits:
        die(E_ARGS, '案例文件未找到：%s/cases/%s*.md' % (suite, case_id))
    if len(hits) > 1:
        err('案例文件多命中，取字典序首个：%s' % hits[0])
    return hits[0]


def head_kind(line):
    """三段式标题归一化识别（容差规则同源引用 rule §1 / 阶段2评审 M-3）：
    去空白与全/半角中点差异后按 运行前|运行中|运行后 前缀识别。"""
    s = line.strip()
    if not s or not (s.startswith('#') or s.startswith('【')):
        return None
    core = s.lstrip('#').strip().lstrip('【').strip()
    core = re.sub(u'[\\s·・]', '', core)
    if core.startswith(u'运行前'):
        return 'pre'
    if core.startswith(u'运行中'):
        return 'mid'
    if core.startswith(u'运行后'):
        return 'post'
    return 'other'


def extract_pre_cd(case_text):
    """R3.1：从案例【运行前】节的 bash 块提取首个 cd 目标。
    返回 (target, resolvable)：无 cd → (None, True)；cd 目标含变量 → (原文, False)。"""
    lines = case_text.splitlines()
    n = len(lines)
    start = None
    for i in range(n):
        if head_kind(lines[i]) == 'pre':
            start = i
            break
    if start is None:
        return None, True
    j = start + 1
    while j < n:
        k = head_kind(lines[j])
        if k in ('mid', 'post'):
            break
        if lines[j].strip().startswith('```bash'):
            j += 1
            while j < n and lines[j].strip() != '```':
                m = re.match(r'\s*cd\s+([^\s#]+)', lines[j])
                if m:
                    tgt = m.group(1).strip('"\'')
                    if '$' in tgt or '`' in tgt:
                        return tgt, False
                    return tgt, True
                j += 1
        j += 1
    return None, True


def extract_startup_prompt(case_text):
    """R3.1：案例"用户启动 prompt 原文"围栏块 → 归一化空白后取首 120 字符作匹配锚。"""
    lines = case_text.splitlines()
    n = len(lines)
    start = None
    for i in range(n):
        s = lines[i].strip()
        if s.startswith('#') and (u'启动' in s) and ('prompt' in s.lower()):
            start = i
            break
    if start is None:
        return None
    j = start + 1
    while j < n:
        if lines[j].strip().startswith('```'):
            body = []
            j += 1
            while j < n and not lines[j].strip().startswith('```'):
                body.append(lines[j])
                j += 1
            text = norm_ws('\n'.join(body))
            return text[:120] if text else None
        # 越过下一个同级标题仍没围栏 → 放弃
        if lines[j].strip().startswith('## '):
            return None
        j += 1
    return None


# ---------------------------------------------------------------- R3.1 会话定位
def iter_user_strings(path):
    """yield (norm_content, timestamp)：主链（非 sidechain）user 型字符串 content 记录。"""
    try:
        fh = open(path, 'r', encoding='utf-8', errors='replace')
    except (IOError, OSError):
        return
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if obj.get('type') != 'user' or obj.get('isSidechain'):
                continue
            c = (obj.get('message') or {}).get('content')
            if isinstance(c, str):
                yield norm_ws(c), obj.get('timestamp', '')


def locate_session(proj_dir, anchor, label):
    """按启动 prompt 锚（归一化前缀）在项目转义目录内匹配会话 JSONL。
    唯一命中 → 路径；多命中/零命中 → exit 3 + stderr 差异提示。"""
    if not os.path.isdir(proj_dir):
        die(E_LOCATE, '会话项目目录不存在：%s\n'
                      '（%s 的工作目录转义后无会话记录；确认被测会话确在该 cwd 启动，或用 --session 手工指定）'
                      % (proj_dir, label))
    files = sorted(glob.glob(os.path.join(proj_dir, '*.jsonl')),
                   key=lambda f: os.path.getmtime(f), reverse=True)
    if not files:
        die(E_LOCATE, '目录内无 JSONL 会话文件：%s（可用 --session 手工指定）' % proj_dir)
    prefix_hits, contain_hits = [], []
    firsts = {}  # path -> (首条 user prompt 摘要, 时间戳)
    for f in files:
        ph = ch = False
        for nc, ts in iter_user_strings(f):
            if f not in firsts:
                firsts[f] = (nc[:80], ts)
            if nc.startswith(anchor):
                ph = True
            elif anchor in nc:
                ch = True
        if ph:
            prefix_hits.append(f)
        elif ch:
            contain_hits.append(f)
    hits = prefix_hits
    if not hits and contain_hits:
        err('前缀匹配 0 命中；按包含匹配（宽松）命中 %d 个候选' % len(contain_hits))
        hits = contain_hits
    if len(hits) == 1:
        return hits[0]
    if len(hits) > 1:
        err('会话定位歧义（%s）：锚匹配命中 %d 个候选，请用 --session <jsonl路径> 手工指定其一：' % (label, len(hits)))
        for f in hits:
            fp, ts = firsts.get(f, ('<无 user 记录>', ''))
            mt = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(os.path.getmtime(f)))
            err('  候选: %s | mtime=%s | ts=%s | 首prompt: %s' % (f, mt, ts, fp))
        die(E_LOCATE)
    # 零命中：给最近 3 个会话首 prompt 摘要做差异提示
    err('会话定位失败（%s）：锚未在任何会话命中。匹配锚（归一化前 120 字符）：' % label)
    err('  锚: %s' % anchor)
    err('最近 %d 个会话的首条 user prompt 摘要（供差异排查；可用 --session 手工指定）：' % min(3, len(files)))
    for f in files[:3]:
        fp, ts = firsts.get(f, ('<无 user 记录>', ''))
        mt = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(os.path.getmtime(f)))
        err('  %s | mtime=%s | 首prompt: %s' % (f, mt, fp))
    die(E_LOCATE)


# ---------------------------------------------------------------- R3.5 防御性加载
KNOWN_TYPES = set(['user', 'assistant', 'system'])
BOOKKEEPING_TYPES = set(['last-prompt', 'file-history-snapshot', 'attachment',
                         'ai-title', 'summary', 'queue-operation'])


def load_records(path):
    """逐行解析 JSONL。返回 (records, total, bad, ok)。
    ok=False（解析失败或未知 type 行占比 >10%）→ 调用侧走 exit 4 降级：永不静默丢证据、不臆造。"""
    records, total, bad = [], 0, 0
    with open(path, 'r', encoding='utf-8', errors='replace') as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            total += 1
            try:
                obj = json.loads(line)
            except ValueError:
                bad += 1
                continue
            t = obj.get('type')
            if t in KNOWN_TYPES:
                records.append(obj)
            elif t in BOOKKEEPING_TYPES:
                continue  # 簿记型：渲染时跳过
            else:
                bad += 1
    ok = total > 0 and (bad * 100 <= total * 10)
    return records, total, bad, ok


# ---------------------------------------------------------------- R3.2 渲染（机械转录，禁止改写）
FENCE = '````'
TOOL_KEY_ORDER = ['command', 'description', 'file_path', 'path', 'pattern',
                  'skill', 'args', 'query', 'url', 'prompt']


def clip_lines(text, limit=80):
    ls = text.splitlines()
    if len(ls) <= limit:
        return text
    return '\n'.join(ls[:limit] + [u'…[截断 %d 行]' % (len(ls) - limit)])


def tool_result_text(blk):
    c = blk.get('content')
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        parts = []
        for p in c:
            if isinstance(p, dict) and p.get('type') == 'text':
                parts.append(p.get('text', ''))
            elif isinstance(p, dict):
                parts.append(json.dumps(p, ensure_ascii=False)[:500])
        return '\n'.join(parts)
    if c is None:
        return ''
    return json.dumps(c, ensure_ascii=False)[:2000]


def tool_use_summary(blk):
    inp = blk.get('input') or {}
    parts = []
    for k in TOOL_KEY_ORDER:
        if k in inp:
            v = inp[k]
            if not isinstance(v, str):
                v = json.dumps(v, ensure_ascii=False)
            if len(v) > 400:
                v = v[:400] + u'…[截断]'
            parts.append('%s: %s' % (k, v))
    if not parts:
        j = json.dumps(inp, ensure_ascii=False)
        parts.append(j[:400] + (u'…[截断]' if len(j) > 400 else ''))
    return '\n'.join(parts)


def render_records(records, no_thinking):
    """按轮次序机械转录为 markdown 摘录；每回合标时间戳。thinking 默认折叠为计数行。"""
    out = []
    side = 0
    for rec in records:
        if rec.get('isSidechain'):
            side += 1
            continue
        t = rec.get('type')
        ts = rec.get('timestamp', '')
        if t == 'user':
            c = (rec.get('message') or {}).get('content')
            if isinstance(c, str):
                out.append('### [%s] user\n\n%s\n' % (ts, c))
            elif isinstance(c, list):
                for blk in c:
                    if not isinstance(blk, dict):
                        continue
                    bt = blk.get('type')
                    if bt == 'tool_result':
                        out.append('### [%s] tool_result\n\n%s\n%s\n%s\n'
                                   % (ts, FENCE, clip_lines(tool_result_text(blk)), FENCE))
                    elif bt == 'text':
                        out.append('### [%s] user\n\n%s\n' % (ts, blk.get('text', '')))
        elif t == 'assistant':
            blocks = (rec.get('message') or {}).get('content')
            if isinstance(blocks, str):
                out.append('### [%s] assistant\n\n%s\n' % (ts, blocks))
                continue
            if not isinstance(blocks, list):
                continue
            tn = sum(1 for b in blocks if isinstance(b, dict) and b.get('type') == 'thinking')
            if tn and not no_thinking:
                out.append(u'[thinking ×%d 已省略]\n' % tn)
            for b in blocks:
                if not isinstance(b, dict):
                    continue
                bt = b.get('type')
                if bt == 'text':
                    out.append('### [%s] assistant\n\n%s\n' % (ts, b.get('text', '')))
                elif bt == 'tool_use':
                    out.append(u'### [%s] tool_use · %s\n\n%s\n%s\n%s\n'
                               % (ts, b.get('name', '?'), FENCE, tool_use_summary(b), FENCE))
        elif t == 'system':
            c = rec.get('content')
            if not isinstance(c, str):
                c = json.dumps(c, ensure_ascii=False)[:2000] if c is not None else \
                    json.dumps(dict((k, v) for k, v in rec.items() if k != 'type'),
                               ensure_ascii=False)[:1000]
            out.append('### [%s] system(hook)\n\n%s\n%s\n%s\n' % (ts, FENCE, clip_lines(c), FENCE))
    if side:
        out.append(u'[sidechain 记录 ×%d 已省略（子 Agent 旁链 · 全文见归档原件）]\n' % side)
    return '\n'.join(out)


# ---------------------------------------------------------------- R3.4 脱敏
RE_KV = re.compile(r'((?:[A-Za-z0-9_.\-]*(?:KEY|TOKEN|SECRET|PASSWORD)[A-Za-z0-9_.\-]*)'
                   r'\s*[=:]\s*["\']?)([A-Za-z0-9_\-]{16,})', re.IGNORECASE)
RE_BEARER = re.compile(r'(Authorization\s*:?\s*Bearer\s+)[^\s"\']+', re.IGNORECASE)


def redact(text):
    text = RE_KV.sub(lambda m: m.group(1) + '***REDACTED***', text)
    text = RE_BEARER.sub(lambda m: m.group(1) + '***REDACTED***', text)
    return text


# ---------------------------------------------------------------- R3.6 chains manifest / 进度文件
def parse_chains(suite, chain_id):
    """解析 <套件根>/chains.md 表行：| 链ID | 序号 | CASE-ID | 进入锚原文 |（支持 \\| 转义）。"""
    p = os.path.join(suite, 'chains.md')
    if not os.path.isfile(p):
        die(E_ARGS, '--chain 指定但 chains manifest 不存在：%s' % p)
    rows = []
    for line in read_text(p).splitlines():
        s = line.strip()
        if not s.startswith('|'):
            continue
        cells = [c.strip() for c in re.split(r'(?<!\\)\|', s)[1:-1]]
        if len(cells) < 4:
            continue
        c0 = cells[0]
        if not c0 or c0 in (u'链ID', 'chain_id') or re.match(r'^[-: ]+$', c0):
            continue
        rows.append({'chain': c0, 'seq': cells[1], 'case': cells[2],
                     'anchor': cells[3].replace('\\|', '|')})
    members = [r for r in rows if r['chain'] == chain_id]
    if not members:
        die(E_ARGS, 'chains.md 中未登记链：%s（%s）' % (chain_id, p))

    def seq_key(r):
        try:
            return (0, int(r['seq']))
        except ValueError:
            return (1, r['seq'])
    members.sort(key=seq_key)
    return members


def load_progress_lines(path):
    if os.path.isfile(path):
        return read_text(path).splitlines()
    return ['# acceptance-backfill 进度文件（行式 KEY=VALUE · acceptance-capture.sh / 主持剧本维护）']


def upsert_kv(lines, key, value):
    out, found = [], False
    for L in lines:
        if L.startswith(key + '='):
            out.append('%s=%s' % (key, value))
            found = True
        else:
            out.append(L)
    if not found:
        out.append('%s=%s' % (key, value))
    return out


def get_kv(lines, key):
    for L in lines:
        if L.startswith(key + '='):
            return L[len(key) + 1:].strip()
    return None


def find_anchor_idx(records, anchor, start=0):
    """归一化空白后前缀匹配：返回首个命中该进入锚的主链 user 记录下标；未命中 → -1。"""
    a = norm_ws(anchor)
    if not a:
        return -1
    for i in range(start, len(records)):
        rec = records[i]
        if rec.get('type') != 'user' or rec.get('isSidechain'):
            continue
        c = (rec.get('message') or {}).get('content')
        if isinstance(c, str) and norm_ws(c).startswith(a):
            return i
    return -1


# ---------------------------------------------------------------- R3.3 草稿骨架
def detect_suite_contract(suite):
    """读 results/README.md：含 case_id/status/evidence 三字段声明 → 'three-field'；否则 'three-section'。"""
    p = os.path.join(suite, 'results', 'README.md')
    if os.path.isfile(p):
        t = read_text(p)
        if 'case_id' in t and 'status' in t and 'evidence' in t:
            return 'three-field'
    err('套件契约未识别（results/README.md 缺失或无 case_id/status/evidence 三字段声明）→ 回退三段式通用骨架')
    return 'three-section'


def latest_log(ev_dir, prefix):
    hits = sorted(glob.glob(os.path.join(ev_dir, prefix + '-*.log')))
    return hits[-1] if hits else None


def log_section(ev_dir, prefix, chain_id):
    p = latest_log(ev_dir, prefix)
    if p:
        return u'留档文件：`%s`\n\n%s\n%s\n%s' % (p, FENCE, read_text(p).rstrip('\n'), FENCE)
    if chain_id:
        return (u'（无本案例级 %s 留档：链式案例 pre 由链首承担一次 / post 由链尾承担一次，'
                u'见主持剧本 R1.5 编排）' % prefix)
    return u'（无 %s 留档：.evidence/<CASE-ID>/%s-*.log 未找到；如需请先跑 acceptance-run.sh %s）' \
        % (prefix, prefix, prefix)


def extract_meta(records):
    """从主链 user 记录取会话元数据（执行时间/gitBranch/version/sessionId）。"""
    meta = {'timestamp': '', 'gitBranch': '', 'version': '', 'sessionId': '', 'cwd': ''}
    for rec in records:
        if rec.get('type') == 'user' and not rec.get('isSidechain'):
            for k in list(meta.keys()):
                if not meta[k] and rec.get(k):
                    meta[k] = str(rec.get(k))
            if all(meta.values()):
                break
    return meta


def build_draft(contract, case_id, meta, os_info, pre_sec, mid_sec, post_sec, session_note):
    if contract == 'three-field':
        return u'''# %s 执行结果

> 本文件为 acceptance-capture.sh 生成的回填草稿：证据为脚本机械转录，判定字段留空待用户。

## 1. case_id
%s

## 2. status
（待用户判定：PASS / FAIL / SKIP）

## 3. evidence

### 执行时间
%s

### 执行环境
- OS: %s
- Claude Code 版本: %s
- gitBranch: %s
- 被测会话: %s

### 【运行前】pre 执行留档
%s

### 【运行中】transcript 摘录（脚本机械转录 · 未改写）
%s

### 【运行后】post 执行留档
%s

### 预期结果验证
（待用户判定：逐条对照案例预期观察点勾认，每条附证据行号）

### 产出物确认
（待用户判定）

### 失败归因（仅 FAIL 时填写）
（待用户判定）

---
判定人=用户（待签）
''' % (case_id, case_id, meta['timestamp'] or u'（未知：以归档原件时间戳为准）',
            os_info or 'unknown', meta['version'] or u'（未知）', meta['gitBranch'] or u'（未知）',
            session_note, pre_sec, mid_sec, post_sec)
    # 三段式通用骨架（research-phase 型 / 契约识别不出时回退）
    return u'''# %s 回填草稿

> 本文件为 acceptance-capture.sh 生成的回填草稿：证据为脚本机械转录，判定字段留空待用户。

- 执行日期 / 执行人：%s / （执行人待填）
- 执行环境：OS %s · Claude Code %s · gitBranch %s
- 被测会话：%s
- 判定：（待用户判定：PASS / FAIL）
- 判定人=用户（待签）

## 【运行前 · 前置验证 / 造条件】

%s

## 【运行中需要进行的操作】

### transcript 摘录（脚本机械转录 · 未改写）

%s

## 【运行后 · 恢复 / 清理】

%s

## 偏差说明

（待用户判定：对照案例预期观察点逐条核对，每条附证据行号）
''' % (case_id, meta['timestamp'] or u'（未知）', os_info or 'unknown',
            meta['version'] or u'（未知）', meta['gitBranch'] or u'（未知）',
            session_note, pre_sec, mid_sec, post_sec)


# ---------------------------------------------------------------- 主流程
def main():
    o = parse_args(sys.argv[1:])
    suite, case_id = o['suite'], o['case']
    results_dir = os.path.join(suite, 'results')
    ev_root = os.path.join(results_dir, '.evidence')
    ev_dir = os.path.join(ev_root, case_id)
    progress_path = os.path.join(ev_root, '.backfill-progress')
    result_path = os.path.join(results_dir, '%s-result.md' % case_id)
    home = os.environ.get('HOME', '')

    members, member_idx = None, -1
    if o['chain']:
        members = parse_chains(suite, o['chain'])
        for i, m in enumerate(members):
            if m['case'] == case_id:
                member_idx = i
                break
        if member_idx < 0:
            die(E_ARGS, 'CASE-ID %s 不在链 %s 的成员序中（成员：%s）'
                % (case_id, o['chain'], ','.join(m['case'] for m in members)))

    # ---- 会话 JSONL 确定（R3.1 / R3.6 链首钉点）
    progress_lines = load_progress_lines(progress_path)
    pinned_key = 'chain_session_uuid.%s' % (o['chain'] or '')
    session_path = None
    pin_uuid = None

    if o['session']:
        session_path = o['session']
    elif o['chain']:
        pin_uuid = get_kv(progress_lines, pinned_key)
        if pin_uuid:
            # 链内后续成员：不再重匹配，用钉住的 UUID 直取
            head_case_file = find_case_file(suite, members[0]['case'])
            cd_tgt, ok = extract_pre_cd(read_text(head_case_file))
            base = cd_tgt if (cd_tgt and ok) else (o['repo_root'] or '')
            proj_dir = os.path.join(home, '.claude', 'projects', escape_proj_dir(base))
            session_path = os.path.join(proj_dir, pin_uuid + '.jsonl')
            if not os.path.isfile(session_path):
                die(E_LOCATE, '进度文件钉住的会话不存在：%s（uuid=%s；可 --session 手工指定或清除钉点重定位）'
                    % (session_path, pin_uuid))
        else:
            # 链首定位：cwd 取链首成员 case 文件 → 锚取 manifest 链首进入锚（= 链首启动 prompt 原文）
            head = members[0]
            head_case_file = find_case_file(suite, head['case'])
            cd_tgt, ok = extract_pre_cd(read_text(head_case_file))
            if cd_tgt and not ok:
                die(E_LOCATE, '链首案例 %s 的 cd 目标含变量无法静态解析：%s（请用 --session 手工指定）'
                    % (head['case'], cd_tgt))
            base = cd_tgt or o['repo_root']
            if not base:
                die(E_LOCATE, '链首会话工作目录不可得（case 无 cd 目标且仓库根不可得）')
            proj_dir = os.path.join(home, '.claude', 'projects', escape_proj_dir(base))
            anchor = norm_ws(head['anchor'])[:120]
            session_path = locate_session(proj_dir, anchor, u'链 %s 链首 %s' % (o['chain'], head['case']))
    else:
        # 独立案例：case 文件解析 cwd + 启动 prompt 锚
        case_file = find_case_file(suite, case_id)
        case_text = read_text(case_file)
        cd_tgt, ok = extract_pre_cd(case_text)
        if cd_tgt and not ok:
            die(E_LOCATE, '案例 %s 的 cd 目标含变量无法静态解析：%s（请用 --session 手工指定）'
                % (case_id, cd_tgt))
        base = cd_tgt or o['repo_root']
        if not base:
            die(E_LOCATE, '会话工作目录不可得（case 无 cd 目标且仓库根不可得）')
        anchor = extract_startup_prompt(case_text)
        if not anchor:
            die(E_LOCATE, '案例文件未找到"用户启动 prompt 原文"围栏块：%s（请用 --session 手工指定）' % case_file)
        proj_dir = os.path.join(home, '.claude', 'projects', escape_proj_dir(base))
        session_path = locate_session(proj_dir, anchor, u'案例 %s' % case_id)

    session_uuid = os.path.basename(session_path)
    if session_uuid.endswith('.jsonl'):
        session_uuid = session_uuid[:-6]

    # ---- 加载 + 防御性解析（R3.5）
    records, total, bad, fmt_ok = load_records(session_path)
    contract = detect_suite_contract(suite)
    archive_path = os.path.join(ev_dir, os.path.basename(session_path))
    backup_path = None

    def do_backup():
        """M-2 覆写语义：目标 result 已存在且非空 → 先备份再覆写，stderr 明示备份路径。"""
        if os.path.isfile(result_path) and os.path.getsize(result_path) > 0:
            bp = os.path.join(ev_dir, 'result-backup-%s.md' % now_stamp())
            shutil.copy2(result_path, bp)
            err('目标 result 已存在且非空，已备份原文件：%s' % bp)
            return bp
        return None

    def write_out(draft_text, degraded):
        """归档 + 备份 + 落草稿 + 进度更新（dry-run 全跳过）。"""
        nonlocal_backup = None
        if o['dry_run']:
            err('dry-run：跳过归档 / 备份 / 草稿写入 / 进度更新')
            return None
        if not os.path.isdir(ev_dir):
            os.makedirs(ev_dir)
        shutil.copy2(session_path, archive_path)  # R3.4 原始 jsonl 归档（降级路径同样归档：永不丢证据）
        nonlocal_backup = do_backup()
        with open(result_path, 'w', encoding='utf-8') as fh:
            fh.write(draft_text)
        lines = load_progress_lines(progress_path)
        if o['chain']:
            lines = upsert_kv(lines, 'chain_members.%s' % o['chain'],
                              ','.join(m['case'] for m in members))
            lines = upsert_kv(lines, pinned_key, session_uuid)
            lines = upsert_kv(lines, 'chain_session_path.%s' % o['chain'], session_path)
        lines = upsert_kv(lines, 'status.%s' % case_id,
                          'captured' if not degraded else 'captured-degraded')
        if not os.path.isdir(ev_root):
            os.makedirs(ev_root)
        with open(progress_path, 'w', encoding='utf-8') as fh:
            fh.write('\n'.join(lines) + '\n')
        return nonlocal_backup

    session_note = u'%s（原件归档：.evidence/%s/）' % (os.path.basename(session_path), case_id)

    if not fmt_ok:
        # ---- exit 4 降级：归档原件 + 草稿【运行中】留提示 + stderr 说明；不臆造
        err('transcript 格式未识别：总行 %d · 异常行 %d（>10%% 阈值）。' % (total, bad))
        err('降级处理：原始 jsonl 归档 + 草稿【运行中】节留人工摘录提示（永不静默丢证据、不臆造内容）。')
        meta = extract_meta(records)
        mid_sec = (u'**transcript 格式未识别（总行 %d · 异常行 %d 超 10%% 阈值）。**\n'
                   u'原始 jsonl 已归档：`.evidence/%s/%s`，请人工摘录；禁止凭记忆转写。'
                   % (total, bad, case_id, os.path.basename(session_path)))
        pre_sec = log_section(ev_dir, 'pre', o['chain'])
        post_sec = log_section(ev_dir, 'post', o['chain'])
        draft = redact(build_draft(contract, case_id, meta, o['os_info'],
                                   pre_sec, mid_sec, post_sec, session_note))
        backup_path = write_out(draft, degraded=True)
        print(json.dumps({'case': case_id, 'chain': o['chain'], 'session': session_path,
                          'result': None if o['dry_run'] else result_path,
                          'archive': None if o['dry_run'] else archive_path,
                          'backup': backup_path, 'degraded': True,
                          'dry_run': o['dry_run'], 'exit': E_FORMAT}, ensure_ascii=False))
        sys.exit(E_FORMAT)

    # ---- 链式切片（R3.6）：[本成员进入锚, 下一成员进入锚)
    sliced = records
    if o['chain']:
        m = members[member_idx]
        s_idx = find_anchor_idx(records, m['anchor'])
        if s_idx < 0:
            die(E_LOCATE, '链 %s 成员 %s 的进入锚未在会话中命中（exit 3 · 不猜切）：\n  锚: %s'
                % (o['chain'], m['case'], norm_ws(m['anchor'])[:160]))
        e_idx = len(records)
        if member_idx + 1 < len(members):
            nxt = members[member_idx + 1]
            n_idx = find_anchor_idx(records, nxt['anchor'], s_idx + 1)
            if n_idx >= 0:
                e_idx = n_idx
            else:
                err('下一成员 %s 的进入锚未命中（会话可能尚未推进到该成员）→ 本成员切片至文件末' % nxt['case'])
        sliced = records[s_idx:e_idx]
        err('链 %s 成员 %s 切片：记录区间 [%d, %d) / 全量 %d 条' %
            (o['chain'], case_id, s_idx, e_idx, len(records)))

    # ---- 渲染（R3.2）→ 脱敏（R3.4）→ 骨架合成（R3.3）
    meta = extract_meta(sliced or records)
    mid_sec = render_records(sliced, o['no_thinking'])
    if not mid_sec.strip():
        mid_sec = u'（切片区间内无可渲染记录；原件见归档）'
    pre_sec = log_section(ev_dir, 'pre', o['chain'])
    post_sec = log_section(ev_dir, 'post', o['chain'])
    draft = redact(build_draft(contract, case_id, meta, o['os_info'],
                               pre_sec, mid_sec, post_sec, session_note))
    backup_path = write_out(draft, degraded=False)

    print(json.dumps({'case': case_id, 'chain': o['chain'], 'session': session_path,
                      'result': None if o['dry_run'] else result_path,
                      'archive': None if o['dry_run'] else archive_path,
                      'backup': backup_path, 'degraded': False,
                      'dry_run': o['dry_run'], 'exit': E_OK}, ensure_ascii=False))
    sys.exit(E_OK)


if __name__ == '__main__':
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:  # 内部错误兜底：exit 5，永不静默
        err('内部错误：%s: %s' % (type(e).__name__, e))
        sys.exit(E_INTERNAL)
PYEOF
