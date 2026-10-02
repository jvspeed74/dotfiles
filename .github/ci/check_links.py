#!/usr/bin/env python3
"""Checks the root Markdown docs.

Default: every relative link resolves (file exists, #anchor matches a heading), and every
backticked repo path (run_*, dot_*, .github/..., .chezmoitemplates/...) exists in the repo.
With --extract-mermaid DIR: writes each ```mermaid block to DIR/<doc>-L<line>.mmd instead.
Standard library only; prints FILE:LINE: problem and exits 1 on any failure.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
DOCS = sorted(ROOT.glob("*.md"))

LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)\)")
CODE = re.compile(r"`([^`\n]+)`")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*$")
REPO_PREFIX = re.compile(r"^(run_|dot_|create_|\.github/|\.chezmoitemplates/|jetbrains/)")
FILE_EXT = re.compile(r"\.(sh|tmpl|md|json|lua|ya?ml|py|toml)$")
PLACEHOLDER = set("*<>…{}$ ")


def lines_outside_fences(text):
    """Yield (line_number, line) for lines not inside fenced code blocks."""
    fenced = False
    for number, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith(("```", "~~~")):
            fenced = not fenced
            continue
        if not fenced:
            yield number, line


def slug(heading):
    """GitHub's heading anchor: lowercase, drop punctuation except - and _, spaces to hyphens."""
    heading = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading).replace("`", "").strip().lower()
    kept = "".join(ch for ch in heading if ch.isalnum() or ch in "-_ ")
    return kept.replace(" ", "-")


def anchors(path):
    seen = {}
    result = set()
    for _, line in lines_outside_fences(path.read_text()):
        match = HEADING.match(line)
        if not match:
            continue
        base = slug(match.group(2))
        count = seen.get(base, 0)
        seen[base] = count + 1
        result.add(base if count == 0 else f"{base}-{count}")
    return result


def looks_like_repo_path(token):
    if any(ch in PLACEHOLDER for ch in token) or not REPO_PREFIX.match(token):
        return False
    return "/" in token or bool(FILE_EXT.search(token))


def check():
    problems = []
    anchor_cache = {}
    for doc in DOCS:
        for number, line in lines_outside_fences(doc.read_text()):
            where = f"{doc.name}:{number}"
            for target in LINK.findall(line):
                if re.match(r"^[a-z]+:", target):
                    continue
                file_part, _, anchor = target.partition("#")
                path = (doc.parent / file_part).resolve() if file_part else doc
                if not path.exists():
                    problems.append(f"{where}: link target not found: {target}")
                    continue
                if anchor and path.suffix == ".md":
                    if path not in anchor_cache:
                        anchor_cache[path] = anchors(path)
                    if anchor not in anchor_cache[path]:
                        problems.append(f"{where}: anchor not found: {target}")
            for token in CODE.findall(line):
                if looks_like_repo_path(token) and not (ROOT / token).exists():
                    problems.append(f"{where}: repo path not found: {token}")
    return problems


def extract_mermaid(out_dir):
    out_dir = pathlib.Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    count = 0
    for doc in DOCS:
        block, start = None, 0
        for number, line in enumerate(doc.read_text().splitlines(), 1):
            if block is None and line.strip() == "```mermaid":
                block, start = [], number
            elif block is not None and line.strip() == "```":
                (out_dir / f"{doc.stem}-L{start}.mmd").write_text("\n".join(block) + "\n")
                block, count = None, count + 1
            elif block is not None:
                block.append(line)
    print(f"extracted {count} mermaid diagram(s)")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--extract-mermaid":
        extract_mermaid(sys.argv[2])
        sys.exit(0)
    found = check()
    for problem in found:
        print(problem)
    print(f"{len(DOCS)} doc(s) checked, {len(found)} problem(s)")
    sys.exit(1 if found else 0)
