#!/usr/bin/env python3
"""Helper for setup-agent-toolkit.ps1.

scan   Record every aws-mcp entry that already exists, before the toolkit runs.
patch  Add AWS_MCP_PROXY_PROFILES to each aws-mcp entry the toolkit wrote,
       touching nothing else in the file. Every edited file is backed up first.
rules  Put the AWS starter rules into CLAUDE.md / AGENTS.md between stable
       markers, appending to existing files and never overwriting them.
"""

import argparse
import datetime
import json
import os
import re
import shutil
import sys
import urllib.request
from pathlib import Path

HOME = Path.home()
APPDATA = Path(os.environ.get("APPDATA", HOME / "AppData" / "Roaming"))
ENV_KEY = "AWS_MCP_PROXY_PROFILES"
BEGIN = "<!-- BEGIN AWS Agent Toolkit rules -->"
END = "<!-- END AWS Agent Toolkit rules -->"
RULES_URL = "https://raw.githubusercontent.com/aws/agent-toolkit-for-aws/refs/heads/main/rules/aws-starter-rules.md"

FIXED = [
    HOME / ".claude.json",
    HOME / ".claude" / "settings.json",
    HOME / ".cursor" / "mcp.json",
    HOME / ".kiro" / "settings" / "mcp.json",
    HOME / ".gemini" / "settings.json",
    HOME / ".codex" / "config.toml",
    HOME / ".copilot" / "mcp-config.json",
    HOME / ".config" / "opencode" / "opencode.json",
    APPDATA / "Claude" / "claude_desktop_config.json",
    APPDATA / "Code" / "User" / "mcp.json",
    APPDATA / "Code" / "User" / "settings.json",
]
MAX_BYTES = 8 * 1024 * 1024


def candidates():
    seen = set()
    out = []
    for p in FIXED:
        if p.is_file():
            seen.add(p.resolve())
            out.append(p)
    # Any other config under a dot-folder in the home directory that mentions aws-mcp.
    for top in HOME.iterdir():
        if not top.is_dir() or not top.name.startswith("."):
            continue
        base_depth = len(top.parts)
        for root, dirs, files in os.walk(top):
            depth = len(Path(root).parts) - base_depth
            if depth >= 3:
                dirs[:] = []
            dirs[:] = [d for d in dirs if d not in ("node_modules", ".git", "cache", "Cache", "logs", "sessions", "projects", "todos", "shell-snapshots")]
            for f in files:
                if not (f.endswith(".json") or f.endswith(".toml")):
                    continue
                p = Path(root) / f
                try:
                    if p.stat().st_size > MAX_BYTES:
                        continue
                    rp = p.resolve()
                    if rp in seen:
                        continue
                    if "aws-mcp" in p.read_text(encoding="utf-8", errors="ignore"):
                        seen.add(rp)
                        out.append(p)
                except OSError:
                    continue
    return out


def walk_json(node, path=()):
    """Yield (parent_key, path_to_entry, entry_dict) for every aws-mcp server entry."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "aws-mcp" and isinstance(v, dict) and path and path[-1] in ("mcpServers", "servers", "mcp", "mcp_servers"):
                yield path[-1], path + (k,), v
            else:
                yield from walk_json(v, path + (k,))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from walk_json(v, path + (str(i),))


def toml_has_entry(text):
    return re.search(r'^\s*\[\s*mcp_servers\.(?:"aws-mcp"|aws-mcp)\s*\]\s*$', text, re.M) is not None


def scan_entries():
    found = []
    for p in candidates():
        try:
            text = p.read_text(encoding="utf-8")
        except OSError:
            continue
        if p.suffix == ".toml":
            if toml_has_entry(text):
                found.append({"file": str(p), "path": "mcp_servers.aws-mcp"})
            continue
        try:
            data = json.loads(text)
        except ValueError:
            continue
        for _parent, path, _entry in walk_json(data):
            found.append({"file": str(p), "path": "/".join(path)})
    return found


def backup(p: Path):
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    dst = p.with_name(p.name + ".bak-" + stamp)
    shutil.copy2(p, dst)
    return dst


def ask(prompt, choices):
    while True:
        ans = input(prompt).strip().lower()
        if ans in choices:
            return ans
        print("  Type one of: " + ", ".join(choices))


def patch_json(p: Path, profile, pre_keys):
    text = p.read_text(encoding="utf-8")
    data = json.loads(text)
    changed = False
    for parent, path, entry in walk_json(data):
        key = "/".join(path)
        env_field = "environment" if parent == "mcp" else "env"  # OpenCode uses "environment"
        env = entry.get(env_field)
        current = env.get(ENV_KEY) if isinstance(env, dict) else None
        profiles = (current or "").split()
        if profile in profiles:
            print(f"  ok      {p} :: {key} already lists {profile}")
            continue
        if (str(p), key) in pre_keys or current:
            print(f"  exists  {p} :: {key}")
            print(f"          {ENV_KEY} is currently: {current!r}")
            choice = ask("          [a]ppend gsl to the list, [r]eplace with gsl, [s]kip this entry: ".replace("gsl", profile), ("a", "r", "s"))
            if choice == "s":
                continue
            new_val = " ".join(profiles + [profile]) if choice == "a" else profile
        else:
            new_val = profile
        if not isinstance(env, dict):
            env = {}
            entry[env_field] = env
        env[ENV_KEY] = new_val
        changed = True
        print(f"  set     {p} :: {key} {env_field}.{ENV_KEY} = {new_val!r}")
    if changed:
        bak = backup(p)
        nl = "\r\n" if "\r\n" in text else "\n"
        out = json.dumps(data, indent=2, ensure_ascii=False)
        if nl != "\n":
            out = out.replace("\n", nl)
        if text.endswith(("\n", "\r\n")):
            out += nl
        p.write_text(out, encoding="utf-8", newline="")
        print(f"          backup: {bak}")
    return changed


def patch_toml(p: Path, profile, pre_keys):
    text = p.read_text(encoding="utf-8")
    if not toml_has_entry(text):
        return False
    key = "mcp_servers.aws-mcp"
    section = re.search(r'(?ms)^\s*\[\s*mcp_servers\.(?:"aws-mcp"|aws-mcp)(?:\.env)?\s*\].*?(?=^\s*\[(?!\s*mcp_servers\.(?:"aws-mcp"|aws-mcp)\.env)|\Z)', text)
    if section and re.search(ENV_KEY + r'\s*=\s*"[^"]*\b' + re.escape(profile) + r'\b[^"]*"', section.group(0)):
        print(f"  ok      {p} :: {key} already lists {profile}")
        return False
    if re.search(r'^\s*\[\s*mcp_servers\.(?:"aws-mcp"|aws-mcp)\.env\s*\]', text, re.M) or re.search(
        r'(?s)\[\s*mcp_servers\.(?:"aws-mcp"|aws-mcp)\s*\][^\[]*?^\s*env\s*=', text, re.M
    ):
        print(f"  manual  {p} :: {key} already has an env table; add {ENV_KEY} = \"{profile}\" to it by hand")
        return False
    if (str(p), key) in pre_keys:
        print(f"  exists  {p} :: {key} predates this setup")
        if ask(f"          add {ENV_KEY} = \"{profile}\" to it? [y/n]: ", ("y", "n")) == "n":
            return False
    nl = "\r\n" if "\r\n" in text else "\n"
    new = re.sub(
        r'^(\s*\[\s*mcp_servers\.(?:"aws-mcp"|aws-mcp)\s*\]\s*)$',
        lambda m: m.group(1) + nl + f'env = {{ {ENV_KEY} = "{profile}" }}',
        text, count=1, flags=re.M,
    )
    bak = backup(p)
    p.write_text(new, encoding="utf-8", newline="")
    print(f"  set     {p} :: {key} env.{ENV_KEY} = {profile!r}")
    print(f"          backup: {bak}")
    return True


def cmd_scan(args):
    entries = scan_entries()
    Path(args.out).write_text(json.dumps(entries, indent=2), encoding="utf-8")
    print(f"Found {len(entries)} aws-mcp entr{'y' if len(entries) == 1 else 'ies'} before setup.")
    for e in entries:
        print(f"  {e['file']} :: {e['path']}")


def cmd_patch(args):
    pre = []
    if args.pre and Path(args.pre).is_file():
        pre = json.loads(Path(args.pre).read_text(encoding="utf-8"))
    pre_keys = {(e["file"], e["path"]) for e in pre}
    files = candidates()
    touched = 0
    any_entry = False
    for p in files:
        try:
            if p.suffix == ".toml":
                if toml_has_entry(p.read_text(encoding="utf-8")):
                    any_entry = True
                    touched += patch_toml(p, args.profile, pre_keys)
            else:
                data = json.loads(p.read_text(encoding="utf-8"))
                if any(True for _ in walk_json(data)):
                    any_entry = True
                    touched += patch_json(p, args.profile, pre_keys)
        except ValueError as e:
            print(f"  skip    {p}: not valid JSON ({e})")
        except OSError as e:
            print(f"  skip    {p}: {e}")
    if not any_entry:
        print("No aws-mcp entry was found in any known MCP configuration file.")
        return 2
    print(f"Updated {touched} file(s).")
    return 0


def fetch_rules():
    with urllib.request.urlopen(RULES_URL, timeout=30) as r:
        return r.read().decode("utf-8")


def place_rules(target: Path, body: str):
    block = f"{BEGIN}\n{body.rstrip()}\n{END}\n"
    if target.exists():
        text = target.read_text(encoding="utf-8")
        if BEGIN in text and END in text:
            start = text.index(BEGIN)
            stop = text.index(END) + len(END)
            tail = text[stop:]
            if tail.startswith("\r\n"):
                tail = tail[2:]
            elif tail.startswith("\n"):
                tail = tail[1:]
            new = text[:start] + block + tail
            action = "replaced block in"
        else:
            sep = "" if text.endswith("\n") or not text else "\n"
            new = text + sep + "\n" + block
            action = "appended to"
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        new = block
        action = "created"
    target.write_text(new, encoding="utf-8")
    print(f"  {action} {target}")


def cmd_rules(args):
    body = fetch_rules()
    root = Path(args.dir).resolve()
    if not root.is_dir():
        print(f"Not a folder: {root}")
        return 1
    for name in args.files:
        place_rules(root / name, body)
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan")
    s.add_argument("--out", required=True)
    pt = sub.add_parser("patch")
    pt.add_argument("--profile", required=True)
    pt.add_argument("--pre")
    r = sub.add_parser("rules")
    r.add_argument("--dir", required=True)
    r.add_argument("--files", nargs="+", default=["CLAUDE.md", "AGENTS.md"])
    a = ap.parse_args()
    if a.cmd == "scan":
        return cmd_scan(a) or 0
    if a.cmd == "patch":
        return cmd_patch(a)
    return cmd_rules(a)


if __name__ == "__main__":
    sys.exit(main())
