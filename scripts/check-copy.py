#!/usr/bin/env python3
"""Check only project-authored source/copy; user data and vendor licenses are excluded."""
from pathlib import Path
import sys
roots = [Path('Sources'), Path('docs')]
files = [Path('README.md'), Path('CONTRIBUTING.md')]
for root in roots:
    files.extend(p for p in root.rglob('*') if p.suffix in {'.swift', '.json', '.md'})
failures = []
for path in files:
    if not path.exists():
        continue
    for line, text in enumerate(path.read_text().splitlines(), 1):
        if '\u2014' in text:
            failures.append(f'{path}:{line}: replace em dash in project-authored copy')
print('\n'.join(failures) if failures else 'Project copy check passed.')
sys.exit(bool(failures))
