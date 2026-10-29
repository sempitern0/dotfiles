"""Read-only and invalid entry points run detached, with disposable state paths."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class EntryPoints(unittest.TestCase):
    def run_script(self, *args):
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary) / 'state'
            result = subprocess.run(['bash', str(ROOT / 'bash_setup.sh'), *args],
                                    capture_output=True, text=True, timeout=15,
                                    start_new_session=True,
                                    env=dict(os.environ, XDG_STATE_HOME=str(state), NO_COLOR='1'))
            self.assertFalse(state.exists(), result.stdout + result.stderr)
            return result

    def test_readonly_modes_do_not_create_state(self):
        for mode in ('--help', '--plan', '--status'):
            with self.subTest(mode=mode):
                result = self.run_script(mode)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_invalid_modes_fail_before_state_creation(self):
        for args in (('--no-such-option',), ('--user',), ('--user=',),
                     ('--user', '--recommended'), ('--status', '--recommended'),
                     ('--desktop', '--user-only'), ()):
            with self.subTest(args=args):
                result = self.run_script(*args)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
