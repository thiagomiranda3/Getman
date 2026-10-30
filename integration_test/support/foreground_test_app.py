"""Activate only the already-running app built in this test checkout."""
import pathlib
import subprocess
import sys
import time

app = pathlib.Path(sys.argv[1]).resolve()
executable = str(app / 'Contents' / 'MacOS' / 'getman')
for _ in range(180):
    commands = subprocess.check_output(['ps', '-axo', 'command='], text=True)
    if executable in commands.splitlines():
        result = subprocess.run(['open', '-a', str(app)], check=False,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode == 0:
            break
    time.sleep(0.5)
