package com.turboio.addon;

import java.io.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.zip.*;

/** One reviewed candidate, not an arbitrary firmware loader. All pins, sizes
 * and hashes come from the held OtaCandidate descriptor; no extracted paths.
 * Without a descriptor every entry throws: fail closed. */
final class OtaPackage {
 private final Map<String,byte[]> members;
 private OtaPackage(Map<String,byte[]> members){this.members=members;}
 static OtaCandidate candidate(){return OtaCandidate.require();}
 static String hash(String algorithm,byte[] bytes){try{byte[] h=MessageDigest.getInstance(algorithm).digest(bytes);StringBuilder out=new StringBuilder();for(byte v:h)out.append(String.format(Locale.ROOT,"%02x",v&255));return out.toString();}catch(Exception e){throw new IllegalStateException("digest unavailable");}}
 static OtaPackage verify(byte[] zip)throws IOException{
  OtaCandidate c=candidate();
  if(zip==null||zip.length!=c.zipSize||!c.zipSHA.equals(hash("SHA-256",zip)))throw new IOException("仅接受已审核 "+c.codeName+" 原样 ZIP，大小或 SHA-256 不符");
  Map<String,OtaCandidate.Pin> pins=c.pins;
  Map<String,byte[]> files=new HashMap<>();int total=0;
  try(ZipInputStream in=new ZipInputStream(new ByteArrayInputStream(zip))){ZipEntry e;while((e=in.getNextEntry())!=null){OtaCandidate.Pin pin=pins.get(e.getName());if(pin==null||e.isDirectory()||files.containsKey(e.getName()))throw new IOException("ZIP member");byte[] data=new byte[pin.size];int at=0,n;while(at<pin.size&&(n=in.read(data,at,pin.size-at))!=-1)at+=n;if(at!=pin.size||in.read()!=-1||!pin.sha256.equals(hash("SHA-256",data)))throw new IOException("member size/hash");total+=pin.size;if(total>19000000)throw new IOException("expanded budget");files.put(e.getName(),data);in.closeEntry();}}
  if(files.size()!=pins.size())throw new IOException("missing member");
  try{List<Object> rows=BoundedJson.list(BoundedJson.read(files.get(c.manifestName)));if(rows.size()!=pins.size()-1)throw new IllegalArgumentException();Set<String> found=new HashSet<>();
   for(Object value:rows){Map<String,Object> row=BoundedJson.map(value);BoundedJson.keys(row,"Name","Size","Md5","BurnMode","BurnAddr","BurnPath");String name=BoundedJson.text(row.get("Name"),64);byte[] bytes=files.get(name);if(bytes==null||name.equals(c.manifestName)||!found.add(name)||BoundedJson.number(row.get("Size"),1,c.apSize)!=bytes.length||!hash("MD5",bytes).equals(row.get("Md5")))throw new IllegalArgumentException();if(name.equals(c.apName)&&c.restore!=null){row.put("Size",c.restore.apSize);row.put("Md5",c.restore.apMd5);}}
   // Restoring just AP size/MD5 must reproduce the original manifest exactly,
   // including all original row order, burn paths, addresses and burn modes.
   if(c.restore!=null&&!c.restore.canonicalSHA256.equals(hash("SHA-256",BoundedJson.canonical(rows))))throw new IllegalArgumentException();
  }catch(RuntimeException e){throw new IOException("manifest/AP-only mismatch");}
  return new OtaPackage(files);
 }
 Object manifest(){return BoundedJson.read(members.get(candidate().manifestName));}
 // Read-only preparation evidence, NOT a transfer-session or installation claim.
 static void verifyDirectory(java.nio.file.Path directory)throws IOException{
  freezeDirectory(directory);
 }
 // Snapshot checked bytes into private memory; outgoing official slices must
 // equal this snapshot even if the vendor's directory is replaced afterward.
 static OtaPackage freezeDirectory(java.nio.file.Path directory)throws IOException{
  OtaCandidate c=candidate();
  if(java.nio.file.Files.isSymbolicLink(directory)||!java.nio.file.Files.isDirectory(directory,java.nio.file.LinkOption.NOFOLLOW_LINKS))throw new IOException("directory unavailable");
  Set<String> expected=new HashSet<>(c.pins.keySet());
  try(java.nio.file.DirectoryStream<java.nio.file.Path> list=java.nio.file.Files.newDirectoryStream(directory)){
   for(java.nio.file.Path p:list)if(!expected.remove(p.getFileName().toString()))throw new IOException("unexpected member");
  }if(!expected.isEmpty())throw new IOException("missing member");
  Map<String,byte[]> frozen=new HashMap<>();
  for(OtaCandidate.Pin pin:c.pins.values()){
   java.nio.file.Path p=directory.resolve(pin.name);
   java.nio.file.attribute.BasicFileAttributes before=java.nio.file.Files.readAttributes(p,java.nio.file.attribute.BasicFileAttributes.class,java.nio.file.LinkOption.NOFOLLOW_LINKS);
   if(!before.isRegularFile()||before.size()!=pin.size)throw new IOException("member type/size");
   byte[] bytes=new byte[pin.size];java.nio.ByteBuffer target=java.nio.ByteBuffer.wrap(bytes);
   Set<java.nio.file.OpenOption> options=new HashSet<>();options.add(java.nio.file.StandardOpenOption.READ);options.add(java.nio.file.LinkOption.NOFOLLOW_LINKS);
   try(java.nio.channels.SeekableByteChannel in=java.nio.file.Files.newByteChannel(p,options)){
    while(target.hasRemaining())if(in.read(target)<0)throw new IOException("short file");
    if(in.read(java.nio.ByteBuffer.allocate(1))!=-1)throw new IOException("file grew");
   }
   java.nio.file.attribute.BasicFileAttributes after=java.nio.file.Files.readAttributes(p,java.nio.file.attribute.BasicFileAttributes.class,java.nio.file.LinkOption.NOFOLLOW_LINKS);
   if(!java.util.Objects.equals(before.fileKey(),after.fileKey())||!before.lastModifiedTime().equals(after.lastModifiedTime())||after.size()!=pin.size||!pin.sha256.equals(hash("SHA-256",bytes)))throw new IOException("member changed/hash");
   frozen.put(pin.name,bytes);
  }
  return new OtaPackage(frozen);
 }
 int size(String name){byte[] b=members.get(name);if(b==null||name.equals(candidate().manifestName))throw new IllegalArgumentException("payload not allowed");return b.length;}
 byte[] slice(String name,int start,int size){int length=size(name);if(start<0||size<1||size>51200||start>length-size)throw new IllegalArgumentException("slice bounds");return Arrays.copyOfRange(members.get(name),start,start+size);}
}
