import test from 'node:test';
import assert from 'node:assert/strict';
import {menuApps,menuFromPage,previewModel} from './public/app.js';
const state = page => ({connected:true,phase:'disabled',page});
test('seven apps match user order; no business message is a menu ID',()=>{
  assert.deepEqual(menuApps.map(a=>a.name),['录音','实时字幕','实时提示','待办','提词器','全天智记','勿扰模式']);
  assert.equal(menuFromPage({scene:1,index:7,app:'未知应用'}).index,6);
  assert.equal(menuFromPage({scene:2,business:14,type:1}).index,-1);
});
test('known app names win; index fallback is explicitly inferred',()=>{
  assert.deepEqual(menuFromPage({scene:1,index:1,app:'待办'}),{index:3,inferred:false});
  assert.deepEqual(menuFromPage({scene:1,index:2,app:'未知应用'}),{index:1,inferred:true});
  assert.equal(menuFromPage({scene:2,app:'字幕'}).index,1);
  for(const index of [0,8,1.5,'4']) assert.equal(menuFromPage({scene:1,index}).index,-1);
});
test('offline and exit never keep old page active',()=>{
  assert.equal(previewModel(null).kind,'unknown');
  assert.equal(previewModel({connected:false,page:{scene:1,index:4,at:1}}).kind,'unknown');
  assert.equal(previewModel(state({scene:2,app:'待办',action:2,at:1})).kind,'unknown');
  assert.equal(previewModel(state({scene:0})).kind,'unknown');
});
test('real page and explicit sample modes remain separate',()=>{
  assert.equal(previewModel(state({scene:0,at:1})).kind,'home');
  assert.equal(previewModel(state({scene:1,index:5,at:1})).index,4);
  for(const mode of ['home','chat','menu','notification']) {
    const p=previewModel(null,mode,6); assert.equal(p.demo,true); assert.match(p.source,/非实时/);
  }
});
test('voice-phase drawing is labeled app-side inference',()=>{
  const p=previewModel({connected:true,phase:'processing',page:{}});
  assert.equal(p.kind,'chat'); assert.match(p.source,/App/); assert.match(p.source,/非镜片确认/);
});
