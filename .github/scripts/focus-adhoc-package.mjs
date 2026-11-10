// FOCUS-04 ad-hoc 打包辅助：复刻 official-addon/package.mjs 的 focus 分支，
// 供不走正式签名（package.mjs 需官方 Bundle ID）的 adhoc 流程使用。
// 用法：node .github/scripts/focus-adhoc-package.mjs \
//        <merged/Payload/Runner.app> <focus-firmware.zip> <amap-sdk-root> <routing-report.json>
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {patch as patchExperimentalOTA} from '../../firmware-research/strix-1.0.4.12/src/patch-ios105-ota-source.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const [appArg, fwArg, sdkArg, reportArg, candidateArg] = process.argv.slice(2);
if (process.argv.length !== 6 && process.argv.length !== 7)
  throw Error('Usage: focus-adhoc-package.mjs <Runner.app> <firmware.zip> <amap-sdk-root> <report.json> [candidate.json]');
const app = path.resolve(appArg), firmware = path.resolve(fwArg), sdkRoot = path.resolve(sdkArg), report = path.resolve(reportArg);
if (!app.endsWith('.app')) throw Error('use_app_input');
for (const p of [app, firmware, sdkRoot]) if (!path.isAbsolute(p)) throw Error('absolute_paths_required');

// 固件精确校验：传入候选描述时按其 zip.size/sha256 校验（TAP1 等任意候选），
// 否则回落到 package.mjs validateResearchPair 的 TFP1 规则。
const fw = fs.readFileSync(firmware);
const fwSha = () => createHash('sha256').update(fw).digest('hex');
if (candidateArg) {
  const cand = JSON.parse(fs.readFileSync(path.resolve(candidateArg), 'utf8'));
  if (fw.length !== cand.zip.size || fwSha() !== cand.zip.sha256)
    throw Error('candidate_firmware_identity_mismatch:' + cand.codeName);
} else if (fw.length !== 9300112
  || fwSha() !== 'ad5054e3d7bda90e94d293bea882bd8dd5a125bcc8f42c13a59b2e149313c9e3')
  throw Error('tfp1_firmware_identity_mismatch');

// 1. OTA 回环补丁：宿主 Flutter 二进制（补丁模块自带原始哈希自校验）
const appBin = path.join(app, 'Frameworks/App.framework/App');
const otaPatch = patchExperimentalOTA(fs.readFileSync(appBin));
fs.writeFileSync(appBin, otaPatch.output);

// 2. FOCUS 美术资源（目标不存在才拷，沿用 errorOnExist 语义）
fs.cpSync(path.join(root, 'official-addon/focus-edition/TurboIOArt'), path.join(app, 'TurboIOArt'), {recursive: true, errorOnExist: true, force: false});

// 3. 固件嵌入（沿用 package.mjs 的目标文件名）
fs.copyFileSync(firmware, path.join(app, 'TurboWeReadCandidate.zip'), fs.constants.COPYFILE_EXCL);

// 4. Info.plist 注入（等价 package.mjs focus 分支的 plutil 操作）
const plist = path.join(app, 'Info.plist');
const run = args => execFileSync('plutil', args, {stdio: 'pipe'});
const info = () => JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', plist], {encoding: 'utf8'}));
run(['-insert', 'TIOExperimentalOTAQueryRouting', '-string', 'ios105-tfp1-loopback-flash-gated', plist]);
run(['-insert', 'TIOExperimentalOTABuild', '-string', 'FOCUS-04-SOURCE', plist]);
// 音乐需要后台音频模式
let i = info();
if (!i.UIBackgroundModes) run(['-insert', 'UIBackgroundModes', '-json', '["audio"]', plist]);
else if (!i.UIBackgroundModes.includes('audio')) run(['-insert', 'UIBackgroundModes.0', '-string', 'audio', plist]);
// OTA 回环需要本地网络豁免
i = info();
if (!i.NSAppTransportSecurity) run(['-insert', 'NSAppTransportSecurity', '-dictionary', plist]);
i = info();
if (i.NSAppTransportSecurity?.NSAllowsLocalNetworking === undefined) run(['-insert', 'NSAppTransportSecurity.NSAllowsLocalNetworking', '-bool', 'YES', plist]);
// 高德定位用途说明
i = info();
if (!i.NSLocationWhenInUseUsageDescription) run(['-insert', 'NSLocationWhenInUseUsageDescription', '-string', '用于用户主动选择的地图定位和前台步行导航。', plist]);

// 5. 路由报告
fs.writeFileSync(report, JSON.stringify(otaPatch.report, null, 2) + '\n', {flag: 'wx', mode: 0o600});
console.log(JSON.stringify({ok: true, firmwareBytes: fw.length, routing: 'ios105-tfp1-loopback-flash-gated'}));
