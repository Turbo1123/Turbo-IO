package com.turboio.addon;
import java.io.*;

/** Binary frames (op 2) parse for TTS audio; reserved opcodes are still rejected. */
public final class WebSocketFrameTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("ws frame "+n+" "+why);}
    public static void main(String[] a)throws Exception{
        BoundedWebSocket.Frame f=BoundedWebSocket.frame(new ByteArrayInputStream(new byte[]{(byte)0x82,3,1,2,3}));ok(f.op==2&&f.fin&&f.bytes.length==3,"binary frame");
        f=BoundedWebSocket.frame(new ByteArrayInputStream(new byte[]{(byte)0x02,1,9}));ok(f.op==2&&!f.fin,"binary fragment");
        for(int op:new int[]{3,7,11}){boolean threw=false;try{BoundedWebSocket.frame(new ByteArrayInputStream(new byte[]{(byte)(0x80|op),0}));}catch(IOException e){threw=true;}ok(threw,"reserved op "+op);}
        System.out.println("WebSocketFrameTest: "+n+" checks");
    }
}
