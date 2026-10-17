#!/usr/bin/env node
// Fetch only pinned public SDK archives, never an app, account or API key.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync as run} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const pins=[
  ['AMap_iOS_Navi_ALL.zip','https://a.amap.com/lbs/static/zip/AMap_iOS_Navi_ALL.zip','8264377eb68d414c046be96585957250cda15a7eabd16553842f53f98764f4b8'],
  ['search-9.8.1.zip','https://a.amap.com/lbs/static/zip/AMap_iOS_Search_Lib_V9.8.1.zip','d11e0b418319c74abf5228611f678b58130eac791e267d6d6e3e7ec9f41b2007'],
];
const args=process.argv.slice(2);let archives;
if(!args.includes('--accept-sdk-terms')){console.log('Read https://developer.amap.com/api/ios-navi-sdk/download and the SDK terms first. Then run: node official-addon/setup-amap.mjs --accept-sdk-terms [--archives-dir /absolute/downloaded-archives]');process.exit(2);}
for(let i=0;i<args.length;i++){if(args[i]==='--accept-sdk-terms')continue;if(args[i]==='--archives-dir'&&!archives&&args[i+1]&&path.isAbsolute(args[i+1]))archives=args[++i];else throw Error('Unknown or invalid option');}
const build=path.join(here,'build'),out=path.join(build,'amap-sdk');fs.mkdirSync(build,{recursive:true});
if(fs.existsSync(out))throw Error('SDK destination already exists; inspect it instead of overwriting');
const temp=fs.mkdtempSync(path.join(build,'amap-download-'));
function unzip(file,dest){const names=run('/usr/bin/unzip',['-Z1',file],{encoding:'utf8'}).split('\n').filter(Boolean);if(names.some(n=>n.startsWith('/')||n.split('/').includes('..')||n.includes('\\')))throw Error('Unsafe archive path');fs.mkdirSync(dest,{recursive:true});run('/usr/bin/unzip',['-q',file,'-d',dest]);}
for(const [name,url,hash] of pins){let file=archives?path.join(archives,name):path.join(temp,name);if(!archives)run('/usr/bin/curl',['--fail','--location','--proto','=https','--proto-redir','=https','--max-time','300','--output',file,url],{stdio:'inherit'});if(createHash('sha256').update(fs.readFileSync(file)).digest('hex')!==hash)throw Error('Pinned SDK hash mismatch; stop and review new SDK version');unzip(file,path.join(temp,name+'.contents'));}
const all=path.join(temp,'AMap_iOS_Navi_ALL.zip.contents','AMap_iOS_Navi_ALL');
unzip(path.join(all,'AMap_iOS_Foundation_Lib_V1.9.4_20260904.zip'),path.join(temp,'foundation'));
unzip(path.join(all,'AMap_iOS_Navi_Lib_V11.3.100.zip'),path.join(temp,'navi'));
function find(dir,name){let result=[];for(const e of fs.readdirSync(dir,{withFileTypes:true})){if(e.name==='__MACOSX')continue;const p=path.join(dir,e.name);if(e.isSymbolicLink())throw Error('Unexpected SDK symlink');if(e.isDirectory()){if(e.name===name)result.push(p);else result.push(...find(p,name));}}return result;}
const parts=[['navi','AMapNaviKit',path.join(temp,'navi')],['foundation','AMapFoundationKit',path.join(temp,'foundation')],['search','AMapSearchKit',path.join(temp,'search-9.8.1.zip.contents')]];
const staged=path.join(temp,'ready');for(const [part,name,dir] of parts){const matches=find(dir,name+'.framework');if(matches.length!==1)throw Error('Unexpected SDK layout');fs.mkdirSync(path.join(staged,part),{recursive:true});fs.cpSync(matches[0],path.join(staged,part,name+'.framework'),{recursive:true,errorOnExist:true,force:false});}
fs.renameSync(staged,out);console.log('Pinned Navi 11.3.100 / Foundation 1.9.4 / Search 9.8.1 installed into ignored build/amap-sdk. No Key configured.');
