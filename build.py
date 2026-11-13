#!/usr/bin/env python3
"""把模块打包成 KernelSU / Magisk 可安装的 zip。

产物: dist/coloros_telemetry_blocker-v<version>.zip

zip 根目录必须是 module.prop，安装器据此解析模块信息。
dist/ 与 __pycache__ 不进包。
"""
import re
import sys
import zipfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent
DIST = ROOT / "dist"

EXCLUDE_DIRS = {"dist", "docs", "__pycache__", ".git", ".github", ".idea", ".vscode"}
EXCLUDE_FILES = {".gitignore", "build.py", "deploy.ps1", "DEVELOPMENT.md", "LICENSE"}

# 需要保留可执行位的文件（zip 外部属性写 0755）
EXECUTABLE = {"customize.sh"}


def module_version() -> str:
    text = (ROOT / "module.prop").read_text(encoding="utf-8")
    m = re.search(r"^version=(.+)$", text, re.MULTILINE)
    return (m.group(1).strip() if m else "dev").lstrip("v")


def iter_files():
    for path in sorted(ROOT.rglob("*")):
        if path.is_dir():
            continue
        rel = path.relative_to(ROOT).as_posix()
        if any(part in EXCLUDE_DIRS for part in path.relative_to(ROOT).parts[:-1]):
            continue
        if rel in EXCLUDE_FILES:
            continue
        if path.name.startswith("."):   # .gitignore / .gitattributes 等
            continue
        yield path, rel


def validate_hosts() -> int:
    """校验 system/etc/hosts：每条非注释行必须是 `IP 域名`，IP 合法。"""
    import ipaddress

    errors = []
    for n, line in enumerate((ROOT / "system/etc/hosts").read_text(encoding="utf-8").splitlines(), 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        parts = s.split()
        if len(parts) != 2:
            errors.append(f"  {n}: 字段数应为 2，实际 {len(parts)}: {s[:60]}")
            continue
        try:
            ipaddress.ip_address(parts[0])
        except ValueError:
            errors.append(f"  {n}: IP 非法: {parts[0]}")
        if "/" in parts[1] or parts[1].endswith("."):
            errors.append(f"  {n}: 域名形式可疑: {parts[1]}")
    if errors:
        print("hosts 校验失败：", file=sys.stderr)
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("hosts 校验通过")
    return 0


def main() -> int:
    if "--check" in sys.argv:
        return validate_hosts()
    DIST.mkdir(exist_ok=True)
    out = DIST / f"coloros_telemetry_blocker-v{module_version()}.zip"
    if out.exists():
        out.unlink()

    files = list(iter_files())
    missing = [name for name in ("module.prop", "system/etc/hosts") if not (ROOT / name).exists()]
    if missing:
        print(f"缺少必需文件: {', '.join(missing)}", file=sys.stderr)
        return 1

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for path, rel in files:
            info = zipfile.ZipInfo(rel)
            mode = 0o755 if rel in EXECUTABLE else 0o644
            info.external_attr = (0o100000 | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, path.read_bytes())

    domains = sum(
        1 for line in (ROOT / "system/etc/hosts").read_text(encoding="utf-8").splitlines()
        if line.startswith("0.0.0.0 ")
    )
    print(f"打包完成: {out}")
    print(f"  文件 {len(files)} 个, hosts {domains} 条域名, 大小 {out.stat().st_size} 字节")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

