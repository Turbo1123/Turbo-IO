import fs from 'node:fs';

export function wrapHostCallback(file,name,signature,args,returnMode) {
  let text=fs.readFileSync(file,'utf8');
  const original='turboioOriginal_'+name;
  const header='.method public final '+name+signature;
  // Replace our generated wrapper on repeated builds, retain the original body.
  if(text.includes(original+'(')) {
    const start=text.indexOf(header+'\n');
    if(start<0)throw new Error('Generated wrapper missing');
    const end=text.indexOf('.end method',start);
    text=text.slice(0,start)+text.slice(end+'.end method'.length);
  } else {
  if(text.split(header).length!==2) throw new Error('Method signature mismatch: '+name);
  text=text.replace(header,'.method public final '+original+signature);
  }
  const className=text.match(/^\.class[^\n]* (L[^;]+;)$/m)?.[1];
  if(!className) throw new Error('Class header missing');
  const invoke='invoke-virtual/range {'+args+'}, '+className+'->'+original+signature;
  const map={onAsrResult:'dispatchAsr(Ljava/lang/Object;Ljava/lang/String;ZLjava/lang/String;)V',
    onNlpResult:'dispatchNlp(Ljava/lang/Object;Ljava/lang/Object;)V',onResponseComplete:'dispatchComplete(Ljava/lang/Object;)V',
    onPostResume:'install(Landroid/app/Activity;)V',
    onNotificationPosted:'notificationPosted(Ljava/lang/Object;Landroid/service/notification/StatusBarNotification;)V',
    onNotificationRemoved:'notificationRemoved(Ljava/lang/Object;Landroid/service/notification/StatusBarNotification;)V'};
  // Observers run after the original and never affect it; the ASR/NLP hooks own dispatch instead.
  const after=['onPostResume','onNotificationPosted','onNotificationRemoved'].includes(name);
  if(!map[name])throw new Error('Unsupported callback: '+name);
  const bridge='invoke-static/range {'+args+'}, Lcom/turboio/addon/TurboAddon;->'+map[name];
  const body=!after
    ? `    :turboio_try\n    ${bridge}\n    :turboio_try_end\n    return-void\n    :turboio_error\n    move-exception v0\n    ${invoke}\n    return-void`
    : `    ${invoke}\n    :turboio_try\n    ${bridge}\n    :turboio_try_end\n    return-void\n    :turboio_error\n    move-exception v0\n    return-void`;
  text+='\n'+header+'\n    .locals 1\n'+body+'\n    .catch Ljava/lang/Throwable; {:turboio_try .. :turboio_try_end} :turboio_error\n.end method\n';
  fs.writeFileSync(file,text);
}
