import json, os, pathlib, subprocess, sys, time

root = pathlib.Path('/workspace/recovery/rc4-build47-linux-release-qa')
fixture = root / 'fixture'
manifest = json.loads((fixture / 'manifest.json').read_text())
profile = fixture / 'app-profile-2'
profile.mkdir(exist_ok=True)
if not (profile / 'settings.json').exists():
    (profile / 'settings.json').write_text(json.dumps({'folder': str(fixture / 'shared'), 'user': manifest['user'], 'appearance': 'dark'}))
(root / 'display.txt').write_text(os.environ['DISPLAY'])
env = dict(os.environ, TANDEMLOG_PROFILE=str(profile), GSETTINGS_BACKEND='memory')
env.pop('TANDEMLOG_TEXT_LIBRARY', None)
with (root / 'release-app.txt').open('ab') as log:
    app = subprocess.Popen(['/workspace/tandemlog-rc4-build47/build/linux/x64/release/bundle/tandemlog'], env=env, stdout=log, stderr=subprocess.STDOUT)
    try:
        for attempt in range(100):
            found = subprocess.run(['xdotool', 'search', '--onlyvisible', '--name', '^tandemlog$'], text=True, capture_output=True)
            if found.returncode == 0:
                break
            time.sleep(.1)
        else:
            raise RuntimeError('Native release window did not appear')
        window = found.stdout.strip().splitlines()[-1]
        (root / 'window.txt').write_text(window)
        subprocess.run(['xdotool', 'windowmove', window, '0', '0'], check=True)
        subprocess.run(['xdotool', 'windowsize', window, '390', '820'], check=True)
        subprocess.run(['xsetroot', '-cursor_name', 'left_ptr'], check=True)
        print(json.dumps({'window': window, 'display': os.environ['DISPLAY'], 'build': 'source4434440 release47', 'synthetic_profile': str(profile)}), flush=True)
        for line in sys.stdin:
            if line.strip() == 'quit':
                break
            command = json.loads(line)
            result = subprocess.run(command['argv'], text=True, capture_output=True)
            print(json.dumps({'returncode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}), flush=True)
    finally:
        app.terminate()
        try:
            app.wait(timeout=10)
        except subprocess.TimeoutExpired:
            app.kill()
            app.wait()
