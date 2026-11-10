package com.turboio.addon;

import java.util.*;

/** Pinned OTA candidate descriptor: the single source of truth shared with the
 * offline watch-remote/flash_check.py preflight. Loaded once from
 * assets/turboio/otacandidate.json; every consumer fails closed until a
 * descriptor has been held. Never reads paths outside the descriptor. */
final class OtaCandidate {
 static final class Pin {
  final String name; final int size; final String sha256;
  private Pin(String name,int size,String sha256){this.name=name;this.size=size;this.sha256=sha256;}
 }
 static final class ManifestRestore {
  final long apSize; final String apMd5; final String canonicalSHA256;
  private ManifestRestore(long apSize,String apMd5,String canonicalSHA256){this.apSize=apSize;this.apMd5=apMd5;this.canonicalSHA256=canonicalSHA256;}
 }
 final String codeName, displayName, confirmToken, baseVersion;
 final String apName, manifestName;
 final int zipSize, otaSize, apSize, apBudgetBytes, manifestSize;
 final String zipSHA, apSHA, manifestSHA, stockAPSHA;
 final ManifestRestore restore;
 final Map<String,Pin> pins;
 private static volatile OtaCandidate DEFAULT;

 private OtaCandidate(String codeName,String displayName,String confirmToken,String baseVersion,
                      String apName,String manifestName,
                      int zipSize,String zipSHA,int otaSize,int apSize,String apSHA,int apBudgetBytes,
                      int manifestSize,String manifestSHA,String stockAPSHA,ManifestRestore restore,
                      Map<String,Pin> pins){
  this.codeName=codeName;this.displayName=displayName;this.confirmToken=confirmToken;this.baseVersion=baseVersion;
  this.apName=apName;this.manifestName=manifestName;
  this.zipSize=zipSize;this.zipSHA=zipSHA;this.otaSize=otaSize;this.apSize=apSize;this.apSHA=apSHA;this.apBudgetBytes=apBudgetBytes;
  this.manifestSize=manifestSize;this.manifestSHA=manifestSHA;this.stockAPSHA=stockAPSHA;this.restore=restore;
  this.pins=pins;
 }

 static void hold(byte[] json){
  if(json==null)throw new IllegalArgumentException("candidate descriptor missing");
  DEFAULT=parse(json);
 }
 static OtaCandidate require(){
  OtaCandidate c=DEFAULT;
  if(c==null)throw new IllegalStateException("OTA candidate descriptor missing; fail closed");
  return c;
 }
 /** Test-only: drop any held descriptor. */
 static void drop(){DEFAULT=null;}

 private static String hex(Object o,String what){
  String s=BoundedJson.text(o,64);
  if(!s.matches("[0-9a-f]{64}"))throw new IllegalArgumentException("Bad "+what);
  return s;
 }
 private static String label(Object o,String what,int bytes){
  return BoundedJson.text(o,bytes);
 }

 static OtaCandidate parse(byte[] json){
  Map<String,Object> root=BoundedJson.map(BoundedJson.read(json));
  if(BoundedJson.number(root.get("schema"),1,1)!=1)throw new IllegalArgumentException("Unsupported schema");
  String codeName=label(root.get("codeName"),"codeName",64);
  String displayName=label(root.get("displayName"),"displayName",96);
  String confirmToken=label(root.get("confirmToken"),"confirmToken",64);
  String baseVersion=label(root.get("baseVersion"),"baseVersion",64);
  Map<String,Object> zip=BoundedJson.map(root.get("zip"));
  BoundedJson.keys(zip,"size","sha256");
  int zipSize=BoundedJson.number(zip.get("size"),1,Integer.MAX_VALUE);
  String zipSHA=hex(zip.get("sha256"),"zip.sha256");
  int otaSize=BoundedJson.number(root.get("otaSize"),1,Integer.MAX_VALUE);
  Map<String,Object> ap=BoundedJson.map(root.get("ap"));
  BoundedJson.keys(ap,"name","size","sha256");
  String apName=BoundedJson.text(ap.get("name"),64);
  int apSize=BoundedJson.number(ap.get("size"),1,Integer.MAX_VALUE);
  String apSHA=hex(ap.get("sha256"),"ap.sha256");
  int apBudget=BoundedJson.number(root.get("apBudgetBytes"),1,Integer.MAX_VALUE);
  Map<String,Object> manifest=BoundedJson.map(root.get("manifest"));
  BoundedJson.keys(manifest,"name","size","sha256");
  String manifestName=BoundedJson.text(manifest.get("name"),64);
  int manifestSize=BoundedJson.number(manifest.get("size"),1,65536);
  String manifestSHA=hex(manifest.get("sha256"),"manifest.sha256");
  String stockAPSHA=hex(root.get("stockAPSHA256"),"stockAPSHA256");
  ManifestRestore restore=null;
  if(root.containsKey("manifestRestore")){
   Map<String,Object> r=BoundedJson.map(root.get("manifestRestore"));
   BoundedJson.keys(r,"apSize","apMd5","canonicalSHA256");
   restore=new ManifestRestore(BoundedJson.number(r.get("apSize"),1,Integer.MAX_VALUE),
                               BoundedJson.text(r.get("apMd5"),32),
                               hex(r.get("canonicalSHA256"),"manifestRestore.canonicalSHA256"));
  }
  List<Object> pinList=BoundedJson.list(root.get("payloadPins"));
  if(pinList.size()<3)throw new IllegalArgumentException("payloadPins");
  Map<String,Pin> pins=new LinkedHashMap<>();
  for(Object value:pinList){
   Map<String,Object> row=BoundedJson.map(value);
   BoundedJson.keys(row,"name","size","sha256");
   String name=BoundedJson.text(row.get("name"),64);
   if(name.indexOf('/')>=0||name.indexOf('\\')>=0)throw new IllegalArgumentException("Unsafe pin name");
   int size=BoundedJson.number(row.get("size"),1,Integer.MAX_VALUE);
   Pin pin=new Pin(name,size,hex(row.get("sha256"),"pin.sha256"));
   if(pins.put(name,pin)!=null)throw new IllegalArgumentException("Duplicate pin "+name);
  }
  if(!pins.containsKey(apName))throw new IllegalArgumentException("pins must include AP");
  if(!pins.containsKey(manifestName))throw new IllegalArgumentException("pins must include manifest");
  return new OtaCandidate(codeName,displayName,confirmToken,baseVersion,apName,manifestName,zipSize,zipSHA,otaSize,
                          apSize,apSHA,apBudget,manifestSize,manifestSHA,stockAPSHA,restore,
                          Collections.unmodifiableMap(pins));
 }
}
