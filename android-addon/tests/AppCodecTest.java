import com.turboio.addon.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
public class AppCodecTest {
    static int tests;
    static void yes(boolean condition){tests++;if(!condition)throw new AssertionError("assert "+tests);}
    static void rejected(Runnable r){boolean fail=false;try{r.run();}catch(IllegalArgumentException e){fail=true;}yes(fail);}
    public static void main(String[] args)throws Exception {
        Path gallery=Paths.get(args[0]),golden=Paths.get(args[1]);int packages=0;
        try(DirectoryStream<Path> paths=Files.newDirectoryStream(gallery,"Gallery_*.zip")){for(Path path:paths){byte[] zip=Files.readAllBytes(path);AppCodec.Package p=AppCodec.read(zip);String stem=path.getFileName().toString().replace(".zip","");yes(Arrays.equals(p.wire,Files.readAllBytes(golden.resolve(stem+".tap"))));yes(Arrays.equals(AppCodec.command(2,42,123,p,null,255),Files.readAllBytes(golden.resolve(stem+".tax"))));yes(p.sha.length()==64);for(int i:new int[]{0,6,8,14,18,22,26,28,zip.length-1,zip.length-22}){byte[] damaged=zip.clone();damaged[i]^=1;rejected(()->AppCodec.read(damaged));}rejected(()->AppCodec.read(Arrays.copyOf(zip,zip.length-1)));rejected(()->AppCodec.read(Arrays.copyOf(zip,zip.length+1)));packages++;}}
        yes(packages==20);
        for(String s:new String[]{"{\"x\":1,\"x\":2}","{\"x\":1.0}","{\"x\":01}","{\"x\":true,}","[1,]","\"\\ud800\"","null extra"})rejected(()->BoundedJson.read(s.getBytes(StandardCharsets.UTF_8)));
        for(String s:new String[]{"{\"x\":\"汉字\",\"y\":[1,true,null]}","{\"a\":\"\\n\",\"b\":\"/\"}"})yes(Arrays.equals(BoundedJson.canonical(BoundedJson.read(s.getBytes(StandardCharsets.UTF_8))),s.getBytes(StandardCharsets.UTF_8)));
        byte[] query=AppCodec.command(1,12,0,null,null,255);yes(query.length==24&&query[5]==-1);rejected(()->AppCodec.command(1,12,1,null,null,255));rejected(()->AppCodec.command(1,0,0,null,null,255));
        byte[] reply=new byte[376];reply[0]='T';reply[1]='A';reply[2]='R';reply[3]='1';reply[6]=reply[7]=-1;reply[8]=42;reply[12]=123;reply[20]=120;reply[21]=1;AppCodec.Reply r=AppCodec.reply(reply);yes(r!=null&&r.session==123&&r.slots.length==4&&r.slots[0]==null);
        for(int i:new int[]{0,4,5,6,7,20,24,25,30,90,375}){byte[] bad=reply.clone();bad[i]=(byte)254;yes(AppCodec.reply(bad)==null);}
        System.out.println("AppCodecTest: "+tests+" assertions; 20 Python SDK wire/command matches");
    }
}
