#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

// Exact, visually reviewed documentation captures, not a blanket PNG exclusion.
const reviewedScreenshots = new Map([
  ['firmware-research/strix-1.0.4.12/assets/turbo-photo-on-glasses.png', 'fc40e716e30ad8817aa27482e497b7ab7f23f77b03c884ef3533b2df0b96a49c'], // Owner-authorized glasses photo; EXIF/XMP removed, IDAT pixels unchanged, visually reviewed.
  ['firmware-research/strix-1.0.4.12/assets/turbo-photo.png', '47031ca47ddb044cedc6af2146018556954572311e2dfd58e807354e7ac17251'], // Owner-provided original color illustration; EXIF removed, pixels unchanged; presentation only.
  ['firmware-research/strix-1.0.4.12/assets/turbo-photo-firmware.png', '738169867ec0ca778cd6ce14e803aaa508bf16f8e169d1081db3e622d571db24'], // Exact embedded portrait, owner explicitly authorized publication; deterministic rebuild input.
  ['harmony-sdk/entry/src/main/resources/base/media/rayneo_home_hero.png', '426720b141311bc859bc59f31763790250a898ef974708d0e69e4841180c51b1'], // Reviewed synthetic glasses illustration, no account/device screenshot.
  ['official-addon/docs/home-tabs-glass-light.png', '12c74fe54a48d2f6b4b5371381f7308732f8b35b07465ecf29728f33dbc969b4'],
  ['official-addon/docs/home-tabs-glass-dark.png', '2f14655122697a4dd0870147fb6bf71417f8dfea82a45670443e2dd1e13c9407'],
  ['official-addon/docs/navigation-search.png', 'd6a4dcb745bd87e67884fa686d87d033d9b557bd70a31cea4fc8098f7935245c'],
  ['official-addon/docs/model-preview.png', '01e013c04f3b0841e4a7ef1ca83af89585154f562c23cfa71698ede373eb4f79'],
  ['official-addon/docs/knowledge-preview.png', 'bb7acde21eddf1c5f83eb02b48cddf2228ad913796fe76f8f5187297a49eb5e7'],
  ['official-addon/docs/profile-preview.png', '567cad6092cc82c543f2c01061615a2ae5e4f491bfd486ee11669dffb5db91b6'],
  ['docs/screenshots/app-home.png', 'ec995e6a4212b0f39c2114369f7264200c13fe84e81210fca34cf8cfbb7d41d9'],
  ['docs/screenshots/app-tools.png', '8d0ae97490dea2d772196ca529b3a9fb82dc4966d66ad1ab8ea4e5ef1befa2e1'],
  ['docs/screenshots/web-chat.png', '61d132ff1b925e158560b3c11aa27f6403be5d6d8a71c5e6fff547cbbc104423'],
  ['docs/screenshots/web-menu.png', '62d9a269e8119d99b30ae7a6592544f9279d53d552d9a8b08baa0d2eee4af3dd'],
]);
// Exact upstream Opus generated weight tables. Still scan their text for credentials.
const reviewedLargeSources = new Map([
  ['core-probe/Vendor/opus-1.5.2/dnn/dred_rdovae_dec_data.c','639d15d2644043d4fec7442e9f46b51ab19f639420e7d57859609c6ecdb24abf'],
  ['core-probe/Vendor/opus-1.5.2/dnn/dred_rdovae_enc_data.c','2831f195a9a2a6d937084bb49b65e6beabb270ac16a08c20721775fc6cac04b5'],
  ['core-probe/Vendor/opus-1.5.2/dnn/fargan_data.c','a1939c859a41f4352ad427fa0fa3348306fdd6cfd64a9bf6493bae96b322d323'],
  ['core-probe/Vendor/opus-1.5.2/dnn/nolace_data.c','5df145d3850d48a89eb27a8512970fde76a401ebf19055f2d7c29213aef7ef04'],
]);

// Previously published synthetic ANIM60 frames and their exact L8 build input.
// Hash-pinned exceptions only: no blanket media or binary exclusion.
const animationAssets='firmware-research/strix-1.0.4.12/native-navigation/src/official-addon/research/animation-runtime-v1/assets/';
const reviewedAnimationAssets=new Map([
  ['anime-idle-atlas-v1.png','c64ceebed83e304631ca45e7751a82d77f379120f399d30f521715ce37b0642d'],
  ['encoded-v1/anime-idle-192x176-l8.bin','f758dd6e3cdf5fc6550238df26e46111e9d45d098b9d95f649626ea58210ee1d'],
  ['encoded-v1/frame-00.png','901283e8d2641c391d05634a85697f55648207c2c3df58104834f3549c5695bc'],
  ['encoded-v1/frame-01.png','3eb3b50e7182348b33ecb1c8824de22a469468b3c33f97dc79cb8bb62f4d64a9'],
  ['encoded-v1/frame-02.png','741e0cb1f1701da5a06f90ded24fbdb1e987ad8d4fd2b0924e270487bcde6ba3'],
  ['encoded-v1/frame-03.png','d64fce0e575cff7b7efb50244cebf7dad3f20b050115a23c309c3b6be79a60d7'],
  ['encoded-v1/frame-04.png','3ae2970a21e3b6d4cd111bc4c002f007bf06a8703c6a2ed68f7e13e374b922ee'],
  ['encoded-v1/frame-05.png','16b6c0a664387ddca5c0b0b309c63657a1a8c3af454cdbc7f2214748b3921ac0'],
  ['encoded-v1/frame-06.png','452d4c9e55d01649f5043252b64dd54e3ea4445178e8f816796015f602776d2e'],
  ['encoded-v1/frame-07.png','a0ea2ea913fe2f904a573d15ebcbd4fe81e6a79a7685f410dbfb0ffc19ebcfe0'],
  ['encoded-v1/frame-08.png','4f74c831706df25c0620231096c881c578ab263d11fb38fbad8becd78f55ed2a'],
  ['encoded-v1/frame-09.png','451b42738d292026e7d6581c565b3026af09336132bc48f85f27bd9397f5c85e'],
  ['encoded-v1/frame-10.png','f78140ce949619405c17d97f3b4d3fd6d1e7a64971604807d23a9d1809a4c8b8'],
  ['encoded-v1/frame-11.png','e69a80814c8674b5f915bbdbf69f4ba6634ea6f3ce08b7636d03519489639764'],
  ['encoded-v1/preview-approx-8fps.gif','4d64a763ee9e34634bfa7b4713287429d97173b51fdc55262f947c3cc345402f'],
].map(([p,h])=>[animationAssets+p,h]));

// Values are never printed. Regex scanning is a release gate, not a guarantee.
// Explicit reviewed FOCUS-04 art and byte-identical copies of public animation assets.
const focusReview=JSON.parse(fs.readFileSync(new URL('./focus-reviewed-assets.json',import.meta.url),'utf8'));
for(const [p,h] of Object.entries(focusReview.media))reviewedScreenshots.set(p,h);
for(const [p,h] of Object.entries(focusReview.largeText))reviewedLargeSources.set(p,h);
// Hash-pinned Android release assets. Gallery ZIP contents are independently
// inspected by android-addon/tests/PrivateArtifactAudit.py; no blanket exemption.
const androidReview=JSON.parse(fs.readFileSync(new URL('./android-release-reviewed-assets.json',import.meta.url),'utf8'));
for(const [p,h] of Object.entries(androidReview.files))reviewedScreenshots.set(p,h);
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
    if(path.basename(p)==='.git')return; // Also support Git worktree pointer files.
    const s=fs.lstatSync(p),relative=path.relative(root,p);
    if(s.isSymbolicLink()){findings.push({file:relative,rule:'symlink'});return;}
    if(s.isDirectory()){
      if(['.git','.build','node_modules','build','__pycache__'].includes(path.basename(p)))return;
      if(/\.(?:app|xcframework|xcresult)$/.test(p)){findings.push({file:relative,rule:'binary-bundle'});return;}
      for(const n of fs.readdirSync(p))walk(path.join(p,n));return;
    }
    files++;
    if(reviewedAnimationAssets.has(relative)){
      if(createHash('sha256').update(fs.readFileSync(p)).digest('hex')!==reviewedAnimationAssets.get(relative))findings.push({file:relative,rule:'animation-asset-needs-review'});
      return;
    }
    if(reviewedScreenshots.has(relative)){
      const digest=createHash('sha256').update(fs.readFileSync(p)).digest('hex');
      if(digest!==reviewedScreenshots.get(relative))findings.push({file:relative,rule:'screenshot-needs-privacy-review'});
      return;
    }
    const dependency=/^core-probe\/Frameworks\/(?:RayneoNet|CocoaAsyncSocket|OpenSSL|RayneoLog|SwiftProtobuf|CocoaLumberjack|SSZipArchive)\.framework\//.test(relative) || relative==='core-probe/Vendor/opus-ios/libopus.a';
    if(dependency)return; // Explicit binary build dependencies; reviewed via the hash inventory.
    if(/\.(?:ipa|apk|hap|har|app|dex|jar|jks|keystore|a|o|dylib|so|p12|p7b|cer|pem|key|mobileprovision|wav|ogg|pcm|mp3|m4a|png|jpg|zip|log|jsonl)$/i.test(p))findings.push({file:relative,rule:'non-source-artifact'});
    if(relative==='harmony-sdk/build-profile.json5')findings.push({file:relative,rule:'local-signing-config'});
    if(s.size>2*1024*1024 && (!reviewedLargeSources.has(relative)||createHash('sha256').update(fs.readFileSync(p)).digest('hex')!==reviewedLargeSources.get(relative))){findings.push({file:relative,rule:'oversize-review'});return;}
    const b=fs.readFileSync(p);if(b.includes(0)){findings.push({file:relative,rule:'binary-content'});return;}
    b.toString('utf8').split('\n').forEach((line,i)=>{for(const [rule,re]of rules){
      // One synthetic host in mocked HTTP tests; still scan the rest of that line.
      const checked=rule==='dedicated-weather-tenant' && relative==='harmony-sdk/tests/remote-services.test.mjs'
        ? line.replaceAll("'test." + "re.qweatherapi.com'", "'mock-weather-host'") : line;
      if(re.test(checked))findings.push({file:relative,line:i+1,rule});
    }});
  }
  walk(root);return {files,findings};
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  const root=path.resolve(process.argv[2]||path.join(path.dirname(fileURLToPath(import.meta.url)),'..'));
  const result=audit(root);console.log(JSON.stringify(result,null,2));process.exitCode=result.findings.length?1:0;
}
