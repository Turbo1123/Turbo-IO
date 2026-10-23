// Version-scoped wrapper generators, testable without rewriting a real APK.
export function wrapExact(text,header,original,body){
 if(text.includes(original+'(')){
  const start=text.indexOf(header+'\n');if(start<0)throw new Error('Missing OTA wrapper');
  const end=text.indexOf('.end method',start);if(end<0)throw new Error('Truncated method');
  text=text.slice(0,start)+text.slice(end+11);
 }else{if(text.split(header).length!==2)throw new Error('OTA ABI mismatch');text=text.replace(header,header.replace(/ ([A-Za-z_][A-Za-z_0-9]*)\(/,' '+original+'('));}
 return text+'\n'+header+'\n'+body+'\n.end method\n';
}
export const OTA_106=Object.freeze({queueClass:'LX3/U;',senderClass:'LX3/u;',message:'LX3/Q;',core:'Lj4/q;',fileMethod:'u'});
export const OTA_107=Object.freeze({queueClass:'LY3/V;',senderClass:'LY3/u;',message:'LY3/S;',core:'Lk4/q;',fileMethod:'u'});
export function queueHook(text,abi){return wrapExact(text,'.method public static o('+abi.message+')V','turboioOriginal_o',`    .locals 1
    :ota_try
    invoke-static {p0}, Lcom/turboio/addon/OfficialOtaBridge;->allowQueue(Ljava/lang/Object;)Ljava/lang/Boolean;
    move-result-object v0
    if-eqz v0, :ota_preparation_policy
    invoke-virtual {v0}, Ljava/lang/Boolean;->booleanValue()Z
    move-result v0
    if-eqz v0, :ota_blocked
    goto :ota_end
    :ota_preparation_policy
    invoke-static {p0}, Lcom/turboio/addon/OfficialOtaPreparation;->allowQueue(Ljava/lang/Object;)Ljava/lang/Boolean;
    move-result-object v0
    if-eqz v0, :ota_legacy_policy
    invoke-virtual {v0}, Ljava/lang/Boolean;->booleanValue()Z
    move-result v0
    if-eqz v0, :ota_blocked
    goto :ota_end
    :ota_legacy_policy
    invoke-static {p0}, Lcom/turboio/addon/OtaController;->allowQueue(Ljava/lang/Object;)Z
    move-result v0
    if-eqz v0, :ota_blocked
    :ota_end
    invoke-static {p0}, ${abi.queueClass}->turboioOriginal_o(${abi.message})V
    return-void
    :ota_error
    move-exception v0
    :ota_blocked
    invoke-static {p0}, Lcom/turboio/addon/OtaController;->blocked(Ljava/lang/Object;)V
    return-void
    .catch Ljava/lang/Throwable; {:ota_try .. :ota_end} :ota_error`);}
export function fileHook(text,abi){const sig='(Ljava/io/File;Ljava/lang/String;'+abi.core+'Ljava/lang/String;)Ljava/lang/String;';return wrapExact(text,'.method public final '+abi.fileMethod+sig,'turboioOriginal_'+abi.fileMethod,`    .locals 1
    invoke-static {}, Lcom/turboio/addon/OfficialOtaBridge;->allowFile()Z
    move-result v0
    if-eqz v0, :ota_blocked
    invoke-static {}, Lcom/turboio/addon/OfficialOtaPreparation;->enabled()Z
    move-result v0
    if-nez v0, :ota_blocked
    invoke-static {}, Lcom/turboio/addon/OtaController;->allowFile()Z
    move-result v0
    if-eqz v0, :ota_blocked
    invoke-virtual/range {p0 .. p4}, ${abi.senderClass}->turboioOriginal_${abi.fileMethod}${sig}
    move-result-object v0
    return-object v0
    :ota_blocked
    new-instance v0, Ljava/lang/IllegalStateException;
    invoke-direct {v0}, Ljava/lang/IllegalStateException;-><init>()V
    throw v0`);}
export const EVENT_GUARD=`    :ota_event_try
    invoke-static {}, Lcom/turboio/addon/OfficialOtaBridge;->enabled()Z
    move-result v0
    if-eqz v0, :ota_event_preparation
    invoke-static {p1, p2}, Lcom/turboio/addon/OfficialOtaBridge;->observe(Ljava/lang/String;Ljava/util/Map;)V
    goto :ota_event_pass
    :ota_event_preparation
    invoke-static {}, Lcom/turboio/addon/OfficialOtaPreparation;->enabled()Z
    move-result v0
    if-nez v0, :ota_event_pass
    invoke-static {p1, p2}, Lcom/turboio/addon/OtaController;->consume(Ljava/lang/String;Ljava/util/Map;)Z
    move-result v0
    if-eqz v0, :ota_event_pass
    :ota_event_end
    return-void
    :ota_event_error
    move-exception v0
    return-void
    :ota_event_pass
    .catch Ljava/lang/Throwable; {:ota_event_try .. :ota_event_end} :ota_event_error
`;
