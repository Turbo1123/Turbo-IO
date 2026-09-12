#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

// Exact, visually reviewed documentation captures, not a blanket PNG exclusion.
const reviewedScreenshots = new Map([
  ['docs/screenshots/app-home.png', 'ec995e6a4212b0f39c2114369f7264200c13fe84e81210fca34cf8cfbb7d41d9'],
  ['docs/screenshots/app-tools.png', '8d0ae97490dea2d772196ca529b3a9fb82dc4966d66ad1ab8ea4e5ef1befa2e1'],
  ['docs/screenshots/web-chat.png', '61d132ff1b925e158560b3c11aa27f6403be5d6d8a71c5e6fff547cbbc104423'],
  ['docs/screenshots/web-menu.png', '62d9a269e8119d99b30ae7a6592544f9279d53d552d9a8b08baa0d2eee4af3dd'],
]);

// Reviewed Norman IO branding exports; changed bytes require fresh review.
const reviewedBrandingAssets = new Map([
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-ios-marketing-1024@1x.png",
    "b80e82dcc0ea93e7672401d52512ff339824078d9148a25989e09a88fdc15935"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-ipad-20@1x.png",
    "db6656f381f02743165b2a3006483573522edc6cb463f67c0408592f259ece71"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-ipad-20@2x.png",
    "0063ce62de0f6385ea4c5cd527b407f72dd383634cfe384457abb9453109c4fd"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-ipad-29@1x.png",
    "f66c8323d09baad96c7c6588e94b61b20f747cd7332ac2cb8f1bbdad1ee269d1"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-ipad-29@2x.png",
    "7096ebdcd54411379be04cb11018b21865c365cb83741bec09656a8c5e07c328"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-ipad-40@1x.png",
    "0063ce62de0f6385ea4c5cd527b407f72dd383634cfe384457abb9453109c4fd"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-ipad-40@2x.png",
    "f4f56e1bf627337a07a38d24025477c884a51b8487f139fb1b37fab7bc42f08a"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-ipad-76@1x.png",
    "1e477d1f48e72980e972ec8e68ee2ba7b68ce5e0b69b418782a367051e7583eb"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-ipad-76@2x.png",
    "cfe5a869391ba6098c0d964150498fb3d97bd0fb4f66f848afe12a83346aa168"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-ipad-83.5@2x.png",
    "dd1f42418b4789a0c60f4502e16ef97e865d5e25cde8ec094ba2ef80027438d9"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-iphone-20@2x.png",
    "0063ce62de0f6385ea4c5cd527b407f72dd383634cfe384457abb9453109c4fd"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-iphone-20@3x.png",
    "449e06214026ff7b1f759c3034c708c06bc10c4a026438b74eb340f5efd38dc0"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-iphone-29@2x.png",
    "7096ebdcd54411379be04cb11018b21865c365cb83741bec09656a8c5e07c328"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-iphone-29@3x.png",
    "b25c9d7e674d4e3d0e273791a078896e1709e3a6838fbbe428ab9a38fad005a1"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-iphone-40@2x.png",
    "f4f56e1bf627337a07a38d24025477c884a51b8487f139fb1b37fab7bc42f08a"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-iphone-40@3x.png",
    "0cbfe8881a1e05408ae34f66fdffc47d58c0a2e1121c16c62894177eba1b5fb3"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-iphone-60@2x.png",
    "0cbfe8881a1e05408ae34f66fdffc47d58c0a2e1121c16c62894177eba1b5fb3"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/AppIcon.appiconset/icon-iphone-60@3x.png",
    "0adcd5bad9bd18798926e0c9daae33817b96631a9be263e6d64441d03aafcf98"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/NormanIOMark.imageset/norman-io-mark@1x.png",
    "c952cf5f7be45586f131bf6835c00496355ea7b4701af260c3e60d042fceaa5f"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/NormanIOMark.imageset/norman-io-mark@2x.png",
    "0f5746e1ce2098377ccb70c6cc9be2600bdfbd8d201f0bbb63735783cc272411"
  ],
  [
    "apps/RayNeoCompanion/Resources/Assets.xcassets/NormanIOMark.imageset/norman-io-mark@3x.png",
    "91a57ad87aadf47879db9afde127d5f19ee6b6205e4039fabd70dfb7989a47c8"
  ],
  [
    "design/branding/norman-io-master.png",
    "b80e82dcc0ea93e7672401d52512ff339824078d9148a25989e09a88fdc15935"
  ],
  [
    "design/branding/norman-io.ico",
    "5ebb4c7d63a337537d05fa542a5598c9e63185b2c71717c0cd7a3630eebea87e"
  ]
]);

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
    if(reviewedBrandingAssets.has(relative)){
      const digest=createHash('sha256').update(fs.readFileSync(p)).digest('hex');
      if(digest!==reviewedBrandingAssets.get(relative))findings.push({file:relative,rule:'branding-needs-privacy-review'});
      return;
    }
    if(reviewedScreenshots.has(relative)){
      const digest=createHash('sha256').update(fs.readFileSync(p)).digest('hex');
      if(digest!==reviewedScreenshots.get(relative))findings.push({file:relative,rule:'screenshot-needs-privacy-review'});
      return;
    }
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
