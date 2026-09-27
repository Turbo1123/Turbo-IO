package com.turboio.addon;
import java.util.*;
import static com.turboio.addon.BoundedJson.*;

/** Business-15 metadata only, bounded before parsing; never retains audio. */
public final class CustomEnvelope {
    private static long var(byte[] b,int[] p){long n=0;for(int i=0;i<5;i++){if(p[0]>=b.length)throw new IllegalArgumentException();int v=b[p[0]++]&255;if(i==4&&(v&240)!=0)throw new IllegalArgumentException();n|=(long)(v&127)<<(7*i);if((v&128)==0)return n;}throw new IllegalArgumentException();}
    public static byte[] decode(byte[] b,String command,int expectedBytes){try{
        if(b==null||b.length>1024||expectedBytes<1||expectedBytes>400||command==null)return null;int[] at={0};int seen=0;long version=0,type=0;byte[] json=null;
        while(at[0]<b.length){long key=var(b,at);int tag=(int)(key>>>3);if(tag<1||tag>6||(seen&(1<<tag))!=0)return null;seen|=1<<tag;
            if((key&7)==0&&tag!=3&&tag!=4){long v=var(b,at);if(tag==1)version=v;if(tag==2)type=v;}
            else if((key&7)==2&&(tag==3||tag==4)){long n=var(b,at);if(n>b.length-at[0]||(tag==4&&n!=0))return null;if(tag==3)json=Arrays.copyOfRange(b,at[0],at[0]+(int)n);at[0]+=(int)n;}else return null;
        }
        if(version!=1||type!=6||json==null)return null;Map<String,Object> root=map(read(json));keys(root,"cmd","payload");if(!command.equals(root.get("cmd")))return null;Map<String,Object> p=map(root.get("payload"));if(command.equals("turbo_nav_v1")&&p.containsKey("value")){keys(p,"value","mode","data");number(p.get("value"),0,0);number(p.get("mode"),0,0);}else keys(p,"data");Object raw=p.get("data");if(!(raw instanceof String))return null;String s=(String)raw;if(s.length()!=expectedBytes*2||!s.matches("[a-f0-9]+"))return null;byte[] out=new byte[expectedBytes];for(int i=0;i<out.length;i++)out[i]=(byte)Integer.parseInt(s.substring(i*2,i*2+2),16);return out;
    }catch(RuntimeException e){return null;}}
}
