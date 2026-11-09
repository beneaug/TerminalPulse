"""Exercise only isolated installer fragments, never installation or services."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

INSTALLER = Path(__file__).resolve().parents[2] / "install.sh"


class InstallerTests(unittest.TestCase):
    def test_local_checkout_detection_does_not_depend_on_repository_name(self):
        source = INSTALLER.read_text().split("# Legacy paths", 1)[0]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo = root / "arbitrary name"
            (repo / "server").mkdir(parents=True)
            (repo / "server" / "main.py").write_text("# fixture")
            script = repo / "install.sh"
            script.write_text(source + '\nprintf "%s\\n%s\\n" "$RUNNING_FROM_REPO" "$INSTALL_DIR"\n')
            result = subprocess.run(["bash", str(script)], text=True, capture_output=True, check=True)
            self.assertEqual(result.stdout.splitlines(), ["1", str(repo / "server")])
            # A path containing the historic internal name does not prove that
            # it contains source files. It must still use the download path.
            other = root / "TerminalPulse-downloader"
            other.mkdir()
            script = other / "install.sh"
            script.write_text(source + '\nprintf "%s\\n" "$RUNNING_FROM_REPO"\n')
            result = subprocess.run(["bash", str(script)], text=True, capture_output=True, check=True,
                                    env={**os.environ, "HOME": str(root / "home")})
            self.assertEqual(result.stdout.strip(), "0")

    @unittest.skipUnless(shutil.which("zsh"), "zsh is needed to exercise its optional hook")
    def test_shell_hook_excludes_command_and_session_text_by_default(self):
        source = INSTALLER.read_text()
        fragment = "  _tmuxonwatch_preexec_hook() {" + source.split("  _tmuxonwatch_preexec_hook() {", 1)[1].split("  autoload -Uz", 1)[0]
        harness = '''
_tmuxonwatch_notify_flush() { :; }
_tmuxonwatch_notify_send() { printf '%s\\n' "$1" "$2" "$3"; }
tmux() { printf 'private-session:1:private-window'; }
export TMUX=fixture TMUX_PANE=%42
'''
        harness += fragment + '''
_tmuxonwatch_preexec_hook 'login --password example-secret'
true
_tmuxonwatch_precmd_hook
'''
        for opt_in in ("0", "1"):
            result = subprocess.run(["zsh", "-f", "-c", harness], text=True, capture_output=True, check=True,
                                    env={**os.environ, "TP_NOTIFY_INCLUDE_COMMAND": opt_in})
            lines = result.stdout.splitlines()
            self.assertEqual(len(lines), 3)
            self.assertNotIn("example-secret", lines[0])
            self.assertNotIn("private-session", lines[0])
            if opt_in == "0":
                self.assertNotIn("example-secret", result.stdout)
                self.assertNotIn("private-session", result.stdout)
                self.assertIn("Command finished (exit 0", lines[2])
            else:
                self.assertIn("example-secret", lines[2])
