package com.turboio.addon;

import java.io.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.zip.*;

/** The one reviewed candidate, TVP2 (Strix OS 1.0.5.5 base + TurboIO AP), for hosts 1.0.6 / 1.0.7.
 * Not an arbitrary firmware loader. No extracted paths. */
final class OtaPackage {
 static final String VERSION="Strix OS 1.0.5.5", NAME="TVP2 · 清晰投屏与仪表盘兼容";
 /** One-time authorization phrase typed by the user; also the feed/gate candidate token. */
 static final String TOKEN="TVP2", CODE="TVP2";
 /** Glasses versions this candidate may be offered over. */
 static final List<String> BASES=Arrays.asList("Strix OS 1.0.4.12","Strix OS 1.0.5.5");
 static final List<String> BASE_CODES=Arrays.asList("01.00.04.0012","01.00.05.0005");
 static final String FEED_VERSION="0100050005", DIRECTORY="Strix_OS_1.0.5.5";
 /** What the user inspects on the lens before releasing the result guard. */
 static final String MARKER="显示 Turbo IO 三排菜单";
 static final int FEED_CODE=100050005;
 static final int ZIP_SIZE=8861428, AP_SIZE=7435336;
 static final String ZIP_SHA="154f0f8e68a69b8fb93f869e423081ee43969bf09c5174e8dbeac192c1047c11";
 static final String AP_SHA="66a2d04faa751c87f830ff324c1d9f9eb96a969ba2c65b37170cc82585970586";
 // Restoring the AP row to the stock values must reproduce the stock 1.0.5.5 manifest exactly.
 private static final int STOCK_AP_SIZE=7208648;
 private static final String STOCK_AP_MD5="0246c12a118e8589593fdd053fddb292";
 private static final String STOCK_MANIFEST="db67ff62cf58350ef3f781a502c0c20bc378bf6d01272b3cce38494386b374f0";
 // Non-AP pins match the unmodified official Strix OS 1.0.5.5 ZIP byte for byte.
 private static final String[] PINS={
  "OtaFileInfo.json 2700 843304cf0db0f6061002652952924867cf03051961db5d6dc7ddff043ea7d05b",
  "bt_controller.bin 625364 0060cc360b04577e8f5ce8f5d54fabde6103a6fef5a1a052260097920165a0c6",
  "cb_fw_venus.bin 114592 8799f12071bdac082218e3601c24ab0989275fc2f7db74e37b8314a225c2cf7d",
  "fac_test_img.bin 1821552 18eb0901c3e0daeae48dd5f015252b6931ea7368f0160c2c985c4e74296d17eb",
  "images.bin 383431 219ba2f7935850a059ac7e6a1ffa181056ce70891501db28238940dfbdc44cc5",
  "lotties.bin 651481 ad66d83a3394034f825a12769aad292fc03e59fa865fe06bc43536b918a0b32b",
  "nuttx_ap.bin 7435336 "+AP_SHA,
  "nuttx_apc1.bin 1423532 40ea15260a56b6c642120b3234a871662d0e74709deab14cda64be0949dacb40",
  "nuttx_audio.bin 1461920 549a72c032595e3829da7d63b7e1fd13cceda1a55dfefa7a7cad02db5a9b42ab",
  "nuttx_bth.bin 1189216 d48cb821f30045ea681cae0bfdab766c6d02be6f7b2bd5a75e1c41dc127d1a30",
  "ota_installer_progress.bin 5616 6fd65d296a667e1a7d94ec129adfd26458a4008ef403b331f855192c36eb3e3f",
  "pil_algo_up_demo_nand.dll 504388 e266726fe055ac6ec6f785a9440e8da7421402f2b4d3d7889039ad9b94e119c2",
  "pil_algo_vad_demo.dll 433900 a3253e86dcdcb92a4d0d32fb4a0800da8761138c021a93d1c1dbca51268b66a2",
  "pil_algo_wakeup_dll_nand.dll 287560 d1594cb8658b228e52c2606d02f1eab696d35a11ed42ddcb725e76a745f5550f",
  "rives.bin 689431 836bc019f7152890b94cafafe2edaa024f317526318349f7833319e41158b104",
  "smf.json 23510 2713dc3a302a65c101fa981500cd8b217766c526b6045bf02db5e9e6763d076d"};
 static final int PIN_COUNT=PINS.length;
 private final Map<String,byte[]> members;
 private OtaPackage(Map<String,byte[]> members){this.members=members;}
 static String hash(String algorithm,byte[] bytes){try{byte[] h=MessageDigest.getInstance(algorithm).digest(bytes);StringBuilder out=new StringBuilder();for(byte v:h)out.append(String.format(Locale.ROOT,"%02x",v&255));return out.toString();}catch(Exception e){throw new IllegalStateException("digest unavailable");}}
 static OtaPackage verify(byte[] zip)throws IOException{
  if(zip==null||zip.length!=ZIP_SIZE||!ZIP_SHA.equals(hash("SHA-256",zip)))throw new IOException("仅接受已审核 "+CODE+" 原样 ZIP，大小或 SHA-256 不符");
  Map<String,String[]> pins=new HashMap<>();for(String line:PINS){String[] p=line.split(" ");pins.put(p[0],p);}
  Map<String,byte[]> files=new HashMap<>();int total=0;
  try(ZipInputStream in=new ZipInputStream(new ByteArrayInputStream(zip))){ZipEntry e;while((e=in.getNextEntry())!=null){String[] p=pins.get(e.getName());if(p==null||e.isDirectory()||files.containsKey(e.getName()))throw new IOException("ZIP member");int size=Integer.parseInt(p[1]);byte[] data=new byte[size];int at=0,n;while(at<size&&(n=in.read(data,at,size-at))!=-1)at+=n;if(at!=size||in.read()!=-1||!p[2].equals(hash("SHA-256",data)))throw new IOException("member size/hash");total+=size;if(total>19000000)throw new IOException("expanded budget");files.put(e.getName(),data);in.closeEntry();}}
  if(files.size()!=PINS.length)throw new IOException("missing member");
  try{List<Object> rows=BoundedJson.list(BoundedJson.read(files.get("OtaFileInfo.json")));if(rows.size()!=PINS.length-1)throw new IllegalArgumentException();Set<String> found=new HashSet<>();
   for(Object value:rows){Map<String,Object> row=BoundedJson.map(value);BoundedJson.keys(row,"Name","Size","Md5","BurnMode","BurnAddr","BurnPath");String name=BoundedJson.text(row.get("Name"),64);byte[] bytes=files.get(name);if(bytes==null||name.equals("OtaFileInfo.json")||!found.add(name)||BoundedJson.number(row.get("Size"),1,AP_SIZE)!=bytes.length||!hash("MD5",bytes).equals(row.get("Md5")))throw new IllegalArgumentException();if(name.equals("nuttx_ap.bin")){row.put("Size",STOCK_AP_SIZE);row.put("Md5",STOCK_AP_MD5);}}
   // Restoring just AP size/MD5 must reproduce the original manifest exactly,
   // including all original row order, burn paths, addresses and burn modes.
   if(!STOCK_MANIFEST.equals(hash("SHA-256",BoundedJson.canonical(rows))))throw new IllegalArgumentException();
  }catch(RuntimeException e){throw new IOException("manifest/AP-only mismatch");}
  return new OtaPackage(files);
 }
 Object manifest(){return BoundedJson.read(members.get("OtaFileInfo.json"));}
 // Read-only preparation evidence, NOT a transfer-session or installation claim.
 static void verifyDirectory(java.nio.file.Path directory)throws IOException{
  freezeDirectory(directory);
 }
 // Snapshot checked bytes into private memory; outgoing official slices must
 // equal this snapshot even if the vendor's directory is replaced afterward.
 static OtaPackage freezeDirectory(java.nio.file.Path directory)throws IOException{
  if(java.nio.file.Files.isSymbolicLink(directory)||!java.nio.file.Files.isDirectory(directory,java.nio.file.LinkOption.NOFOLLOW_LINKS))throw new IOException("directory unavailable");
  Set<String> expected=new HashSet<>();for(String line:PINS)expected.add(line.split(" ")[0]);
  try(java.nio.file.DirectoryStream<java.nio.file.Path> list=java.nio.file.Files.newDirectoryStream(directory)){
   for(java.nio.file.Path p:list)if(!expected.remove(p.getFileName().toString()))throw new IOException("unexpected member");
  }if(!expected.isEmpty())throw new IOException("missing member");
  Map<String,byte[]> frozen=new HashMap<>();
  for(String line:PINS){String[] pin=line.split(" ");java.nio.file.Path p=directory.resolve(pin[0]);
   java.nio.file.attribute.BasicFileAttributes before=java.nio.file.Files.readAttributes(p,java.nio.file.attribute.BasicFileAttributes.class,java.nio.file.LinkOption.NOFOLLOW_LINKS);
   int size=Integer.parseInt(pin[1]);if(!before.isRegularFile()||before.size()!=size)throw new IOException("member type/size");
   byte[] bytes=new byte[size];java.nio.ByteBuffer target=java.nio.ByteBuffer.wrap(bytes);
   Set<java.nio.file.OpenOption> options=new HashSet<>();options.add(java.nio.file.StandardOpenOption.READ);options.add(java.nio.file.LinkOption.NOFOLLOW_LINKS);
   try(java.nio.channels.SeekableByteChannel in=java.nio.file.Files.newByteChannel(p,options)){
    while(target.hasRemaining())if(in.read(target)<0)throw new IOException("short file");
    if(in.read(java.nio.ByteBuffer.allocate(1))!=-1)throw new IOException("file grew");
   }
   java.nio.file.attribute.BasicFileAttributes after=java.nio.file.Files.readAttributes(p,java.nio.file.attribute.BasicFileAttributes.class,java.nio.file.LinkOption.NOFOLLOW_LINKS);
   if(!java.util.Objects.equals(before.fileKey(),after.fileKey())||!before.lastModifiedTime().equals(after.lastModifiedTime())||after.size()!=size||!pin[2].equals(hash("SHA-256",bytes)))throw new IOException("member changed/hash");
   frozen.put(pin[0],bytes);
  }
  return new OtaPackage(frozen);
 }
 int size(String name){byte[] b=members.get(name);if(b==null||name.equals("OtaFileInfo.json"))throw new IllegalArgumentException("payload not allowed");return b.length;}
 byte[] slice(String name,int start,int size){int length=size(name);if(start<0||size<1||size>51200||start>length-size)throw new IllegalArgumentException("slice bounds");return Arrays.copyOfRange(members.get(name),start,start+size);}
}
