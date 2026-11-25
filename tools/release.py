"""Publish a new version to GitHub: python tools/release.py 0.3 "what changed"

Sets the version in project.godot and the Android preset (bumping the
version code), builds the APK, commits, pushes, and makes a GitHub release
with the APK attached. Phones see it through the game's update button.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APK = os.path.join(ROOT, "build", "Warband.apk")


def edit(path, pattern, repl):
    full = os.path.join(ROOT, path)
    with open(full, encoding="utf-8") as f:
        text = f.read()
    new, n = re.subn(pattern, repl, text, count=1, flags=re.M)
    if n != 1:
        sys.exit(f"couldn't find {pattern!r} in {path}")
    with open(full, "w", encoding="utf-8", newline="") as f:
        f.write(new)


def run(*cmd):
    print(">", " ".join(cmd))
    subprocess.run(cmd, cwd=ROOT, check=True)


def main():
    if len(sys.argv) < 2 or not re.fullmatch(r"\d+(\.\d+)*", sys.argv[1]):
        sys.exit(__doc__)
    version = sys.argv[1]
    notes = sys.argv[2] if len(sys.argv) > 2 else f"Warband {version}"

    edit("project.godot", r'^config/version=".*"$', f'config/version="{version}"')
    edit("export_presets.cfg", r'^version/name=".*"$', f'version/name="{version}"')
    with open(os.path.join(ROOT, "export_presets.cfg"), encoding="utf-8") as f:
        code = int(re.search(r"^version/code=(\d+)$", f.read(), re.M).group(1))
    edit("export_presets.cfg", r"^version/code=\d+$", f"version/code={code + 1}")

    before = os.path.getmtime(APK) if os.path.exists(APK) else 0
    run("powershell", "-NoProfile", "-Command", "& '.\\build_apk.bat'")
    if not os.path.exists(APK) or os.path.getmtime(APK) <= before:
        sys.exit("the APK wasn't rebuilt")

    run("git", "add", "-A")
    trailer = os.environ.get("COMMIT_TRAILER", "")
    run("git", "commit", "-m", f"Release v{version}\n\n{notes}" + (f"\n\n{trailer}" if trailer else ""))
    run("git", "push")
    run("gh", "release", "create", f"v{version}", APK, "--title", f"Warband {version}", "--notes", notes)


if __name__ == "__main__":
    main()
