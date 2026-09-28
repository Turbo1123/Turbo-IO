// Read and embed an explicitly supplied, already signed watch companion.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';

// codesign --deep on the app does not verify Xcode's root-level Debug dylibs.
// Device dyld rejects an unsigned one even when installation and outer verification pass.
export function verifyCueWatchCode(source,team,run=(program,args)=>execFileSync(program,args,{stdio:['pipe','pipe','pipe']})) {
  const magic=new Set(['cffaedfe','cefaedfe','feedfacf','feedface','cafebabe','bebafeca','cafebabf','bfbafeca']);
  const checked=[];
  const visit=directory=>{
    for(const entry of fs.readdirSync(directory,{withFileTypes:true})) {
      const file=path.join(directory,entry.name);
      if(entry.isDirectory())visit(file);
      else if(entry.isFile()) {
        const fd=fs.openSync(file,'r'),header=Buffer.alloc(4);
        try{fs.readSync(fd,header,0,4,0);}finally{fs.closeSync(fd);}
        if(!magic.has(header.toString('hex')))continue;
        run('codesign',['--verify','--strict','-R','=anchor apple generic and certificate leaf[subject.OU] = '+JSON.stringify(team),file]);
        checked.push(file);
      }
    }
  };
  visit(source);
  if(!checked.length)throw Error('watch_has_no_signed_executable');
  return checked;
}

export function validateCueWatchMetadata(info,entitlements,companion,team,parentInfo) {
  const bundle=info.CFBundleIdentifier;
  const cueBundle=companion+'.cuecards.watchkitapp';
  const combinedBundle=companion+'.watchkitapp';
  const combined=Boolean(info.NSHealthShareUsageDescription)&&entitlements['com.apple.developer.healthkit']===true;
  if((bundle!==cueBundle&&!(combined&&bundle===combinedBundle))||info.WKCompanionAppBundleIdentifier!==companion||info.WKApplication!==true)
    throw Error('watch_companion_identity_mismatch');
  if(!team||entitlements['com.apple.developer.team-identifier']!==team||
     entitlements['application-identifier']!==team+'.'+bundle)
    throw Error('watch_team_or_entitlements_mismatch');
  if(parentInfo&&(info.CFBundleVersion!==parentInfo.CFBundleVersion||
     info.CFBundleShortVersionString!==parentInfo.CFBundleShortVersionString))
    throw Error('watch_companion_version_mismatch');
  if(info.NSHealthShareUsageDescription&&entitlements['com.apple.developer.healthkit']!==true)
    throw Error('watch_healthkit_entitlement_required');
}
export function prepareCueWatch(source,companion,team,parentInfo) {
  if(!source)return null;
  if(!path.isAbsolute(source)||!source.endsWith('.app')||!fs.statSync(source).isDirectory())throw Error('invalid_watch_app');
  const run=(program,args)=>execFileSync(program,args,{encoding:'utf8',stdio:['pipe','pipe','pipe']});
  run('codesign',['--verify','--deep','--strict',source]);
  verifyCueWatchCode(source,team);
  const info=JSON.parse(run('plutil',['-convert','json','-o','-',path.join(source,'Info.plist')]));
  const entitlementXML=run('codesign',['-d','--entitlements',':-',source]);
  const entitlements=JSON.parse(execFileSync('python3',['-c','import sys,plistlib,json;print(json.dumps(plistlib.loads(sys.stdin.buffer.read())))'],{input:entitlementXML,encoding:'utf8'}));
  validateCueWatchMetadata(info,entitlements,companion,team,parentInfo);
  const profile=JSON.parse(run('python3',['-c',
    'import sys,subprocess,plistlib,json; p=plistlib.loads(subprocess.check_output(["security","cms","-D","-i",sys.argv[1]],stderr=subprocess.DEVNULL)); print(json.dumps({"expires":p["ExpirationDate"].isoformat()+"Z","entitlements":p["Entitlements"]}))',
    path.join(source,'embedded.mobileprovision')]));
  if(!(Date.parse(profile.expires)>Date.now()))throw Error('watch_profile_expired');
  if(profile.entitlements['com.apple.developer.team-identifier']!==team)throw Error('watch_profile_team_mismatch');
  const allowed=profile.entitlements['application-identifier'];
  if(allowed!==entitlements['application-identifier']&&allowed!==team+'.*')throw Error('watch_profile_bundle_mismatch');
  if(entitlements['com.apple.developer.healthkit']===true&&profile.entitlements['com.apple.developer.healthkit']!==true)
    throw Error('watch_profile_healthkit_required');
  return source;
}
export function copyCueWatch(source,app) {
  if(!source)return;
  const destination=path.join(app,'Watch',path.basename(source));
  if(fs.existsSync(path.join(app,'Watch')))throw Error('existing_watch_companion_requires_review');
  fs.mkdirSync(path.dirname(destination));
  fs.cpSync(source,destination,{recursive:true,errorOnExist:true,force:false});
}
