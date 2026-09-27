package com.turboio.addon;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.regex.*;

/** TMU1/TMA1 wire format shared with existing music.c. No firmware changes. */
final class MusicCodec {
 static final int OPEN=1,CLOCK=2,COVER=3,LYRICS=4,CLOSE=5,QUERY=6,MAX=4096,COVER_BYTES=20736;
 static void put(byte[] b,int at,long v){if(v<0||v>0xffffffffL)throw new IllegalArgumentException();for(int i=0;i<4;i++)b[at+i]=(byte)(v>>>(8*i));}
 static byte[] clip(String text,int max){ByteArrayOutputStream out=new ByteArrayOutputStream();if(text==null)return out.toByteArray();for(int i=0;i<text.length();){int cp=text.codePointAt(i);i+=Character.charCount(cp);if(cp<32||cp==127)cp=' ';if(cp>=0xd800&&cp<=0xdfff)continue;byte[] part=new String(Character.toChars(cp)).getBytes(StandardCharsets.UTF_8);if(out.size()+part.length>max)break;out.write(part,0,part.length);}return out.toByteArray();}
 static byte[] state(long position,long duration,boolean playing,int mode,long event,String title,String artist){if(position<0||position>86400000||duration<0||duration>86400000||mode<0||mode>2)throw new IllegalArgumentException();byte[] b=new byte[208];put(b,0,position);put(b,4,duration);b[8]=(byte)(playing?1:0);b[9]=(byte)mode;put(b,12,event);byte[] t=clip(title,95),a=clip(artist,79);System.arraycopy(t,0,b,16,t.length);System.arraycopy(a,0,b,112,a.length);return b;}
 static byte[] command(int op,long sid,long gen,long seq,int offset,boolean last,byte[] data){if(data==null)data=new byte[0];if(op<1||op>6||sid<=0||gen<=0||seq<=0||data.length>MAX-32)throw new IllegalArgumentException();
   if(op==OPEN||op==CLOCK){if(data.length!=208||offset!=0||last||FocusCodec.u32(data,0)>86400000||FocusCodec.u32(data,4)>86400000||(data[8]&255)>1||(data[9]&255)>2||data[10]!=0||data[11]!=0)throw new IllegalArgumentException();for(int i=192;i<208;i++)if(data[i]!=0)throw new IllegalArgumentException();field(data,16,96);field(data,112,80);}
   else if(op==COVER||op==LYRICS){int cap=op==COVER?COVER_BYTES:24576;if(offset<0||data.length==0||offset>cap-data.length)throw new IllegalArgumentException();if(op==COVER&&last&&offset+data.length!=cap)throw new IllegalArgumentException();}
   else if(data.length!=0||offset!=0||last)throw new IllegalArgumentException();
   byte[] b=new byte[32+data.length];b[0]='T';b[1]='M';b[2]='U';b[3]='1';b[4]=1;b[5]=(byte)op;b[6]=(byte)(last?1:0);put(b,8,sid);put(b,12,gen);put(b,16,seq);put(b,20,data.length);put(b,28,offset);System.arraycopy(data,0,b,32,data.length);put(b,24,FocusCodec.crc(b,b.length));return b;
 }
 private static void field(byte[] b,int at,int n){int k=0;while(k<n&&b[at+k]!=0)k++;if(k==n)throw new IllegalArgumentException();byte[] raw=Arrays.copyOfRange(b,at,at+k);String s=new String(raw,StandardCharsets.UTF_8);if(!Arrays.equals(raw,clip(s,k)))throw new IllegalArgumentException();for(int i=k;i<n;i++)if(b[at+i]!=0)throw new IllegalArgumentException();}
 static final class Reply{final int event,result;final long sid,gen,seq,request,position;final boolean active,awake;Reply(byte[]b){event=b[5];result=b[6];active=(b[7]&1)!=0;awake=(b[7]&2)!=0;sid=FocusCodec.u32(b,8);gen=FocusCodec.u32(b,12);seq=FocusCodec.u32(b,16);request=FocusCodec.u32(b,20);position=FocusCodec.u32(b,24);}}
 static Reply reply(byte[]b){if(b==null||b.length!=32||b[0]!='T'||b[1]!='M'||b[2]!='A'||b[3]!='1'||b[4]!=1||(b[5]&255)>6||(b[6]&255)>4||(b[7]&~3)!=0||FocusCodec.u32(b,24)>86400000||FocusCodec.u32(b,28)!=FocusCodec.crc(b,28))return null;return new Reply(b);}
 static final class Line{final long ms;final String text;Line(long m,String t){ms=m;text=t;}}
 static List<Line> lrc(String text){List<Line> rows=new ArrayList<>();if(text==null||text.length()>200000)return rows;Pattern stamp=Pattern.compile("\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\]");Matcher off=Pattern.compile("\\[offset:([+-]?\\d{1,9})\\]",Pattern.CASE_INSENSITIVE).matcher(text);long offset=off.find()?Math.max(-60000,Math.min(60000,Long.parseLong(off.group(1)))):0;
   for(String line:text.split("[\\r\\n]")){Matcher m=stamp.matcher(line);List<Long> times=new ArrayList<>();int end=0;while(m.find()){end=m.end();int sec=Integer.parseInt(m.group(2));if(sec>59)continue;String f=m.group(3);long t=(Long.parseLong(m.group(1))*60+sec)*1000+(f==null?0:Integer.parseInt(f)*(f.length()==1?100:f.length()==2?10:1))+offset;if(t<=86400000&&times.size()<192)times.add(Math.max(0,t));}if(end==0)continue;String body=new String(clip(line.substring(end).trim(),240),StandardCharsets.UTF_8);if(body.isEmpty())continue;for(long t:times){if(rows.size()>=1024)break;rows.add(new Line(t,body));}}
   rows.sort(Comparator.comparingLong(l->l.ms));return new ArrayList<>(rows.subList(0,Math.min(192,rows.size())));
 }
 static byte[] lyrics(List<Line> rows){ByteArrayOutputStream out=new ByteArrayOutputStream();long prior=0;int count=0;for(Line l:rows){if(count>=192)break;if(l.ms<prior||l.ms<0||l.ms>86400000)throw new IllegalArgumentException();byte[] b=clip(l.text,240);if(b.length==0)continue;if(out.size()+6+b.length>24576)break;byte[] h=new byte[6];put(h,0,l.ms);h[4]=(byte)b.length;h[5]=(byte)(b.length>>>8);out.write(h,0,6);out.write(b,0,b.length);prior=l.ms;count++;}return out.toByteArray();}
 static int line(List<Line> rows,long position){int result=-1;for(int i=0;i<rows.size()&&rows.get(i).ms<=position;i++)result=i;return result;}
}
