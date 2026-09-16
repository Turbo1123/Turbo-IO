// Synthetic official JSON-RPC peer. This never loads the owner's Hermes profile.
import {createInterface} from 'node:readline';
const scenario=process.argv[2]||'normal', sessions=new Map();
const send=value=>process.stdout.write(JSON.stringify(value)+'\n');
const emit=(session_id,type,payload={})=>send({jsonrpc:'2.0',method:'event',params:{session_id,type,payload}});
let sequence=0;
if(scenario==='no-ready') setTimeout(()=>process.exit(4),40);
else setTimeout(()=>emit('', 'gateway.ready',{private:'CONFIG MUST NOT ESCAPE'}),10);
if(scenario==='oversize') setTimeout(()=>process.stdout.write('x'.repeat(4097)),20);
for await(const line of createInterface({input:process.stdin})) {
  const r=JSON.parse(line), p=r.params||{}, s=sessions.get(p.session_id);
  const reply=result=>send({jsonrpc:'2.0',id:r.id,result});
  const error=()=>send({jsonrpc:'2.0',id:r.id,error:{code:4009,message:'OWNER SECRET MUST NOT ESCAPE'}});
  if(r.method==='session.create'||r.method==='session.resume') {
    if(p.source!=='norman-io'||p.close_on_disconnect!==false) {error();continue;}
    const session_id='session-'+(++sequence), stored_session_id=p.session_id||'stored-'+sequence;
    const state={session_id,stored_session_id,ready:false,running:false,run_thread_alive:false,prompts:[]};
    sessions.set(session_id,state);
    reply({session_id,stored_session_id,session_key:stored_session_id,info:{lazy:true}});
    if(scenario!=='stop-before-ready')setTimeout(()=>{state.ready=true;emit(session_id,'session.info',{running:false,tools:{terminal:['terminal']},skills:{private:'skill body'},model:'private-model'});},20);
  } else if(r.method==='io.status') {
    if(!s){error();continue;}
    if(scenario==='status-timeout') continue;
    if(scenario==='status-once-timeout'&&s.text&&!s.skippedStatus){s.skippedStatus=true;continue;}
    const snapshot={ready:s.ready,failed:false,running:s.running,run_thread_alive:s.run_thread_alive,pending_prompt_ids:s.prompts.map(x=>x.id),stored_session_id:s.stored_session_id};
    if(s.text==='late-prompt'&&!s.latePrompt){s.latePrompt=true;s.prompts=[{id:'late-question'}];emit(s.session_id,'clarify.request',{request_id:'late-question',question:'A newly arrived question?',choices:['a']});}
    if(scenario==='stop-before-ready'&&s.stoppedBeforeReady)setTimeout(()=>reply(snapshot),35);
    else reply(snapshot);
  } else if(r.method==='prompt.submit') {
    if(!s?.ready||s.running) {error();continue;}
    if(p.text==='rpc-error') {error();continue;}
    s.running=true;s.run_thread_alive=true;s.text=p.text;
    if(p.text==='rpc-timeout') continue;
    reply({status:'streaming'});
    emit(p.session_id,'message.start');
    emit('foreign-session','message.delta',{text:'FOREIGN CHAT'});
    emit(p.session_id,'thinking.delta',{text:'PRIVATE REASONING'});
    emit(p.session_id,'reasoning.delta',{text:'PRIVATE REASONING'});
    emit(p.session_id,'agent.terminal.output',{chunk:'RAW TERMINAL SECRET'});
    emit(p.session_id,'status.update',{kind:'tool',text:'RAW COMMAND TOKEN'});
    emit(p.session_id,'tool.start',{name:'terminal',args:{secret:'TOOL ARGS'}});
    if(p.text==='crash') {setTimeout(()=>process.exit(9),20);continue;}
    if(p.text==='long'||p.text==='rpc-timeout'||p.text==='late-prompt') continue;
    if(p.text==='prompt'||p.text==='local') {
      const prompts=p.text==='prompt' ? [{id:'approve-1',type:'approval.request',command:'echo review-me',description:'Run command'},{id:'approve-2',type:'approval.request',command:'echo second'},{id:'clarify-1',type:'clarify.request',question:'Which file?',choices:['one','two']}] : [{id:'secret-1',type:'secret.request',prompt:'PRIVATE SECRET LABEL',env_var:'PRIVATE_KEY'}];
      s.prompts=prompts;
      for(const prompt of prompts)emit(p.session_id,prompt.type,{...prompt,request_id:prompt.id});
      continue;
    }
    if(p.text==='expired') {
      s.prompts=[{id:'clarify-expired'}];
      emit(p.session_id,'clarify.request',{request_id:'clarify-expired',question:'Choose',choices:['a']});
      setTimeout(()=>{s.prompts=[];},25);continue;
    }
    setTimeout(()=>{
      if(p.text==='failed')emit(p.session_id,'error',{message:'SECRET RUNTIME ERROR'});
      else if(p.text==='status-error')emit(p.session_id,'message.complete',{text:'SECRET PROVIDER ERROR',status:'error',reasoning:'PRIVATE REASONING'});
      else {emit(p.session_id,'message.delta',{text:'Hello ',rendered:'SECRET'});emit(p.session_id,'message.complete',{text:'Hello world',status:'complete',reasoning:'PRIVATE REASONING',usage:{secret:1}});}
      s.running=false;emit(p.session_id,'session.info',{running:false,tools:{terminal:['terminal']}});
      setTimeout(()=>{s.run_thread_alive=false;},60);
    },10);
  } else if(r.method==='session.interrupt') {
    if(!s){error();continue;}
    if(scenario==='stop-before-ready'&&!s.ready){
      // Deterministically release initialization only AFTER stop is received.
      // An interrupt on an idle official session emits no message.complete.
      s.ready=true;s.stoppedBeforeReady=true;reply({status:'interrupted'});continue;
    }
    reply({status:'interrupted'});s.prompts=[];
    setTimeout(()=>{emit(p.session_id,'message.complete',{status:'interrupted',text:''});s.running=false;},20);
    setTimeout(()=>{s.run_thread_alive=false;},60);
  } else if(r.method==='approval.respond'||r.method==='clarify.respond') {
    if(!s||s.prompts[0]?.id!==p.request_id){error();continue;}
    if(r.method==='approval.respond'&&!['once','deny'].includes(p.choice)){error();continue;}
    s.prompts.shift();reply(r.method==='approval.respond'?{resolved:1}:{status:'ok'});
  } else if(r.method==='session.history') {
    if(!s){error();continue;}
    if(scenario==='stop-before-ready'){reply({messages:s.text?[{role:'user',text:s.text}]:[]});continue;}
    reply({messages:[{role:'system',text:'SYSTEM SECRET'},{role:'user',text:'question\n\n[Norman IO request: uuid]'},{role:'assistant',text:'Checking',tool_calls:true,reasoning:'HIDDEN'},{role:'tool',context:'RAW TOOL'},{role:'assistant',text:'Answer',tool_calls:false,reasoning_details:'HIDDEN'}]});
  } else if(r.method==='session.close') {sessions.delete(p.session_id);reply({closed:true});}
  else error();
}
