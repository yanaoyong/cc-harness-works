#!/usr/bin/env python3
"""transcript_archive.py — Claude Code 会话 transcript 归档 CLI（sync / index / backfill）。

纯 Python stdlib（3.11+，零第三方）。三入口（手动命令 / cron / SessionEnd hook）复用本脚本。

角色分层（本脚本 = 编排层，串接 T1/T2 冻结库）::

    lib.transcript_lean   —— lean 变换 + secret 脱敏（确定性）
    lib.transcript_index  —— by-instance 索引 + index.tsv（幂等）

硬纪律::

    * 未启用（config 缺失 / enabled!=true）→ 打印一行 exit 0，零副作用（AC-5）。
    * git 写操作 **仅限归档仓自身**——绝不触碰业务仓 / 公有分发仓（DF-007 精神）。
    * 归档仓不可用（缺失 / .git 损坏 / --push remote 不可达）→ fail-closed 非零退出、不自动 re-clone（AC-5）。
    * 热层 / 冷层 / 索引产物重跑逐字节一致（gzip/tar mtime=0、遍历排序、无时间戳入产物）。
    * git / cold_sync 外呼一律 subprocess argv 数组、``shell=False``——禁 shell 拼接（SEC-1 / R-005）。
    * 输出信息走 stderr，机器可读结果走 stdout。写操作先落临时文件再原子 os.replace（防半写）。

meta 重建路线（Owner 建议路线 · index 子命令与源解耦、天然幂等）::

    index / by-instance 的会话 meta **从归档仓 lean 产物行重建**——lean 逐字保留信封字段
    （gitBranch / timestamp）与 tool_use 参数路径两信号，故 ``extract_session_meta`` 直接喂
    lean 行即可；``index`` 遂为纯归档仓内操作、与源（可能已被 cleanupPeriodDays 清理）无关、
    单独运行幂等。sync/backfill 提取阶段亦复用该重建（不落 meta-cache）。
"""

from __future__ import annotations

import argparse
import fcntl
import gzip
import io
import json
import os
import shlex
import shutil
import subprocess
import sys
import tarfile
import time
from pathlib import Path

# lib/ 与本脚本同级（scripts/transcript_archive.py 与 scripts/lib/）；注入自身目录后 import。
# 两副本路径（plugins/harness-core/scripts、.harness/scripts）下均可运行（各自 lib/ 同级镜像）。
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import transcript_index, transcript_lean  # noqa: E402

# --------------------------------------------------------------------------- #
# 缺省常量（Owner 冻结配置契约）
# --------------------------------------------------------------------------- #

ENV_STATE_HOME = "HARNESS_TRANSCRIPT_ARCHIVE_HOME"
ENV_SOURCE_ROOT = "HARNESS_TRANSCRIPT_SOURCE_ROOT"
DEFAULT_STATE_HOME = Path.home() / ".claude" / "harness-transcript-archive"
DEFAULT_SOURCE_ROOT = Path.home() / ".claude" / "projects"
DEFAULT_LOCK_STALE_SECONDS = 600

# 附属目录（AC-7）——仅 subagents/ 与 workflows/ 纳入归档（tool-results/ 不入）。
AUX_SUBDIRS = ("subagents", "workflows")


# --------------------------------------------------------------------------- #
# 日志（信息 → stderr）
# --------------------------------------------------------------------------- #

def log(msg: str) -> None:
    print(f"[transcript-archive] {msg}", file=sys.stderr)


def warn(msg: str) -> None:
    print(f"[transcript-archive] WARNING: {msg}", file=sys.stderr)


# --------------------------------------------------------------------------- #
# 原子写 / 确定性压缩 helper
# --------------------------------------------------------------------------- #

def _atomic_write_bytes(path: Path, data: bytes) -> None:
    """先落同目录临时文件 + fsync，再 os.replace 原子换名（防半写）。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.parent / f".{path.name}.tmp.{os.getpid()}"
    with open(tmp, "wb") as fh:
        fh.write(data)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


def _atomic_write_text(path: Path, text: str) -> None:
    _atomic_write_bytes(path, text.encode("utf-8"))


def _write_gz(path: Path, raw: bytes) -> None:
    """确定性 gzip（mtime=0、无内嵌文件名）——重跑逐字节一致。"""
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", mtime=0) as gz:
        gz.write(raw)
    _atomic_write_bytes(path, buf.getvalue())


def _write_aux_tar(path: Path, aux_dir: Path) -> bool:
    """把附属目录（subagents/ + workflows/）打确定性 tar.gz。

    确定性：条目按相对路径排序、mtime=0、uid=gid=0、固定 mode、无内嵌 gzip 文件名。
    返回 True=有内容已落盘；False=无文件、未落盘。
    """
    files: list[Path] = []
    for sub in AUX_SUBDIRS:
        d = aux_dir / sub
        if d.is_dir():
            files.extend(p for p in d.rglob("*") if p.is_file())
    if not files:
        return False
    files.sort(key=lambda p: p.relative_to(aux_dir).as_posix())
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode="w") as tar:
            for fp in files:
                data = fp.read_bytes()
                info = tarfile.TarInfo(name=fp.relative_to(aux_dir).as_posix())
                info.size = len(data)
                info.mtime = 0
                info.mode = 0o644
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                info.type = tarfile.REGTYPE
                tar.addfile(info, io.BytesIO(data))
    _atomic_write_bytes(path, buf.getvalue())
    return True


# --------------------------------------------------------------------------- #
# git（argv 数组 · shell=False · 仅归档仓）
# --------------------------------------------------------------------------- #

def run_git(archive_dir: Path, args: list[str], check: bool = True) -> subprocess.CompletedProcess:
    """在归档仓内执行 git（``git -C <archive_dir> ...``）。禁 shell=True 拼接（SEC-1）。"""
    proc = subprocess.run(
        ["git", "-C", str(archive_dir), *args],
        capture_output=True,
        text=True,
    )
    if check and proc.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc


def archive_available(archive_dir: Path) -> bool:
    """归档仓本地 clone 是否可用：目录存在且为有效 git 仓（AC-5 fail-closed 前置）。"""
    if not archive_dir.is_dir():
        return False
    return run_git(archive_dir, ["rev-parse", "--git-dir"], check=False).returncode == 0


def commit_if_changed(archive_dir: Path, message: str) -> bool:
    """git add -A → porcelain 非空才 commit（无内容变化不产生空 commit · AC-4）。返回是否 commit。"""
    run_git(archive_dir, ["add", "-A"])
    if run_git(archive_dir, ["status", "--porcelain"]).stdout.strip():
        run_git(archive_dir, ["commit", "-m", message])
        return True
    return False


# --------------------------------------------------------------------------- #
# flock 串行化 + 锁龄检测（AC-9）
# --------------------------------------------------------------------------- #

def _read_lock_age(lock_path: Path) -> float | None:
    """读锁文件内持锁者写入的时间戳算锁龄（秒）。解析失败 → None（视作刚取锁/新鲜）。

    锁龄来源固定单一 = 锁文件内 ``acquired`` 时间戳（持锁成功后立即写入 · 评审条件 C-1）。
    """
    try:
        data = json.loads(lock_path.read_text())
        return max(time.time() - float(data["acquired"]), 0.0)
    except Exception:
        return None


def acquire_lock(lock_path: Path, stale_seconds: int):
    """非阻塞 flock 排他锁（锁粒度=归档仓级 · AC-9）。

    返回 ``(fd, status)``：
      * ``(fd, "acquired")`` —— 取锁成功，已写入持锁时间戳；调用方负责 release。
      * ``(None, "contention")`` —— 取锁失败且锁龄 ≤ 阈值：正常 contention（第二实例干净退出 exit 0）。
      * ``(None, "stale")`` —— 取锁失败且锁龄 > 阈值：病态（持锁者卡死），须非零退出告警。
    """
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(lock_path), os.O_RDWR | os.O_CREAT, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        age = _read_lock_age(lock_path)
        os.close(fd)
        if age is None or age <= stale_seconds:
            return None, "contention"
        return None, "stale"
    # 取锁成功 → 立即写入持锁时间戳（供 contender 判锁龄，评审条件 C-1）。
    os.ftruncate(fd, 0)
    os.lseek(fd, 0, os.SEEK_SET)
    os.write(fd, json.dumps({"pid": os.getpid(), "acquired": time.time()}).encode())
    os.fsync(fd)
    return fd, "acquired"


def release_lock(fd: int) -> None:
    try:
        fcntl.flock(fd, fcntl.LOCK_UN)
    finally:
        os.close(fd)


# --------------------------------------------------------------------------- #
# 配置 / 上下文
# --------------------------------------------------------------------------- #

class Ctx:
    """本轮运行上下文（解析后配置 + 可变状态）。"""

    def __init__(self, state_home: Path, source_root: Path, cfg: dict):
        self.state_home = state_home
        self.source_root = source_root
        self.archive_dir = Path(cfg.get("archive_dir") or (state_home / "archive")).expanduser()
        self.cold_dir = Path(cfg.get("cold_dir") or (state_home / "cold")).expanduser()
        self.cold_retention_days = int(cfg.get("cold_retention_days") or 0)
        self.denylist_path = cfg.get("denylist_path") or None
        self.cold_sync_cmd = (cfg.get("cold_sync_cmd") or "").strip()
        self.lock_stale_seconds = int(cfg.get("lock_stale_seconds") or DEFAULT_LOCK_STALE_SECONDS)
        # 机器本地水位（不入归档仓 · HITL-2 多机修订）
        self.watermarks_path = state_home / "watermarks.json"
        self.watermarks: dict = load_watermarks(self.watermarks_path)
        # 归档仓内运行态 .state/（机器本地，入 .gitignore）
        self.state_dir = self.archive_dir / ".state"
        self.lock_path = self.state_dir / ".lock"
        self.last_skip_path = self.state_dir / "last_skip"
        self.failed_list_path = self.state_dir / "cold_sync_failed.list"
        self.cold_sync_failed: set[str] = load_failed_list(self.failed_list_path)
        # denylist 编译（编译失败条目 skip+warning、内置族仍生效 · fail-safe）
        self.denylist = transcript_lean.load_denylist(self.denylist_path)
        for lineno, err in self.denylist.skipped:
            warn(f"denylist line {lineno} skipped: {err}")


def resolve_state_home() -> Path:
    return Path(os.environ.get(ENV_STATE_HOME) or DEFAULT_STATE_HOME).expanduser()


def resolve_source_root() -> Path:
    return Path(os.environ.get(ENV_SOURCE_ROOT) or DEFAULT_SOURCE_ROOT).expanduser()


def load_config(state_home: Path) -> dict | None:
    """读 <STATE_HOME>/config.json。缺失 → None（未配置）。"""
    path = state_home / "config.json"
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except Exception as exc:  # noqa: BLE001
        warn(f"config.json 解析失败: {exc}")
        return None


def load_watermarks(path: Path) -> dict:
    if path.exists():
        try:
            return json.loads(path.read_text())
        except Exception:  # noqa: BLE001
            return {}
    return {}


def save_watermarks(path: Path, data: dict) -> None:
    _atomic_write_text(path, json.dumps(data, sort_keys=True) + "\n")


def load_failed_list(path: Path) -> set[str]:
    if path.exists():
        return {ln.strip() for ln in path.read_text().splitlines() if ln.strip()}
    return set()


def save_failed_list(path: Path, entries: set[str]) -> None:
    _atomic_write_text(path, "".join(f"{p}\n" for p in sorted(entries)))


def ensure_state_and_gitignore(ctx: Ctx) -> None:
    """建 .state/ 目录并保证归档仓 .gitignore 含 ``.state/``（运行态不入库）。"""
    ctx.state_dir.mkdir(parents=True, exist_ok=True)
    gi = ctx.archive_dir / ".gitignore"
    lines = gi.read_text().splitlines() if gi.exists() else []
    if ".state/" not in lines:
        lines.append(".state/")
        _atomic_write_text(gi, "".join(f"{ln}\n" for ln in lines))


# --------------------------------------------------------------------------- #
# cold_sync（AC-8）
# --------------------------------------------------------------------------- #

COLD_PATH_PLACEHOLDER = "{COLD_PATH}"


def _build_cold_sync_argv(cmd: str, target_path: str) -> list[str]:
    """把 cold_sync_cmd 展开为 argv 数组（两形态，均 shell=False 数据分离）。

    形态判定按 ``shlex.split(cmd)`` 后是否有任一 token 含子串 ``{COLD_PATH}``：

    * **占位符替换式**（任一 token 含 ``{COLD_PATH}``）：对**全部** token 做
      ``str.replace("{COLD_PATH}", target_path)``、**不再尾追**——支持 rclone/scp 等
      「动态源在前、固定目的在后」主用例（``rclone copy {COLD_PATH} myremote:claude-cold``）。
    * **无占位符尾追式**（无任一 token 含占位符）：目标路径**追加为末位 argv**，
      维持既有向后兼容行为。
    """
    tokens = shlex.split(cmd)
    if any(COLD_PATH_PLACEHOLDER in tok for tok in tokens):
        return [tok.replace(COLD_PATH_PLACEHOLDER, target_path) for tok in tokens]
    return [*tokens, target_path]


def _run_cold_sync(cmd: str, target_path: str) -> bool:
    """执行 cold_sync_cmd（占位符替换式 / 无占位符尾追式两形态）。

    argv 数组经 ``_build_cold_sync_argv`` 构造 + ``shell=False``——命令与数据分离，杜绝 shell
    求值面命令注入（SEC-1）。两形态：

    * ``cmd`` 含 ``{COLD_PATH}`` → 全 token 替换为 ``target_path``、不尾追（源在前场景）。
    * ``cmd`` 无 ``{COLD_PATH}`` → ``target_path`` 追加为末位参数（向后兼容尾追式）。

    cold_sync_cmd 为用户自撰配置；如需管道/重定向等 shell 特性，用户自行配 ``sh -c '<...>'``
    作为命令（其显式选择、其自负）。返回 True=退出码 0。
    """
    try:
        proc = subprocess.run(_build_cold_sync_argv(cmd, target_path), capture_output=True, text=True)
    except Exception as exc:  # noqa: BLE001
        warn(f"cold_sync_cmd 执行异常 ({target_path}): {exc}")
        return False
    if proc.returncode != 0:
        warn(f"cold_sync_cmd 非零退出 ({proc.returncode}) for {target_path}: {proc.stderr.strip()}")
    return proc.returncode == 0


def cold_sync_artifact(ctx: Ctx, target_path: Path) -> None:
    """冷层产物落盘成功后同步一次（cold_sync_cmd 空 → 不执行任何外部命令 · AC-8a）。

    命令非零退出 → warning + 路径入 failed.list；**sync 主流程不整体失败、热层水位不回退**（AC-8c）。
    """
    if not ctx.cold_sync_cmd:
        return
    if not _run_cold_sync(ctx.cold_sync_cmd, str(target_path)):
        ctx.cold_sync_failed.add(str(target_path))


def retry_failed_cold_sync(ctx: Ctx) -> None:
    """下轮 sync 取得 flock 后、主提取前，对 failed.list 逐项重试一次（C-2(i) · 临界区内）。

    成功移出列；仍败保留 + warning。cold_sync_cmd 为空则无法重试、原样保留。
    """
    if not ctx.cold_sync_failed:
        return
    if not ctx.cold_sync_cmd:
        warn(f"cold_sync_failed 有 {len(ctx.cold_sync_failed)} 项待同步，但 cold_sync_cmd 为空，保留待配置")
        return
    still: set[str] = set()
    for target in sorted(ctx.cold_sync_failed):
        if Path(target).exists() and _run_cold_sync(ctx.cold_sync_cmd, target):
            log(f"cold_sync 重试成功，移出 failed.list: {target}")
        else:
            still.add(target)
            warn(f"cold_sync 重试仍失败，保留 failed.list: {target}")
    ctx.cold_sync_failed = still


def apply_retention(ctx: Ctx) -> None:
    """回收冷层超龄文件（cold_retention_days>0），**跳过 failed.list 中待同步项**（C-2(ii)）。"""
    if ctx.cold_retention_days <= 0 or not ctx.cold_dir.is_dir():
        return
    cutoff = time.time() - ctx.cold_retention_days * 86400
    protected = set(ctx.cold_sync_failed)
    for fp in ctx.cold_dir.rglob("*"):
        if not fp.is_file() or str(fp) in protected:
            continue
        if fp.stat().st_mtime < cutoff:
            fp.unlink()
            log(f"retention 回收超龄冷层: {fp}")


# --------------------------------------------------------------------------- #
# 单会话提取（热层 + 冷层 + 附属目录 AC-7）
# --------------------------------------------------------------------------- #

def _split_complete(raw_bytes: bytes) -> tuple[bytes, int]:
    """取完整行部分（以 \\n 结尾）；尾部不完整行丢弃、下轮补齐（AC-4）。

    返回 ``(complete_bytes, processed_offset)``——processed_offset = 最后完整行末字节位置。
    """
    last_nl = raw_bytes.rfind(b"\n")
    if last_nl < 0:
        return b"", 0
    return raw_bytes[: last_nl + 1], last_nl + 1


def process_session(ctx: Ctx, project: str, session_id: str, jsonl_path: Path, ignore_watermark: bool) -> bool:
    """提取单会话：水位增量判定 → lean 热层 → gz/tar 冷层 → cold_sync → 附属目录（AC-7）。

    水位值 = ``{"size": 上轮处理时文件字节数, "processed": 完整行末偏移}``。
      * 增量判定用 ``size``：未增长（cur_size == 记录 size）→ skip；增长/收缩/水位缺失 → 整文件重提。
        （lean 确定性 → 水位缺失重提产物与仓内逐字节相同 → git 无 diff、无新 commit · AC-4 HITL-2）。
      * ``processed`` = 尾部不完整行前的偏移，仅作记录。
    热层写成功后方推进水位；冷层 / cold_sync 失败不回退水位（防热层每轮重提死循环 · AC-8c）。
    返回是否实际处理（供计数）。
    """
    cur_size = jsonl_path.stat().st_size
    wm = ctx.watermarks.get(session_id)
    if not ignore_watermark and isinstance(wm, dict) and wm.get("size") == cur_size:
        return False  # 未增长 → skip

    raw_bytes = jsonl_path.read_bytes()
    complete, processed = _split_complete(raw_bytes)
    if not complete.strip():
        # 尚无完整行（全是不完整尾行）——记录 size 避免每轮空转，不落热层。
        ctx.watermarks[session_id] = {"size": cur_size, "processed": processed}
        return False

    raw_lines = complete.decode("utf-8", errors="replace").splitlines()

    # --- 热层 lean（AC-1 确定性）---
    lean = transcript_lean.lean_transform(
        raw_lines, denylist=ctx.denylist, truncate_bytes=transcript_lean.DEFAULT_TRUNCATE_BYTES
    )
    for w in lean.warnings:
        warn(f"{session_id}: {w}")
    meta = transcript_index.extract_session_meta(raw_lines, project, session_id)
    yyyymm = (meta.get("date") or "")[:7] or "unknown"  # date 空 → unknown（路径内容确定，禁 mtime）

    hot_path = ctx.archive_dir / project / yyyymm / f"{session_id}.lean.jsonl"
    _atomic_write_text(hot_path, "\n".join(lean.lines) + "\n")

    # --- 附属目录 lean（AC-7：subagents/ 与 workflows/）---
    aux_src = jsonl_path.parent / session_id
    session_dir = ctx.archive_dir / project / yyyymm / session_id
    if aux_src.is_dir():
        for sub in AUX_SUBDIRS:
            sub_src = aux_src / sub
            if not sub_src.is_dir():
                continue
            for aux_file in sorted(p for p in sub_src.rglob("*.jsonl") if p.is_file()):
                aux_lines = aux_file.read_text(encoding="utf-8", errors="replace").splitlines()
                aux_lean = transcript_lean.lean_transform(
                    aux_lines, denylist=ctx.denylist,
                    truncate_bytes=transcript_lean.DEFAULT_TRUNCATE_BYTES,
                )
                rel = aux_file.relative_to(aux_src)
                out = session_dir / rel.parent / f"{aux_file.stem}.lean.jsonl"
                _atomic_write_text(out, "\n".join(aux_lean.lines) + "\n")

    # --- 冷层（raw gz + 附属 tar.gz，确定性）---
    cold_gz = ctx.cold_dir / project / f"{session_id}.jsonl.gz"
    _write_gz(cold_gz, complete)
    cold_sync_artifact(ctx, cold_gz)  # 落盘成功后方同步（AC-8b）
    if aux_src.is_dir():
        cold_tar = ctx.cold_dir / project / f"{session_id}-aux.tar.gz"
        if _write_aux_tar(cold_tar, aux_src):
            cold_sync_artifact(ctx, cold_tar)

    # 热层已成功 → 推进水位（冷层/同步失败不影响）。
    ctx.watermarks[session_id] = {"size": cur_size, "processed": processed}
    return True


def iter_sessions(source_root: Path):
    """遍历源根下各项目的 *.jsonl 会话（确定性排序）。"""
    if not source_root.is_dir():
        return
    for project_dir in sorted(source_root.iterdir()):
        if not project_dir.is_dir():
            continue
        project = project_dir.name  # 源根下目录名原样（不转义还原 · 确定性优先）
        for jsonl in sorted(project_dir.glob("*.jsonl")):
            yield project, jsonl.stem, jsonl


# --------------------------------------------------------------------------- #
# 索引重建（AC-3 · 纯归档仓内操作、幂等）
# --------------------------------------------------------------------------- #

def rebuild_index(ctx: Ctx) -> None:
    """从归档仓 lean 产物行重建 index.tsv + by-instance/（派生物全量重写、幂等）。

    仅扫主会话 lean（``<project>/<yyyy-mm>/<session>.lean.jsonl`` · 3 层深 glob）；附属目录 lean
    （4+ 层深）不构成独立会话、不进索引。meta 从 lean 行重建（信封 gitBranch/timestamp + tool_use
    路径两信号在 lean 存活），故与源无关、单独运行幂等。
    """
    archive = ctx.archive_dir
    metas: list[dict] = []
    lean_rel: dict[str, str] = {}
    for lean_file in sorted(archive.glob("*/*/*.lean.jsonl")):  # glob `*` 不匹配 .git/.state（点开头）
        rel = lean_file.relative_to(archive)
        project = rel.parts[0]
        session_id = lean_file.name[: -len(".lean.jsonl")]
        lines = lean_file.read_text(encoding="utf-8", errors="replace").splitlines()
        meta = transcript_index.extract_session_meta(lines, project, session_id)
        metas.append(meta)
        lean_rel[meta.get("session", "")] = rel.as_posix()

    _atomic_write_text(archive / "index.tsv", transcript_index.render_index_tsv(metas))

    # by-instance/ 全量重写（先清后写 → 删除的实例页随 git add -A 落地）。
    bi_dir = archive / "by-instance"
    if bi_dir.exists():
        shutil.rmtree(bi_dir)
    pages = transcript_index.render_by_instance(
        metas, lambda m: lean_rel.get(m.get("session", ""), "")
    )
    for relpath, content in pages.items():
        _atomic_write_text(archive / relpath, content)


# --------------------------------------------------------------------------- #
# push（多机冲突策略 · §2.1.12 HITL-2 修订）
# --------------------------------------------------------------------------- #

def push_with_conflict_retry(ctx: Ctx) -> bool:
    """--push：遇非 fast-forward → pull --rebase + 重建索引（派生物不三方合并）+ commit + 重试一次。

    再败报错留待下轮（不强推、不循环）。remote 不可达等其他失败 → 直接 False（fail-closed · AC-5）。
    """
    first = run_git(ctx.archive_dir, ["push"], check=False)
    if first.returncode == 0:
        return True
    stderr = (first.stderr or "").lower()
    non_ff = "fast-forward" in stderr or "rejected" in stderr or "non-fast-forward" in stderr
    if not non_ff:
        warn(f"push 失败（非冲突类，如 remote 不可达）: {first.stderr.strip()}")
        return False

    log("push 遇非 fast-forward，pull --rebase + 重建索引后重试一次")
    rebase = run_git(ctx.archive_dir, ["pull", "--rebase"], check=False)
    if rebase.returncode != 0:
        run_git(ctx.archive_dir, ["rebase", "--abort"], check=False)
        warn(f"pull --rebase 失败，留待下轮: {rebase.stderr.strip()}")
        return False
    rebuild_index(ctx)  # 派生物全量重写，不三方合并
    commit_if_changed(ctx.archive_dir, "transcript-archive: rebuild index after rebase")
    second = run_git(ctx.archive_dir, ["push"], check=False)
    if second.returncode != 0:
        warn(f"重试 push 仍失败，留待下轮: {second.stderr.strip()}")
        return False
    return True


# --------------------------------------------------------------------------- #
# 子命令实现
# --------------------------------------------------------------------------- #

def _run_extract_pipeline(ctx: Ctx, ignore_watermark: bool, do_push: bool) -> int:
    """sync/backfill 共用管线（临界区内）：cold_sync 重试 → 主提取 → 保留 → 索引 → commit → push。"""
    # 1. failed.list 下轮重试（C-2(i)·须在 flock 临界区内、主提取前）
    retry_failed_cold_sync(ctx)

    # 2. 主提取（热层 + 冷层 + 附属目录）
    processed = 0
    for project, session_id, jsonl in iter_sessions(ctx.source_root):
        if process_session(ctx, project, session_id, jsonl, ignore_watermark):
            processed += 1

    # 3. 水位 + failed.list 持久化（与 failed.list 同临界区 · 防 lost update）
    save_watermarks(ctx.watermarks_path, ctx.watermarks)
    save_failed_list(ctx.failed_list_path, ctx.cold_sync_failed)

    # 4. 冷层保留策略（跳过 failed.list 待同步项）
    apply_retention(ctx)

    # 5. 索引联动重建（提取后）
    rebuild_index(ctx)

    # 6. commit（无 diff 不空转）
    mode = "backfill" if ignore_watermark else "sync"
    committed = commit_if_changed(
        ctx.archive_dir, f"transcript-archive {mode}: {processed} session(s) @ {int(time.time())}"
    )
    log(f"{mode}: processed={processed} committed={committed}")

    # 7. push（显式方推）
    rc = 0
    if do_push:
        if not push_with_conflict_retry(ctx):
            warn("--push 未成功，留待下轮")
            rc = 4
    print(json.dumps({"mode": mode, "processed": processed, "committed": committed}), flush=True)
    return rc


def cmd_sync(ctx: Ctx, args) -> int:
    return _run_extract_pipeline(ctx, ignore_watermark=False, do_push=args.push)


def cmd_backfill(ctx: Ctx, args) -> int:
    # backfill = 忽略水位的全量提取（复用同一管线）
    return _run_extract_pipeline(ctx, ignore_watermark=True, do_push=args.push)


def cmd_index(ctx: Ctx, args) -> int:
    rebuild_index(ctx)
    committed = commit_if_changed(ctx.archive_dir, f"transcript-archive index @ {int(time.time())}")
    log(f"index: committed={committed}")
    print(json.dumps({"mode": "index", "committed": committed}), flush=True)
    return 0


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="transcript_archive.py",
        description="Claude Code 会话 transcript 归档（sync / index / backfill）",
    )
    sub = p.add_subparsers(dest="command", required=True)

    sp = sub.add_parser("sync", help="增量提取 + 落盘 + 可选 commit（--push 显式方推）")
    sp.add_argument("--push", action="store_true", help="commit 后推送归档仓（显式开关）")

    ip = sub.add_parser("index", help="重建 index.tsv + by-instance/（派生物全量重写、幂等）")
    ip.set_defaults(push=False)

    bp = sub.add_parser("backfill", help="首次全量提取（忽略水位的 sync）")
    bp.add_argument("--push", action="store_true", help="commit 后推送归档仓（显式开关）")

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    state_home = resolve_state_home()
    source_root = resolve_source_root()

    # --- opt-in 门：未启用 → 零副作用 exit 0（AC-5）---
    cfg = load_config(state_home)
    if cfg is None or cfg.get("enabled") is not True:
        log("未启用（config 缺失或 enabled!=true），不做任何落盘/commit（exit 0）")
        return 0

    ctx = Ctx(state_home, source_root, cfg)

    # --- 归档仓不可用 fail-closed（缺失 / .git 损坏）→ 非零、不 re-clone（AC-5）---
    if not archive_available(ctx.archive_dir):
        warn(f"归档仓不可用（缺失或 .git 损坏），fail-closed 中止本轮、不自动 re-clone: {ctx.archive_dir}")
        return 2

    ensure_state_and_gitignore(ctx)

    # --- flock 串行化 + 锁龄检测（AC-9）---
    fd, status = acquire_lock(ctx.lock_path, ctx.lock_stale_seconds)
    if status == "contention":
        # 正常 contention：干净退出 exit 0，但 skip 可观测（stderr + .state/last_skip）
        log("另一实例持锁（正常 contention），本轮 skip、不改水位/不重复提交（exit 0）")
        _atomic_write_text(ctx.last_skip_path, f"{int(time.time())}\n")
        return 0
    if status == "stale":
        # 病态：持锁者卡死（锁龄超阈值）→ 显式告警 + 非零退出，不强抢锁、不静默 exit 0
        warn(f"检测到陈旧锁（锁龄 > {ctx.lock_stale_seconds}s，持锁者疑似卡死），非零退出告警、不强抢锁")
        return 3

    try:
        dispatch = {"sync": cmd_sync, "index": cmd_index, "backfill": cmd_backfill}
        return dispatch[args.command](ctx, args)
    finally:
        release_lock(fd)


if __name__ == "__main__":
    sys.exit(main())
