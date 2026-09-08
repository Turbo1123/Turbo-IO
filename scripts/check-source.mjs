#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

// Values are never printed. Regex scanning is a release gate, not a guarantee.
export function audit(root){
  const findings=[];let files=0;
  const rules=[
    ['api-key',/sk-[A-Za-z0-9_.-]{12,}/],
    ['private-key',/-----BEGIN (?:[A-Z ]+)?PRIVATE KEY-----/],
    ['private-home',/\/Users\/(?!YOUR_|example)[^/\s]+\//],
    ['dedicated-asr-tenant',/llm-[a-z0-9-]+\.[a-z0-9.-]*aliyuncs\.com/],
    ['dedicated-weather-tenant',/[a-z0-9]+\.re\.qweatherapi\.com/],
    ['embedded-credential',/(?:api[_-]?key|password|apiToken|access_token)\s*[:=]\s*["'][a-f0-9]{32,}["']/i],
    ['temporary-public-endpoint',/https:\/\/[a-z0-9-]+\.trycloudflare\.com/],
  ];
  function walk(p){
    const s=fs.lstatSync(p),relative=path.relative(root,p);
    if(s.isSymbolicLink()){findings.push({file:relative,rule:'symlink'});return;}
    if(s.isDirectory()){
      if(['.git','.build','node_modules','build'].includes(path.basename(p)))return;
      if(/\.(?:app|xcframework|xcresult)$/.test(p)){findings.push({file:relative,rule:'binary-bundle'});return;}
      for(const n of fs.readdirSync(p))walk(path.join(p,n));return;
    }
    files++;
    const dependency=/^core-probe\/Frameworks\/(?:RayneoNet|CocoaAsyncSocket|OpenSSL|RayneoLog|SwiftProtobuf|CocoaLumberjack|SSZipArchive)\.framework\//.test(relative) || relative==='core-probe/Vendor/opus-ios/libopus.a';
    if(dependency)return; // Explicit binary build dependencies; reviewed via the hash inventory.
    if(/\.(?:ipa|apk|a|o|dylib|so|p12|pem|key|mobileprovision|wav|ogg|pcm|mp3|m4a|png|jpg|zip|log|jsonl)$/i.test(p))findings.push({file:relative,rule:'non-source-artifact'});
    if(s.size>2*1024*1024){findings.push({file:relative,rule:'oversize-review'});return;}
    const b=fs.readFileSync(p);if(b.includes(0)){findings.push({file:relative,rule:'binary-content'});return;}
    b.toString('utf8').split('\n').forEach((line,i)=>{for(const [rule,re]of rules)if(re.test(line))findings.push({file:relative,line:i+1,rule});});
  }
  walk(root);return {files,findings};
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  const root=path.resolve(process.argv[2]||path.join(path.dirname(fileURLToPath(import.meta.url)),'..'));
  const result=audit(root);console.log(JSON.stringify(result,null,2));process.exitCode=result.findings.length?1:0;
}
