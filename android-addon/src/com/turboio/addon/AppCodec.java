package com.turboio.addon;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.zip.*;
import static com.turboio.addon.BoundedJson.*;

/** TAP1 snapshot packages and TAX1/TAR1, same bounded contract as the iOS SDK. */
public final class AppCodec {
    public static final int QUERY=1,INSTALL=2,LAUNCH=3,STOP=4,REMOVE=5;
    public static final class Package {
        public final Map<String,Object> document;public final byte[] wire;public final String id,name,sha;public final int version;
        private Package(Map<String,Object> d,byte[] wire,byte[] zip){document=Collections.unmodifiableMap(d);this.wire=wire;id=name(d.get("id"));name=text(d.get("name"),48);version=number(d.get("version"),1,65535);sha=sha(zip);}
    }
    private static void need(boolean yes){if(!yes)throw new IllegalArgumentException("Invalid TAP1 package");}
    static int u16(byte[] b,int at){return (b[at]&255)|((b[at+1]&255)<<8);}
    static long u32(byte[] b,int at){return FocusCodec.u32(b,at);}
    private static void p16(ByteArrayOutputStream o,int v){o.write(v);o.write(v>>>8);}
    private static void p32(ByteArrayOutputStream o,long v){p16(o,(int)v);p16(o,(int)(v>>>16));}
    private static void bytes(ByteArrayOutputStream o,byte[] b){o.write(b,0,b.length);}
    public static String sha(byte[] b){try{StringBuilder s=new StringBuilder();for(byte v:MessageDigest.getInstance("SHA-256").digest(b))s.append(String.format(Locale.ROOT,"%02x",v&255));return s.toString();}catch(Exception e){throw new IllegalStateException(e);}}
    public static Package read(byte[] zip){
        need(zip!=null&&zip.length>=22&&zip.length<=24576);int end=zip.length-22;
        need(u32(zip,end)==0x06054b50&&u16(zip,end+4)==0&&u16(zip,end+6)==0&&u16(zip,end+8)==2&&u16(zip,end+10)==2&&u16(zip,end+20)==0);
        long cdLong=u32(zip,end+16);need(cdLong<=end&&u32(zip,end+12)==end-cdLong);int cd=(int)cdLong,at=cd,local=0,total=0;Map<String,Object> files=new HashMap<>();
        for(int i=0;i<2;i++){
            need(end-at>=46&&u32(zip,at)==0x02014b50);int flags=u16(zip,at+8),method=u16(zip,at+10),nl=u16(zip,at+28),mode=(int)(u32(zip,at+38)>>>16);
            long packedLong=u32(zip,at+20),unpackedLong=u32(zip,at+24),crc=u32(zip,at+16);
            need((flags&~0x800)==0&&(method==0||method==8)&&u16(zip,at+30)==0&&u16(zip,at+32)==0&&u16(zip,at+34)==0&&((mode&0170000)==0||(mode&0170000)==0100000)&&nl<=16&&end-at-46>=nl&&unpackedLong<=20480-total&&u32(zip,at+42)==local);
            String name=utf8(Arrays.copyOfRange(zip,at+46,at+46+nl));need((name.equals("app.json")||name.equals("manifest.json"))&&!files.containsKey(name));
            need(cd-local>=30&&u32(zip,local)==0x04034b50&&u16(zip,local+6)==flags&&u16(zip,local+8)==method&&u32(zip,local+14)==crc&&u32(zip,local+18)==packedLong&&u32(zip,local+22)==unpackedLong&&u16(zip,local+26)==nl&&u16(zip,local+28)==0&&cd-local-30>=nl);
            need(Arrays.equals(Arrays.copyOfRange(zip,local+30,local+30+nl),Arrays.copyOfRange(zip,at+46,at+46+nl)));local+=30+nl;need(packedLong<=cd-local);int packed=(int)packedLong,unpacked=(int)unpackedLong;byte[] data=new byte[unpacked];
            if(method==0){need(packed==unpacked);System.arraycopy(zip,local,data,0,unpacked);}else{Inflater inflater=new Inflater(true);try{inflater.setInput(zip,local,packed);int n=inflater.inflate(data);need(n==unpacked&&inflater.finished()&&inflater.getRemaining()==0);}catch(DataFormatException e){throw new IllegalArgumentException("ZIP deflate");}finally{inflater.end();}}
            need(FocusCodec.crc(data,data.length)==crc);Object value=BoundedJson.read(data);need(Arrays.equals(canonical(value),data));files.put(name,value);total+=unpacked;local+=packed;at+=46+nl;
        }
        need(at==end&&local==cd);Map<String,Object> d=map(files.get("app.json")),m=map(files.get("manifest.json"));byte[] wire=encode(d);
        keys(m,"format","id","version","entry","sha256","runtime","permissions");need("TAP1-draft".equals(m.get("format"))&&"TAP1-draft".equals(m.get("runtime"))&&"app.json".equals(m.get("entry"))&&Objects.equals(m.get("id"),d.get("id"))&&Objects.equals(m.get("version"),d.get("version"))&&Objects.equals(m.get("permissions"),d.get("permissions"))&&sha(canonical(d)).equals(m.get("sha256")));
        return new Package(d,wire,zip);
    }
    public static byte[] encode(Map<String,Object> d){
        keys(d,"schema","id","name","version","entry","permissions","pages","assets");number(d.get("schema"),1,1);name(d.get("id"));name(d.get("entry"));text(d.get("name"),48);number(d.get("version"),1,65535);need(canonical(d).length<=20480);
        List<Object> permissions=list(d.get("permissions")),pages=list(d.get("pages"));Map<String,Object> assets=map(d.get("assets"));need(permissions.size()<=1&&(permissions.isEmpty()||permissions.get(0).equals("backend.events"))&&pages.size()>=1&&pages.size()<=4&&assets.size()<=8);
        Map<String,byte[]> raw=new HashMap<>();Map<String,Integer> indices=new HashMap<>();
        for(String id:assets.keySet()){name(id);Map<String,Object> a=map(assets.get(id));keys(a,"format","width","height","pixels");need("mono1-msb".equals(a.get("format")));int w=number(a.get("width"),8,128),h=number(a.get("height"),8,128);need(w%8==0);String s=text(a.get("pixels"),4096);byte[] b=Base64.getDecoder().decode(s);need(b.length==w*h/8&&Base64.getEncoder().encodeToString(b).equals(s));raw.put(id,b);}
        ByteArrayOutputStream body=new ByteArrayOutputStream();int count=0;
        for(Object p:pages){Map<String,Object> page=map(p);keys(page,"id","components");String id=name(page.get("id"));need(!indices.containsKey(id));indices.put(id,indices.size());List<Object> components=list(page.get("components"));need(components.size()>=1&&components.size()<=12);p16(body,count);p16(body,components.size());count+=components.size();}need(indices.containsKey(d.get("entry")));
        List<String> kinds=Arrays.asList("text","button","progress","image","frame");
        for(Object p:pages){Set<String> ids=new HashSet<>();int imageBudget=0;for(Object component:list(map(p).get("components"))){Map<String,Object> c=map(component);need(ids.add(name(c.get("id"))));int k=kinds.indexOf(c.get("kind"))+1;need(k>0);List<String> fields=new ArrayList<>(Arrays.asList("id","kind","x","y","w","h"));if(k<=2)fields.addAll(Arrays.asList("text","font"));if(k==2)fields.add("action");if(k==3)fields.add("value");if(k==4)fields.add("asset");keys(c,fields.toArray(new String[0]));
            int x=number(c.get("x"),0,538),y=number(c.get("y"),0,178),w=number(c.get("w"),2,540),h=number(c.get("h"),2,180),font=0,action=0,target=0,param=0;need(x+w<=540&&y+h<=180);byte[] data=new byte[0];
            if(k<=2){font=number(c.get("font"),14,28);need(Arrays.asList(14,16,18,20,24,28).contains(font)&&font+4<=h);data=text(c.get("text"),96).getBytes(StandardCharsets.UTF_8);}
            if(k==2){Map<String,Object> a=map(c.get("action"));keys(a,"type","target");String t=text(a.get("target"),24);if("page".equals(a.get("type"))){need(indices.containsKey(t));action=1;target=indices.get(t);}else if("emit".equals(a.get("type"))){name(t);need(permissions.contains("backend.events"));action=2;}else{need("exit".equals(a.get("type"))&&t.equals("system"));action=3;}}
            if(k==3)param=number(c.get("value"),0,100);
            if(k==4){String id=name(c.get("asset"));need(raw.containsKey(id));Map<String,Object> a=map(assets.get(id));need(w==number(a.get("width"),8,128)&&h==number(a.get("height"),8,128));data=raw.get(id);imageBudget+=w*h;need(imageBudget<=32768);}
            body.write(k);body.write(font);body.write(action);body.write(target);for(int v:new int[]{x,y,w,h,param,data.length})p16(body,v);bytes(body,data);
        }}
        ByteArrayOutputStream out=new ByteArrayOutputStream();bytes(out,new byte[]{'T','A','P','1'});out.write(pages.size());out.write(indices.get(d.get("entry")));p16(out,count);p32(out,12+body.size());bytes(out,body.toByteArray());need(out.size()<=20480);return out.toByteArray();
    }
    public static final class Slot {public final String id,name;public final int version,bytes;public final boolean tombstone;private Slot(byte[] b,int a){int il=b[a+1]&255,nl=b[a+2]&255;id=BoundedJson.name(utf8(Arrays.copyOfRange(b,a+16,a+16+il)));name=text(utf8(Arrays.copyOfRange(b,a+40,a+40+nl)),48);version=u16(b,a+4);bytes=u16(b,a+6);tombstone=b[a]==3;}}
    public static final class Reply {public final int result,slot,activeSlot;public final boolean needsQuery;public final long request,session,lastRequest;public final Slot[] slots;
        private Reply(byte[] b,Slot[] slots){result=b[4];needsQuery=(b[5]&2)!=0;slot=b[6]&255;activeSlot=b[7]&255;request=u32(b,8);session=u32(b,12);lastRequest=u32(b,16);this.slots=slots;}}
    public static Reply reply(byte[] b){try{need(b!=null&&b.length==376&&b[0]=='T'&&b[1]=='A'&&b[2]=='R'&&b[3]=='1'&&(b[4]&255)<=13&&(b[5]&~3)==0&&((b[6]&255)<=3||b[6]==-1)&&((b[7]&255)<=3||b[7]==-1)&&u32(b,8)>0&&u32(b,12)>0&&u32(b,20)==376);Slot[] slots=new Slot[4];for(int i=0;i<4;i++){int a=24+88*i;if(b[a]==0){for(int j=0;j<88;j++)need(b[a+j]==0);continue;}int il=b[a+1]&255,nl=b[a+2]&255;need((b[a]==1||b[a]==3)&&il>=1&&il<=24&&nl>=1&&nl<=48&&b[a+3]==0&&u16(b,a+4)>0&&u32(b,a+8)>0&&u16(b,a+6)<=20480&&(b[a]==3?u16(b,a+6)==0:u16(b,a+6)>=12));for(int j=16+il;j<40;j++)need(b[a+j]==0);for(int j=40+nl;j<88;j++)need(b[a+j]==0);slots[i]=new Slot(b,a);}return new Reply(b,slots);}catch(RuntimeException e){return null;}}
    public static byte[] command(int op,long request,long session,Package pkg,Slot target,int slot){
        need(op>=1&&op<=5&&request>0&&request<=0xffffffffL&&session>=0&&session<=0xffffffffL);byte[] id=new byte[0],title=new byte[0],wire=new byte[0];int version=0;
        if(op==QUERY){need(session==0&&pkg==null&&target==null&&slot==255);}else{need(session!=0);if(op==INSTALL){need(pkg!=null&&target==null&&slot==255);wire=encode(pkg.document);need(Arrays.equals(wire,pkg.wire));id=pkg.id.getBytes(StandardCharsets.UTF_8);title=pkg.name.getBytes(StandardCharsets.UTF_8);version=pkg.version;}else{need(pkg==null&&target!=null&&slot>=0&&slot<=3);id=target.id.getBytes(StandardCharsets.UTF_8);version=target.version;}}
        ByteArrayOutputStream o=new ByteArrayOutputStream();bytes(o,new byte[]{'T','A','X','1'});o.write(op);o.write(slot);o.write(id.length);o.write(title.length);p32(o,request);p32(o,session);p16(o,version);p16(o,wire.length);p32(o,0);bytes(o,id);bytes(o,title);bytes(o,wire);byte[] b=o.toByteArray();long crc=FocusCodec.crc(b,b.length);for(int i=0;i<4;i++)b[20+i]=(byte)(crc>>>(8*i));return b;
    }
}
