#!/usr/bin/env python3
"""Run offline/loopback regressions. Never install packages or apply host policy."""
from pathlib import Path
import argparse
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-shellcheck', action='store_true')
    args = parser.parse_args()
    scripts = sorted(p for p in ROOT.rglob('*.sh') if '.git' not in p.parts)
    commands = [['bash', '-n', str(p.relative_to(ROOT))] for p in scripts]
    commands += [['bash', '-n', str(p.relative_to(ROOT))] for p in sorted((ROOT / 'bash/conf').iterdir())]
    commands += [['bash', str(p.relative_to(ROOT))] for p in sorted((ROOT / 'tests').glob('*-smoke.sh'))]
    commands += [[sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-v']]
    if shutil.which('shellcheck'):
        commands += [['shellcheck', '--severity=error', *[str(p.relative_to(ROOT)) for p in scripts]]]
    elif args.require_shellcheck:
        print('FAIL: ShellCheck is required.', file=sys.stderr)
        return 1
    else:
        print('SKIP: ShellCheck unavailable (required in CI).')
    failures = 0
    for command in commands:
        print('+ ' + ' '.join(command), flush=True)
        try:
            result = subprocess.run(command, cwd=ROOT, timeout=90, check=False)
            failures += int(result.returncode != 0)
        except (subprocess.TimeoutExpired, OSError) as error:
            print(f'FAIL: {error}', file=sys.stderr)
            failures += 1
    print(f'{len(commands) - failures}/{len(commands)} checks passed.')
    return int(failures != 0)


if __name__ == '__main__':
    raise SystemExit(main())
