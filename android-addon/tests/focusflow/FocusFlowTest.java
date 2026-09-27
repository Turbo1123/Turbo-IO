package com.turboio.addon;
import java.lang.reflect.*;
import android.os.SystemClock;
public class FocusFlowTest {
 static int count;static void ok(boolean b){count++;if(!b)throw new AssertionError(count+": "+FocusController.status());}
 static void reset()throws Exception{for(Field f:FocusController.class.getDeclaredFields()){if(!Modifier.isStatic(f.getModifiers()))continue;f.setAccessible(true);if(f.getType()==long.class)f.setLong(null,0);else f.set(null,null);}NativeTransfer.busy=NativeTransfer.refuse=false;NativeTransfer.peer="glasses";NativeTransfer.sends=0;SystemClock.now=10000;FocusController.init(new android.content.Context());}
 static void put(byte[] b,int at,long n){for(int i=0;i<4;i++)b[at+i]=(byte)(n>>>(8*i));}
 static byte[] reply(int state,int result,long seq){byte[] b=new byte[64];b[0]='T';b[1]='F';b[2]='A';b[3]='1';b[4]=1;b[5]=(byte)result;b[6]=(byte)state;put(b,8,NativeTransfer.session==0?10:NativeTransfer.session);put(b,12,seq);put(b,16,7);put(b,40,NativeTransfer.session);put(b,60,FocusCodec.crc(b,60));StringBuilder hex=new StringBuilder();for(byte v:b)hex.append(String.format("%02x",v&255));byte[] j=("{\"cmd\":\"turbo_focus_v1\",\"payload\":{\"data\":\""+hex+"\"}}").getBytes(java.nio.charset.StandardCharsets.UTF_8);java.io.ByteArrayOutputStream o=new java.io.ByteArrayOutputStream();o.write(8);o.write(1);o.write(16);o.write(6);o.write(26);int len=j.length;while(len>=128){o.write((len&127)|128);len>>>=7;}o.write(len);o.write(j,0,j.length);return o.toByteArray();}
 static void ack(int state,int result){NativeTransfer.receiver.message(NativeTransfer.peer,reply(state,result,NativeTransfer.request));}
 public static void main(String[] args)throws Exception{
  reset();FocusController.start(900);ok(NativeTransfer.sent[5]==FocusCodec.QUERY);FocusController.start(2700);ok(NativeTransfer.sends==1);NativeTransfer.receiver.message("other",reply(0,0,NativeTransfer.request));ok(NativeTransfer.sends==1&&NativeTransfer.busy);NativeTransfer.receiver.message("glasses",reply(0,0,NativeTransfer.request+1));ok(NativeTransfer.sends==1&&NativeTransfer.busy);ack(0,0);ok(NativeTransfer.sends==2&&NativeTransfer.sent[5]==FocusCodec.START&&FocusCodec.u32(NativeTransfer.sent,20)==900&&FocusCodec.u32(NativeTransfer.sent,16)==7);ack(1,0);ok(FocusController.snapshot().status==1);FocusController.start(900);ok(NativeTransfer.sends==2);
  reset();FocusController.start(900);ack(FocusCodec.PAUSED,0);ok(NativeTransfer.sends==1&&!NativeTransfer.busy);
  reset();FocusController.start(900);ack(0,3);ok(NativeTransfer.sends==1);
  reset();FocusController.start(900);SystemClock.now+=10001;ack(0,0);ok(NativeTransfer.sends==1);
  reset();FocusController.start(900);FocusController.detach();ack(0,0);ok(NativeTransfer.sends==1);
  reset();FocusController.start(900);FocusController.query();ack(0,0);ok(NativeTransfer.sends==1);
  reset();FocusController.start(900);FocusController.operate(FocusCodec.STOP);ack(0,0);ok(NativeTransfer.sends==1);
  reset();FocusController.start(900);NativeTransfer.peer="other";NativeTransfer.finish(TransferGate.State.UNCERTAIN,0);ok(NativeTransfer.sends==1);
  reset();NativeTransfer.refuse=true;FocusController.start(900);ok(NativeTransfer.sends==0);NativeTransfer.refuse=false;FocusController.start(900);ack(0,0);ok(NativeTransfer.sends==2);
  reset();FocusController.start(900);NativeTransfer.finish(TransferGate.State.UNCERTAIN,0);ok(NativeTransfer.sends==1);FocusController.refreshIfNeeded();ok(NativeTransfer.sends==1);
  reset();FocusController.query();ack(0,0);FocusController.start(900);ok(NativeTransfer.sends==2&&NativeTransfer.sent[5]==FocusCodec.START);
  reset();FocusController.start(0);ok(NativeTransfer.sends==0);NativeTransfer.peer="";FocusController.start(900);ok(NativeTransfer.sends==0);
  System.out.println("FocusFlow: "+count+" checks (mock transport, not device evidence)");
 }
}
