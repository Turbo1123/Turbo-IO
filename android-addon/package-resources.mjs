// Mechanical transformation of a private, locally supplied 1.0.5 APK derivative.
// Resource rule (2026-09-20 stage fix): never trust apktool's Windows filesystem
// layout for res/. Official res/* files and resources.arsc are copied as raw ZIP
// entries with exact case-sensitive names, bytes, method, CRC and sizes. Missing,
// extra or changed resources fail the build. Other reviewed entries remain intact.
import fs from 'node:fs';
import zlib from 'node:zlib';


export function isResourceName(name) {
  return name==='resources.arsc' || (name.startsWith('res/') && !name.endsWith('/'));
}

export function storedEntry(name,data) {
  const body=Buffer.from(data);
  return {name,versionNeeded:20,flags:0,method:0,modTime:0,modDate:0,crc:crc32(body),compSize:body.length,size:body.length,external:0,data:body};
}

function deflatedEntry(name,data) {
  const body=Buffer.from(data);
  const compressed=zlib.deflateRawSync(body,{level:9});
  return {name,versionNeeded:20,flags:0,method:8,modTime:0,modDate:0,crc:crc32(body),compSize:compressed.length,size:body.length,external:0,data:compressed};
}

export function readZipEntries(input) {
  const zip=readZip(input);
  return zip.order.map(name=>zip.entries.get(name));
}

export function writeZipEntries(entries) {
  return zipBuffer(entries);
}

export function addStoredFile(input,name,data) {
  const zip=readZip(input);
  const entries=zip.order.filter(existing=>existing!==name).map(existing=>zip.entries.get(existing));
  entries.push(storedEntry(name,data));
  return zipBuffer(entries);
}

export function restoreOfficialResources(officialInput,builtInput,addon) {
  const official=readZip(officialInput);
  const built=readZip(builtInput);
  const resources=official.order.map(name=>official.entries.get(name)).filter(entry=>entry && isResourceName(entry.name));
  const base=built.order.map(name=>built.entries.get(name)).filter(entry=>entry && !isResourceName(entry.name) && !(addon && entry.name===addon.name));
  const finalEntries=[...base,...resources];
  if(addon) finalEntries.push(deflatedEntry(addon.name,addon.data));
  return zipBuffer(finalEntries);
}

export function compareOfficialResources(officialInput,finalInput) {
  const official=readZip(officialInput);
  const finalZip=readZip(finalInput);
  const names=official.order.filter(isResourceName);
  const wanted=new Set(names);
  const missing=[];
  const unauthorized=[];
  const different=[];
  for(const name of names) {
    if(!finalZip.entries.has(name)) missing.push(name);
  }
  for(const name of finalZip.order.filter(isResourceName)) {
    const expected=official.entries.get(name);
    const got=finalZip.entries.get(name);
    if(!wanted.has(name)) { unauthorized.push(name); continue; }
    if(got.crc!==expected.crc || got.size!==expected.size || got.method!==expected.method
        || Buffer.compare(got.data, expected.data)!==0) {
      unauthorized.push(name);
      different.push(name);
    }
  }
  return {officialCount:names.length,finalCount:names.length-missing.length,missing,unauthorized,different,caseSensitive:true};
}

function readZip(input) {
  const buf=Buffer.isBuffer(input)?input:fs.readFileSync(input);
  const eocd=findEocd(buf);
  const count=buf.readUInt16LE(eocd+10);
  const centralSize=buf.readUInt32LE(eocd+12);
  const centralOffset=buf.readUInt32LE(eocd+16);
  if(centralOffset+centralSize>buf.length) throw new Error('Bad central directory');
  const entries=new Map();
  const order=[];
  let p=centralOffset;
  for(let i=0;i<count;i++) {
    if(buf.readUInt32LE(p)!==0x02014b50) throw new Error('Bad central entry');
    const versionNeeded=buf.readUInt16LE(p+6);
    const flags=buf.readUInt16LE(p+8);
    const method=buf.readUInt16LE(p+10);
    const modTime=buf.readUInt16LE(p+12);
    const modDate=buf.readUInt16LE(p+14);
    const crc=buf.readUInt32LE(p+16)>>>0;
    const compSize=buf.readUInt32LE(p+20);
    const size=buf.readUInt32LE(p+24);
    const nameLen=buf.readUInt16LE(p+28);
    const extraLen=buf.readUInt16LE(p+30);
    const commentLen=buf.readUInt16LE(p+32);
    const external=buf.readUInt32LE(p+38);
    const localOffset=buf.readUInt32LE(p+42);
    const name=buf.slice(p+46,p+46+nameLen).toString('utf8');
    if(buf.readUInt32LE(localOffset)!==0x04034b50) throw new Error('Bad local entry: '+name);
    const localNameLen=buf.readUInt16LE(localOffset+26);
    const localExtraLen=buf.readUInt16LE(localOffset+28);
    const dataOffset=localOffset+30+localNameLen+localExtraLen;
    if(dataOffset+compSize>buf.length) throw new Error('Bad entry data: '+name);
    if(entries.has(name)) throw new Error('Duplicate ZIP entry in source: '+name);
    entries.set(name,{name,versionNeeded,flags,method,modTime,modDate,crc,compSize,size,external,data:buf.slice(dataOffset,dataOffset+compSize)});
    order.push(name);
    p+=46+nameLen+extraLen+commentLen;
  }
  return {entries,order};
}

function findEocd(buf) {
  const min=Math.max(0,buf.length-22-65536);
  for(let p=buf.length-22;p>=min;p--) if(buf.readUInt32LE(p)===0x06054b50) return p;
  throw new Error('EOCD not found');
}

function zipBuffer(entries) {
  const chunks=[];
  const central=[];
  let offset=0;
  const seen=new Set();
  for(const entry of entries) {
    if(seen.has(entry.name)) throw new Error('Duplicate output entry: '+entry.name);
    seen.add(entry.name);
    const name=Buffer.from(entry.name,'utf8');
    const flags=entry.flags & ~0x08;
    const local=Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50,0);
    local.writeUInt16LE(entry.versionNeeded||20,4);
    local.writeUInt16LE(flags,6);
    local.writeUInt16LE(entry.method,8);
    local.writeUInt16LE(entry.modTime||0,10);
    local.writeUInt16LE(entry.modDate||0,12);
    local.writeUInt32LE(entry.crc>>>0,14);
    local.writeUInt32LE(entry.compSize,18);
    local.writeUInt32LE(entry.size,22);
    local.writeUInt16LE(name.length,26);
    local.writeUInt16LE(0,28);
    chunks.push(local,name,entry.data);
    const head=Buffer.alloc(46);
    head.writeUInt32LE(0x02014b50,0);
    head.writeUInt16LE(20,4);
    head.writeUInt16LE(entry.versionNeeded||20,6);
    head.writeUInt16LE(flags,8);
    head.writeUInt16LE(entry.method,10);
    head.writeUInt16LE(entry.modTime||0,12);
    head.writeUInt16LE(entry.modDate||0,14);
    head.writeUInt32LE(entry.crc>>>0,16);
    head.writeUInt32LE(entry.compSize,20);
    head.writeUInt32LE(entry.size,24);
    head.writeUInt16LE(name.length,28);
    head.writeUInt16LE(0,30);
    head.writeUInt16LE(0,32);
    head.writeUInt16LE(0,34);
    head.writeUInt16LE(0,36);
    head.writeUInt32LE(entry.external||0,38);
    head.writeUInt32LE(offset,42);
    central.push(head,name);
    offset+=30+name.length+entry.data.length;
  }
  const centralSize=central.reduce((n,part)=>n+part.length,0);
  const eocd=Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50,0);
  eocd.writeUInt16LE(entries.length,8);
  eocd.writeUInt16LE(entries.length,10);
  eocd.writeUInt32LE(centralSize,12);
  eocd.writeUInt32LE(offset,16);
  return Buffer.concat([...chunks,...central,eocd]);
}

let CRC_TABLE=null;
function crc32(data) {
  if(!CRC_TABLE) {
    CRC_TABLE=new Uint32Array(256);
    for(let n=0;n<256;n++) {
      let c=n;
      for(let k=0;k<8;k++) c=(c&1)?(0xedb88320^(c>>>1)):(c>>>1);
      CRC_TABLE[n]=c>>>0;
    }
  }
  let crc=0xffffffff;
  for(let i=0;i<data.length;i++) crc=CRC_TABLE[(crc^data[i])&0xff]^(crc>>>8);
  return (crc^0xffffffff)>>>0;
}
