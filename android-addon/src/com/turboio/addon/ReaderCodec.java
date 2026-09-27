package com.turboio.addon;
import java.nio.*;
import java.nio.charset.*;
import java.util.*;
import java.util.zip.CRC32;

/** TWR1, strict little endian and bounded phone-side pages. No book network access. */
final class ReaderCodec {
 static long get(byte[] b,int p){return ((long)b[p]&255)|((long)b[p+1]&255)<<8|((long)b[p+2]&255)<<16|((long)b[p+3]&255)<<24;}
 static void put(byte[] b,int p,long n){if(n<0||n>0xffffffffL)throw new IllegalArgumentException();for(int i=0;i<4;i++)b[p+i]=(byte)(n>>>(i*8));}
 static long crc(byte[] b){CRC32 c=new CRC32();c.update(b);return c.getValue();}
 static byte[] command(int op,long sid,long seq,long rev,long offset,byte[] body){if(op<1||op>7||sid==0||seq==0||(body!=null&&body.length>480))throw new IllegalArgumentException();int n=body==null?0:body.length;byte[] b=new byte[32+n];System.arraycopy(new byte[]{84,87,82,49,1,(byte)op},0,b,0,6);put(b,8,sid);put(b,12,seq);put(b,16,rev);put(b,20,offset);put(b,24,n);if(n>0)System.arraycopy(body,0,b,32,n);put(b,28,crc(b));return b;}
 static final class Book{String id,title,author,coverURL;int token;byte[] cover;Book(String id,String title,String author,int token){this.id=id;this.title=title;this.author=author;this.token=token;}}
 static void text(byte[] out,int offset,int size,String s){byte[] b=MusicCodec.clip(s==null?"":s,size-1);System.arraycopy(b,0,out,offset,b.length);}
 static byte[] shelf(List<Book> books,int first){if(books.size()>10000||first<0||first>books.size()||first%4!=0)throw new IllegalArgumentException();int count=Math.min(4,books.size()-first);byte[] b=new byte[64+5824*count];put(b,0,1);put(b,4,first);put(b,8,books.size());put(b,12,count);for(int i=0;i<count;i++){Book v=books.get(first+i);if(v.token<=0)throw new IllegalArgumentException();int p=64+i*5824;text(b,p,96,v.title);text(b,p+96,64,v.author);put(b,p+160,v.token);if(v.cover!=null){if(v.cover.length!=5632)throw new IllegalArgumentException();System.arraycopy(v.cover,0,b,p+192,5632);}}return b;}
 static byte[] window(Book book,List<String> lines,int row,int speed,boolean auto){if(lines.isEmpty()||lines.size()>50000||row<0||row>=lines.size()||speed<30||speed>480||book.token<=0)throw new IllegalArgumentException();int count=Math.min(64,lines.size()-row);byte[] b=new byte[256+128*count];put(b,0,2);put(b,4,row);put(b,8,lines.size());put(b,12,count);put(b,16,row);put(b,20,speed);put(b,24,auto?1:0);put(b,28,book.token);text(b,64,96,book.title);text(b,160,96,"手机导入 · 有界阅读窗口");for(int i=0;i<count;i++)text(b,256+i*128,128,lines.get(row+i));return b;}
 static List<String> wrap(String s){if(s.length()>500000)throw new IllegalArgumentException("正文超过50万字符");List<String> out=new ArrayList<>();StringBuilder line=new StringBuilder();int cells=0,bytes=0;for(int p=0;p<s.length();){int cp=s.codePointAt(p);p+=Character.charCount(cp);if(cp=='\r')continue;if(cp=='\n'){out.add(line.toString());line.setLength(0);cells=bytes=0;continue;}if(Character.isISOControl(cp)||cp>=0xd800&&cp<=0xdfff)continue;String ch=new String(Character.toChars(cp));int n=ch.getBytes(StandardCharsets.UTF_8).length,w=cp<128?1:2;if(cells+w>48||bytes+n>127){out.add(line.toString());line.setLength(0);cells=bytes=0;}line.append(ch);cells+=w;bytes+=n;if(out.size()>50000)throw new IllegalArgumentException();}if(line.length()>0)out.add(line.toString());if(out.isEmpty())throw new IllegalArgumentException("没有可读正文");return out;}
 static final class Reply{int event,result,kind,speed;long sid,seq,revision,id,value,token,row;boolean automatic;}
 static Reply reply(byte[] b){if(b==null||b.length!=48||b[0]!=87||b[1]!=82||b[2]!=65||b[3]!=49||b[4]!=1||(b[5]&255)>5||(b[6]&255)>4||(b[7]&~3)!=0||crc(Arrays.copyOf(b,44))!=get(b,44))return null;Reply r=new Reply();r.event=b[5];r.result=b[6];r.automatic=(b[7]&2)!=0;r.sid=get(b,8);r.seq=get(b,12);r.revision=get(b,16);r.id=get(b,20);r.value=get(b,24);r.token=get(b,28);r.row=get(b,32);r.speed=(int)get(b,36);r.kind=(int)get(b,40);return r;}
 static String utf8(byte[] b)throws CharacterCodingException{return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(b)).toString();}
}
