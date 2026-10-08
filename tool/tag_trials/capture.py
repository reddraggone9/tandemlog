"""Capture a standalone real GTK prototype; run inside xvfb-run/dbus-run-session.

Does not start the production application or open a profile. This harness has no
TaskStore or file transport. Sleeps are short frame/input settling intervals.
"""
import os
from pathlib import Path
import subprocess
import time

root = Path(__file__).resolve().parents[2]
output = root / "evidence/tag-autocomplete-trials/ui"
output.mkdir(parents=True, exist_ok=True)
private = Path('/workspace/recovery/tag-trials-runtime')
private.mkdir(parents=True, exist_ok=True)
env = dict(os.environ)
for key, child in [('XDG_CACHE_HOME', 'cache'), ('XDG_CONFIG_HOME', 'config'),
                   ('XDG_DATA_HOME', 'data')]:
    path = private / child
    path.mkdir(exist_ok=True)
    env[key] = str(path)

def run(*args):
    return subprocess.check_output(args, env=env, text=True).strip()

with (private / 'application.log').open('w') as log:
    app = subprocess.Popen([str(root / 'build/linux/x64/debug/bundle/tandemlog')],
                           env=env, stdout=log, stderr=log)
    try:
        window = ''
        for _ in range(100):
            found = subprocess.run(['xdotool', 'search', '--onlyvisible', '--name', '^tandemlog$'],
                                   env=env, text=True, capture_output=True)
            if found.returncode == 0:
                window = found.stdout.strip().splitlines()[-1]
                break
            time.sleep(.1)
        if not window:
            raise RuntimeError('No actual prototype GTK window appeared')
        run('xdotool', 'windowmove', window, '0', '0')
        run('xdotool', 'windowsize', window, '1000', '820')
        run('xdotool', 'windowfocus', window)
        time.sleep(1)
        def capture(name):
            time.sleep(1.2)
            run('import', '-window', window, str(output / f'{name}.png'))
        def click(x, y):
            run('xdotool', 'mousemove', '--window', window, str(x), str(y), 'click', '1')
            time.sleep(1.2)
        video_log = (private / 'video.log').open('w')
        recording = subprocess.Popen([
            'ffmpeg', '-y', '-f', 'x11grab', '-draw_mouse', '1', '-framerate', '15',
            '-video_size', '1000x820', '-i', env['DISPLAY'],
            '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
            str(output / 'tag-entry-linux-gtk-trials.mp4')],
            env=env, stdin=subprocess.PIPE, stdout=video_log, stderr=video_log)
        capture('a-1000-suggestions')
        # Real native desktop Enter selects the current suggestion.
        run('xdotool', 'key', '--window', window, 'Return')
        capture('a-1000-selected')
        click(535, 73)
        capture('b-1000-suggestions')
        run('xdotool', 'key', '--window', window, 'Return')
        capture('b-1000-selected')
        # Resize the same real desktop window; these are not Android captures.
        run('xdotool', 'windowsize', window, '390', '820')
        click(100, 73)
        capture('a-390-suggestions')
        run('xdotool', 'key', '--window', window, 'Return')
        capture('a-390-selected')
        click(285, 73)
        capture('b-390-suggestions')
        run('xdotool', 'key', '--window', window, 'Return')
        capture('b-390-selected')
        click(78, 111)
        capture('b-390-bulk')
        click(100, 73)
        capture('a-390-bulk')
        recording.communicate(input=b'q', timeout=10)
        video_log.close()
        if recording.returncode:
            raise RuntimeError('Prototype video recording failed')
        # Keep the process open for the parent capture controller if requested.
        print(f'GTK window {window}; standalone GTK comparison captured', flush=True)
        if os.environ.get('TAG_TRIAL_INTERACTIVE') == '1':
            for line in __import__('sys').stdin:
                parts = line.strip().split()
                if not parts:
                    continue
                if parts[0] == 'capture':
                    capture(parts[1])
                elif parts[0] == 'click':
                    click(int(parts[1]), int(parts[2]))
                elif parts[0] == 'size':
                    run('xdotool', 'windowsize', window, parts[1], parts[2])
                    time.sleep(.5)
                elif parts[0] == 'key':
                    run('xdotool', 'key', '--window', window, parts[1])
                    time.sleep(.25)
                elif parts[0] == 'text':
                    run('xdotool', 'type', '--window', window, ' '.join(parts[1:]))
                elif parts[0] == 'quit':
                    break
                print(f'done {parts[0]}', flush=True)
    finally:
        app.terminate()
        try:
            app.wait(timeout=5)
        except subprocess.TimeoutExpired:
            app.kill()
            app.wait()
