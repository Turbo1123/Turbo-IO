import {open,lstat} from 'node:fs/promises';
import {constants} from 'node:fs';
export async function readTodoPhoneToken(path){
  const pre=await lstat(path);if(!pre.isFile()||pre.isSymbolicLink())throw Error('auth_not_configured');
  const file=await open(path,constants.O_RDONLY|constants.O_NOFOLLOW);
  try{const info=await file.stat();if(!info.isFile()||info.size>256||(info.mode&0o077)!==0)throw Error('auth_not_configured');const token=(await file.readFile('utf8')).trim();if(!/^[A-Za-z0-9_-]{32,128}$/.test(token))throw Error('auth_not_configured');return token;}finally{await file.close();}
}
