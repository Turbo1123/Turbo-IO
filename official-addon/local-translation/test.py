"""Synthetic offline unit tests. No microphone, accounts, network or device."""
import subprocess
import tempfile
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE/'src'

def run(args):
    subprocess.run(list(map(str,args)),check=True)

def main():
    with tempfile.TemporaryDirectory(prefix='turbo-caption-tests-') as td:
        out = Path(td)
        for name,files in [('events',['RealtimeText','RealtimeTextTests']),
                           ('segments',['CaptionSegmenter','CaptionSegmenterTests']),
                           ('scheduler',['CaptionSegmenter','CaptionSchedulerTests'])]:
            exe = out/name
            # Do not use -O here: these tests deliberately rely on Swift assertions.
            run(['xcrun','swiftc','-swift-version','6','-parse-as-library',
                 *[SRC/(f+'.swift') for f in files],'-o',exe]);run([exe])
        fixture=out/'synthetic-silence.wav'
        with wave.open(str(fixture),'wb') as w:
            w.setnchannels(1);w.setsampwidth(2);w.setframerate(16000);w.writeframes(b'\0\0'*128000)
        exe=out/'capture'
        run(['xcrun','swiftc','-swift-version','6','-parse-as-library',
             *[SRC/(f+'.swift') for f in ['CaptionAudioPipeline','CaptionAudioPipelineProbe','CaptionAudioPipelineTests']],
             '-o',exe]);run([exe,fixture])
        exe=out/'hud'
        run(['xcrun','clang','-fobjc-arc','-fmodules','-fsanitize=address,undefined','-Wno-incompatible-pointer-types',
             '-framework','Foundation','-I',HERE,'-I',HERE.parent,HERE.parent/'TodoProtocol.m',
             HERE/'SubtitleHUDCore.m',HERE/'SubtitleHUDTests.m','-o',exe]);run([exe])
        run(['node','--test',HERE/'package-resources.test.mjs',HERE.parent/'package.test.mjs'])
    print('PASS synthetic tests; not ASR accuracy or physical glasses acceptance')

if __name__ == '__main__': main()
