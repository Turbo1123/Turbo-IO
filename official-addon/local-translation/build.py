"""Build original iOS translation module from explicit pinned local dependencies.
No model downloads, account access, developer signing, installation or firmware I/O.
"""
import argparse
import json
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE / 'src'
LLAMA = '1e411d8f5a1e23525fa3265dfb4bd76265465397'
FLUID = 'eabcd9e36dab48f1f7180165396d84b9688650e0'

def run(args):
    subprocess.run(list(map(str, args)), check=True)

def pinned(folder, revision):
    actual = subprocess.check_output(['git', '-C', str(folder), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != revision:
        raise ValueError('Wrong dependency revision')
    for args in (['diff', '--quiet'], ['diff', '--cached', '--quiet']):
        run(['git', '-C', folder, *args])

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--llama', type=Path, required=True)
    p.add_argument('--fluid', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args()
    llama, fluid, out = a.llama.resolve(), a.fluid.resolve(), a.out.resolve()
    if out.exists():
        raise ValueError('Use a new output directory; existing output is preserved')
    pinned(llama, LLAMA); pinned(fluid, FLUID)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
    out.mkdir(parents=True)
    native = out / 'native'
    run(['cmake', '-S', SRC, '-B', native, '-DHYMT_LLAMA_SOURCE='+str(llama),
         '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_SYSTEM_NAME=iOS', '-DCMAKE_OSX_SYSROOT=iphoneos',
         '-DCMAKE_OSX_ARCHITECTURES=arm64', '-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0'])
    run(['cmake', '--build', native, '-j', '6'])
    run(['xcrun', 'swift', 'build', '--package-path', fluid, '--scratch-path', out/'fluid',
         '--configuration', 'release', '--build-system', 'swiftbuild', '--triple', 'arm64-apple-ios26.0',
         '--sdk', sdk, '--disable-default-traits', '--target', 'FluidAudio'])
    matches = list((out/'fluid').rglob('Release-iphoneos/FluidAudio.o'))
    if len(matches) != 1:
        raise ValueError('Unexpected FluidAudio build layout')
    products = matches[0].parent
    libs = [native/'libTurboHyMT.a', native/'llama-build/src/libllama.a']
    libs += [native/('llama-build/ggml/src/lib'+n+'.a') for n in ('ggml', 'ggml-cpu', 'ggml-base')]
    units = ['RealtimeText', 'LocalTranslation', 'HyMTLocalTranslation', 'CaptionTranslationRouter',
             'LocalTranslationPanel', 'HyMTPerformanceProbe', 'CaptionAudioPipeline', 'MicrophoneInput',
             'ParakeetSpeech', 'OfflineCaptionPanel', 'CaptionSegmenter']
    run(['xcrun', '--sdk', 'iphoneos', 'swiftc', '-swift-version', '6', '-O', '-parse-as-library',
         '-import-objc-header', SRC/'HyMTBridge.h', '-target', 'arm64-apple-ios26.0', '-sdk', sdk,
         '-I', products, '-I', fluid/'Sources/FastClusterWrapper/include',
         '-I', fluid/'Sources/MachTaskSelfWrapper/include', '-emit-library', '-module-name', 'TurboCaptionTranslation',
         *[SRC/(u+'.swift') for u in units], *[products/(u+'.o') for u in ('FluidAudio','FastClusterWrapper','MachTaskSelfWrapper')],
         *libs, '-lc++', '-framework', 'Accelerate', '-framework', 'CoreML', '-framework', 'AVFoundation',
         '-Xlinker', '-install_name', '-Xlinker', '@rpath/TurboCaptionTranslation.dylib',
         '-o', out/'TurboCaptionTranslation.dylib'])
    shutil.copytree(products/'FluidAudio_FluidAudio.bundle', out/'FluidAudio_FluidAudio.bundle')
    shutil.copytree(HERE/'licenses', out/'licenses')
    (out/'build-info.json').write_text(json.dumps({'version':'LOCAL-TRANSLATION-SOURCE-01',
        'llama':LLAMA, 'fluid':FLUID, 'minimumIOS':'26.0', 'deviceValidated':False,
        'signedWithDeveloperIdentity':False, 'modelsIncluded':False}, indent=2)+'\n')
    print('Built unsigned/local module. No device or firmware operations.')

if __name__ == '__main__':
    main()
