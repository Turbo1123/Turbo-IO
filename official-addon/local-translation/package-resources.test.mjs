import test from 'node:test';
import assert from 'node:assert/strict';
import {validateTranslationPair} from './package-resources.mjs';
test('translation entry and explicit local resources are paired',()=>{
  validateTranslationPair('',{});
  const options={'translation-module-dir':'/example/module','translation-models':'/example/models'};
  validateTranslationPair('_TIOOpenLocalTranslation',options);
  assert.throws(()=>validateTranslationPair('',options));
  assert.throws(()=>validateTranslationPair('_TIOOpenLocalTranslation',{}));
  assert.throws(()=>validateTranslationPair('_TIOOpenLocalTranslation',{'translation-module-dir':'/example/module'}));
  assert.throws(()=>validateTranslationPair('_TIOOpenLocalTranslation',{...options,'translation-models':'relative'}));
});
