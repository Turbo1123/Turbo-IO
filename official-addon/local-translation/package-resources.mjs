// Explicit local build resources only. No automatic downloads, credentials or signing.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync as exec} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
export function validateTranslationPair(symbols, options) {
  const enabled=symbols.includes('_TIOOpenLocalTranslation');
  const module=options['translation-module-dir'], models=options['translation-models'];
  if(enabled!==Boolean(module)||enabled!==Boolean(models))throw Error('translation_addon_resources_must_match');
  if(enabled&&(!path.isAbsolute(module)||!path.isAbsolute(models)))throw Error('translation_absolute_paths_required');
}
export function prepareTranslationResources(options) {
  if(!options['translation-module-dir'])return null;
  const module=options['translation-module-dir'], models=options['translation-models'];
  const info=JSON.parse(fs.readFileSync(path.join(module,'build-info.json')));
  if(info.version!=='LOCAL-TRANSLATION-SOURCE-01'||info.llama!=='1e411d8f5a1e23525fa3265dfb4bd76265465397'||info.fluid!=='eabcd9e36dab48f1f7180165396d84b9688650e0')throw Error('translation_build_revision_mismatch');
  const dylib=path.join(module,'TurboCaptionTranslation.dylib');
  // Swift internal @objc classes are local symbols but registered with ObjC runtime.
  const symbols=exec('nm',[dylib],{encoding:'utf8',maxBuffer:64*1024*1024});
  if(!symbols.includes('_OBJC_CLASS_$_TIOCaptionLocalPanel')||!symbols.includes('_OBJC_CLASS_$_TIOCaptionHost'))throw Error('translation_module_symbols_missing');
  exec('python3',[path.join(here,'models.py'),'--out',models,'--verify-only'],{stdio:'pipe'});
  return {module,models,dylib};
}
export function copyTranslationResources(resources, app) {
  if(!resources)return;
  const {module,models,dylib}=resources;
  for(const target of ['Frameworks/TurboCaptionTranslation.dylib','TurboCaptionModels','FluidAudio_FluidAudio.bundle','TurboCaptionLicenses']) {
    if(fs.existsSync(path.join(app,target)))throw Error('translation_resources_already_present_use_clean_input');
  }
  fs.copyFileSync(dylib,path.join(app,'Frameworks/TurboCaptionTranslation.dylib'));
  fs.cpSync(path.join(module,'FluidAudio_FluidAudio.bundle'),path.join(app,'FluidAudio_FluidAudio.bundle'),{recursive:true});
  fs.cpSync(path.join(module,'licenses'),path.join(app,'TurboCaptionLicenses'),{recursive:true});
  const dest=path.join(app,'TurboCaptionModels');fs.mkdirSync(dest);
  fs.copyFileSync(path.join(models,'Hy-MT2-1.8B-STQ43.gguf'),path.join(dest,'Hy-MT2-1.8B-STQ43.gguf'));
  const manifest=JSON.parse(fs.readFileSync(path.join(here,'parakeet-manifest.json')));
  for(const entry of [...manifest.files,{path:'manifest.json'}]) {
    const target=path.join(dest,'ParakeetEOU320',entry.path);fs.mkdirSync(path.dirname(target),{recursive:true});
    fs.copyFileSync(path.join(models,'ParakeetEOU320',entry.path),target);
  }
}
