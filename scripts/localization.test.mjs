import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
const root = new URL('../', import.meta.url);
const catalog = () => JSON.parse(readFileSync(new URL('apps/RayNeoCompanion/Resources/Localizable.xcstrings', root), 'utf8'));
function swiftFiles(dir) {
  return readdirSync(dir,{withFileTypes:true}).flatMap(item => item.isDirectory() ? swiftFiles(join(dir,item.name)) : item.name.endsWith('.swift') ? [join(dir,item.name)] : []);
}
test('catalog has English base and complete Simplified Chinese translations',()=>{
 const data=catalog(); assert.equal(data.sourceLanguage,'en'); assert.ok(Object.keys(data.strings).length>100);
 for(const [key,entry] of Object.entries(data.strings)) {
  assert.ok(entry.localizations.en.stringUnit.value, key);
  assert.ok(entry.localizations['zh-Hans'].stringUnit.value, key);
  assert.equal(entry.localizations.en.stringUnit.state,'translated',key);
  assert.equal(entry.localizations['zh-Hans'].stringUnit.state,'translated',key);
 }
});
test('all explicit localization calls have catalog entries and matching format placeholders',()=>{
 const data=catalog();
 for(const file of swiftFiles(fileURLToPath(new URL('apps/RayNeoCompanion/Sources', root)))) {
  const source=readFileSync(file,'utf8');
  for(const match of source.matchAll(/L10n\.(?:text|format)\("((?:[^"\\]|\\.)*)"/g)) {
   const key=JSON.parse('"'+match[1]+'"'); assert.ok(data.strings[key],file+': '+key);
  }
 }
 for(const [key,entry] of Object.entries(data.strings)) {
  const placeholders=value=> [...value.matchAll(/%(?:\d+\$)?(?:@|lld|ld|d|f)/g)].map(m=>m[0]).sort();
  assert.deepEqual(placeholders(entry.localizations.en.stringUnit.value),placeholders(entry.localizations['zh-Hans'].stringUnit.value),key);
 }
});
test('language changes do not rebuild the root or change system language preferences',()=>{
 const source=readFileSync(new URL('apps/RayNeoCompanion/Sources/RayNeoCompanionApp.swift',root),'utf8');
 assert.ok(source.includes('.environment(\\.locale, languageSettings.locale)'));
 assert.ok(!source.includes('.id(language'));
 const settings=readFileSync(new URL('apps/RayNeoCompanion/Sources/App/Localization/AppLanguageSettings.swift',root),'utf8');
 assert.ok(!settings.includes('forKey: "AppleLanguages"'));
});
