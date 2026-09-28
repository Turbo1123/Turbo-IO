"""Apply the public cue-card/TWK1 overlay chain to a temp candidate and test its runtime."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[4]
BASE = REPO / 'firmware-research/strix-1.0.4.12/native-navigation/focus/src/official-addon/research'
CUE = REPO / 'firmware-research/strix-1.0.4.12/native-navigation/cue-cards/prepare_menu13.py'
PREPARE = Path(__file__).with_name('prepare.py')
MENU = Path(__file__).with_name('prepare_menu14.py')
RUNTIME_TEST = Path(__file__).with_name('test_runtime.c')
VIEW_TEST = Path(__file__).with_name('test_view.c')


def run(command):
    result = subprocess.run(command, text=True, capture_output=True)
    if result.stdout.strip():
        print(result.stdout.strip())
    if result.returncode:
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        raise SystemExit(result.returncode)


def main():
    with tempfile.TemporaryDirectory(prefix='turbo-twk-overlay-test-') as temp:
        root = Path(temp)
        for name in ('navigation-runtime-v1', 'focus-v1', 'music-runtime-v1', 'weread-v1'):
            shutil.copytree(BASE / name, root / name)
        shutil.copy2(BASE / 'build-image-rx-candidate.py', root / 'build-image-rx-candidate.py')
        for script in (CUE, PREPARE, MENU):
            run([sys.executable, str(script), '--source', str(root)])

        runtime = root / 'navigation-runtime-v1'
        service = (runtime / 'nav_service.c').read_text()
        assert '"turbo-navigation.tnv",wn[]="turbo-workout.twk"' in service
        assert 'memcmp(f->data,workout?"TWK1":"TNV1",4)' in service
        assert 'if(r->active&&is_workout!=r->scene.workout)' in (runtime / 'nav_runtime.c').read_text()
        menu_source = (root / 'music-runtime-v1/menu10.c').read_text()
        assert 'return index==13?"TurboWorkout":index==12?"TurboCueCards"' in menu_source
        assert "native-fourteen-TFP1-CUE-TWK1" in (root / 'build-image-rx-candidate.py').read_text()

        binary = root / 'twk-runtime-tests'
        run(['cc', '-std=c11', '-O2', str(runtime / 'nav_runtime.c'), str(RUNTIME_TEST),
             '-I', str(runtime), '-o', str(binary)])
        run([str(binary)])
        view_binary = root / 'twk-view-tests'
        run(['cc', '-std=c11', '-O2', str(runtime / 'nav_view.c'), str(runtime / 'nav_visual.c'),
             str(VIEW_TEST), '-I', str(runtime), '-o', str(view_binary)])
        run([str(view_binary)])
    print('PASS cue-card -> TWK1 firmware overlay application, distinct file/magic routing, 14-item menu wiring, native protocol regression, and mock workout UI; no firmware image or device used.')


if __name__ == '__main__':
    main()
