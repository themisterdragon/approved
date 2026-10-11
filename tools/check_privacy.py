#!/usr/bin/env python3
"""Refuse to commit anything personal.

Runs from .githooks/pre-commit on the staged files, or on every tracked file
with --all. Checks text and binary files (image and audio metadata too) for:
  - home-folder paths (home or Users folder names)
  - email addresses other than GitHub noreply ones
  - the words in .git/info/banned-words (one regex per line). That list
    lives inside .git, so it is never committed or pushed.
It also refuses a commit whose author or committer isn't a noreply address.
"""
import os, re, subprocess, sys

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                      check=True).stdout.strip()
GENERIC = [rb"/home/[A-Za-z0-9_.-]+", rb"/Users/[A-Za-z0-9_.-]+", rb"[A-Za-z]:\\\\?Users\\\\?[A-Za-z0-9_.-]+"]
EMAIL = re.compile(rb"[A-Za-z0-9_.+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b")  # (a version like name@1.5.4 is not one)
EMAIL_OK = re.compile(rb"(@users\.noreply\.github\.com|@anthropic\.com|@example\.(com|org))$")
SKIP = {"LICENSE"}  # the GPL text itself


def is_license(path):
    return os.path.basename(path).endswith("-OFL.txt")  # font designers' contact emails


def is_vendored(path):
    return path.endswith(".min.js")  # third-party minified code: its email-like strings are code, not emails


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, check=True).stdout


def banned():
    path = os.path.join(ROOT, ".git", "info", "banned-words")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [l.strip().encode() for l in f if l.strip() and not l.startswith("#")]


def files(all_files):
    if all_files:
        out = git("ls-files", "-z")
    else:
        out = git("diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z")
    return [f.decode() for f in out.split(b"\0") if f]


def blob(path, all_files):
    if all_files:
        with open(os.path.join(ROOT, path), "rb") as f:
            return f.read()
    return git("show", f":{path}")  # the staged version, not the working copy


def main():
    all_files = "--all" in sys.argv
    problems = []
    if not all_files:
        for var in ("GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"):
            ident = git("var", var).decode()
            if "@users.noreply.github.com" not in ident:
                problems.append(f"{var} is not a noreply address (pass -c user.name/user.email)")
    words = banned()
    patterns = [re.compile(p) for p in GENERIC + words]
    # short words (2-3 letters) turn up by chance in compressed bytes, so binaries skip them
    long_patterns = [re.compile(p) for p in GENERIC + words if len(re.sub(rb"\\b", b"", p)) > 3]
    for path in files(all_files):
        if path in SKIP:
            continue
        data = blob(path, all_files)
        binary = b"\0" in data
        for pat in long_patterns if binary else patterns:
            for m in pat.finditer(data):
                line = data.count(b"\n", 0, m.start()) + 1
                problems.append(f"{path}:{line}: matches {pat.pattern.decode()}")
        if binary or is_license(path) or is_vendored(path):
            continue  # fonts carry their designers' emails
        for m in EMAIL.finditer(data):
            if not EMAIL_OK.search(m.group()):
                line = data.count(b"\n", 0, m.start()) + 1
                problems.append(f"{path}:{line}: email address")
    if problems:
        sys.exit("privacy check failed:\n  " + "\n  ".join(problems))
    print("privacy check passed")


if __name__ == "__main__":
    main()
