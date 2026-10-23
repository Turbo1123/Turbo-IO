package com.turboio.addon;
import java.nio.file.*;import java.util.*;

/** TNR3 wire codec vs the iOS/firmware nav_map.c: wrap bytes, label placement, validator verdicts. */
public final class NavMapCodecTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("navmap "+n+" "+why);}
    static byte[] body(byte[] wire){return Arrays.copyOfRange(wire,32,wire.length);}
    static byte[] unhex(String s){byte[] b=new byte[s.length()/2];for(int i=0;i<b.length;i++)b[i]=(byte)Integer.parseInt(s.substring(2*i,2*i+2),16);return b;}
    public static void main(String[] a)throws Exception{Path d=Paths.get(a[0]);
        for(String[] c:new String[][]{{"scene.bin","7","5"},{"scene2.bin","10","6"},{"pose.bin","8","7"},{"clear.bin","9","8"}}){
            byte[] wire=Files.readAllBytes(d.resolve(c[0]));int op=Integer.parseInt(c[1]);
            ok(Arrays.equals(NavMapCodec.wrap(op,0x01020304L,Long.parseLong(c[2]),body(wire)),wire),"wrap "+c[0]);ok(NavMapCodec.bodyValid(op,body(wire)),"valid "+c[0]);}
        byte[] scene2=Files.readAllBytes(d.resolve("scene2-body.bin"));
        for(String line:Files.readAllLines(d.resolve("labels.txt"))){String[] p=line.trim().split(" ");byte[] v=scene2.clone();int x=Integer.parseInt(p[0]),y=Integer.parseInt(p[1]),h=Integer.parseInt(p[2]);
            List<int[]> got=NavMapCodec.labels(v,x,y,h);ok(got.size()==Integer.parseInt(p[3]),"label count "+line);
            for(int i=0;i<got.size();i++){String[] e=p[4+i].split(",");ok(got.get(i)[0]==Integer.parseInt(e[0])&&got.get(i)[1]==Integer.parseInt(e[1])&&got.get(i)[2]==Integer.parseInt(e[2]),"label "+i+" "+line);}}
        int verdicts=0;for(String line:Files.readAllLines(d.resolve("validity.txt"))){String[] p=line.split(" ",-1);int op=Integer.parseInt(p[0]);boolean c=p[1].equals("1");byte[] v=p[2].isEmpty()?new byte[0]:unhex(p[2]);
            ok(NavMapCodec.bodyValid(op,v)==c,"verdict op "+op+" "+p[2]);verdicts++;}
        ok(verdicts>500,"many verdicts");
        ok(NavMapCodec.wrap(7,0,1,body(Files.readAllBytes(d.resolve("scene.bin"))))==null&&NavMapCodec.wrap(7,1,0,body(Files.readAllBytes(d.resolve("scene.bin"))))==null,"sid/seq zero");
        System.out.println("NavMapCodecTest: "+n+" checks against C nav_map.c");
    }
}
