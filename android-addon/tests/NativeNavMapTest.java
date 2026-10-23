import com.turboio.addon.*;
import java.nio.*;
import java.util.*;
import java.util.zip.CRC32;

/** TNR3 scheduling inside the TNV1 session (iOS NativeNavigation.m pump/finish): QUERY probe, SCENE2 with pose age,
 * POSE ≥0.2 s on change or 1 s keep-alive, urgent UPDATE first, stale pose never sent, CLEAR once, 3 s pose deadline. */
public class NativeNavMapTest {
    static int checks;static void yes(boolean b,String why){checks++;if(!b)throw new AssertionError("TNR session #"+checks+" "+why);}
    static NativeNavCodec.Scene scene(){NativeNavCodec.Scene s=new NativeNavCodec.Scene();s.icon=3;s.mode=1;s.heading=90;s.distance=80;s.remaining=2048;s.seconds=420;s.x=512;s.y=800;s.points=new int[][]{{512,800},{700,200}};s.road="测试道路";s.turn="前方右转";return s;}
    static NativeNavCodec.Reply reply(long seq,int caps){ByteBuffer q=ByteBuffer.allocate(32).order(ByteOrder.LITTLE_ENDIAN);q.put(new byte[]{'T','N','A','1',1,0,3,0}).putInt(77).putInt((int)seq).putInt(60000).putInt(32).putInt(caps);CRC32 c=new CRC32();c.update(q.array(),0,28);q.putInt(28,(int)c.getValue());return NativeNavCodec.reply(q.array());}
    static byte[] map(int gen,int x){ByteBuffer q=ByteBuffer.allocate(32).order(ByteOrder.LITTLE_ENDIAN);q.putInt(gen).putShort((short)320).putShort((short)1).putShort((short)2).putShort((short)0).putInt(0);q.putShort((short)2).put((byte)6).put((byte)0).put((byte)8).put((byte)0).putShort((short)0);q.putShort((short)x).putShort((short)0).putShort((short)(x+40)).putShort((short)40);return q.array();}
    static byte[] map2(byte[] m){byte[] v=Arrays.copyOf(m,m.length+12);System.arraycopy(m,0,v,m.length,4);return v;}
    static byte[] pose(int gen,int x){ByteBuffer q=ByteBuffer.allocate(12).order(ByteOrder.LITTLE_ENDIAN);q.putInt(gen).putShort((short)x).putShort((short)4).putShort((short)90).putShort((short)0);return q.array();}
    static int op(byte[] p){return p[5]&255;}
    static int u16(byte[] p,int at){return (p[at]&255)|(p[at+1]&255)<<8;}
    public static void main(String[] a){
        yes(reply(1,1)!=null&&reply(1,1).capabilities==1&&reply(1,2)==null,"QUERY capability bit 0 only");
        yes(NavMapCodec.bodyValid(NavMapCodec.SCENE,map(1,0))&&NavMapCodec.bodyValid(NavMapCodec.SCENE2,map2(map(1,0)))&&NavMapCodec.bodyValid(NavMapCodec.POSE,pose(1,0)),"fixtures valid");
        List<byte[]> sent=new ArrayList<>();NativeNavSession s=new NativeNavSession("peer",77,(b,id,seq)->{sent.add(b);return true;});
        byte[] m1=map(1,0);s.mapOffer(m1,map2(m1),pose(1,10),0,0);yes(s.start(scene(),0),"start");yes(op(sent.get(0))==1&&!s.extended()==false,"START, extended by map offer");
        s.complete(1,true,0,reply(1,0),100);s.pump("peer",100);yes(sent.size()==2&&op(sent.get(1))==6,"QUERY first, no 1 s gap when extended");
        s.complete(2,true,0,reply(2,1),150);s.mapOffer(m1,map2(m1),pose(1,10),200,200);s.pump("peer",300);
        byte[] p=sent.get(2);yes(op(p)==10,"SCENE2 when supported");yes(u16(p,p.length-12+4)==10&&u16(p,p.length-2)==100,"SCENE2 carries latest pose, age stamped at send");
        s.complete(3,true,0,reply(3,1),350);yes(s.maps()==1&&s.poses()==1,"SCENE2 commits map and pose");
        s.pump("peer",400);s.pump("peer",560);yes(sent.size()==3,"unchanged pose within 1 s: nothing");
        s.mapOffer(m1,map2(m1),pose(1,20),600,600);s.pump("peer",600);yes(sent.size()==4&&op(sent.get(3))==8&&u16(sent.get(3),36)==20,"changed pose ≥0.2 s → POSE");
        s.complete(4,true,0,reply(4,1),650);s.mapOffer(m1,map2(m1),pose(1,21),700,700);s.pump("peer",800);yes(sent.size()==4,"POSE at most every 0.2 s");
        s.pump("peer",850);yes(sent.size()==5&&op(sent.get(4))==8,"changed pose after 0.2 s");s.complete(5,true,0,reply(5,1),860);
        s.pump("peer",1700);yes(sent.size()==5,"keep-alive waits 1 s");s.pump("peer",1860);yes(sent.size()==6&&op(sent.get(5))==8&&u16(sent.get(5),42)==1160,"1 s keep-alive with fresh age");s.complete(6,true,0,reply(6,1),1870);
        NativeNavCodec.Scene turn=scene();turn.road="新道路";s.offer(turn,1900);s.mapOffer(m1,map2(m1),pose(1,30),1900,1900);s.pump("peer",2100);yes(sent.size()==7&&op(sent.get(6))==2,"urgent UPDATE preempts pose");s.complete(7,true,0,reply(7,1),2150);
        NativeNavCodec.Scene turn2=scene();turn2.road="第三道路";s.offer(turn2,2200);s.pump("peer",2400);yes(sent.size()==8&&op(sent.get(7))==2,"urgent UPDATE within 1 s of the last commit, pose pending");s.complete(8,true,0,reply(8,1),2450);
        NativeNavCodec.Scene minor=scene();minor.road="第三道路";minor.distance=70;s.offer(minor,2500);s.pump("peer",2700);yes(sent.size()==9&&op(sent.get(8))==8,"non-urgent change within 1 s of commit: pose first");s.complete(9,true,0,reply(9,1),2750);
        s.pump("peer",3500);yes(sent.size()==10&&op(sent.get(9))==2,"non-urgent change after 1 s: UPDATE");s.complete(10,true,0,reply(10,1),3550);
        s.pump("peer",6000);yes(sent.size()==10,"stale pose (>4 s) never sent");
        byte[] m2=map(2,0);s.mapOffer(m2,null,pose(2,0),6000,6000);s.pump("peer",6100);yes(sent.size()==11&&op(sent.get(10))==7,"SCENE when no SCENE2 offered");s.complete(11,true,0,reply(11,1),6150);
        yes(s.maps()==2&&s.poses()==5,"SCENE commits map, clears pose");s.pump("peer",6400);yes(op(sent.get(sent.size()-1))==8,"pose after SCENE");s.complete(sent.size(),true,0,reply(sent.size(),1),6450);
        int before=sent.size();s.mapOffer(null,null,null,0,6500);s.pump("peer",6500);yes(sent.size()==before+1&&op(sent.get(before))==9,"withdrawn map → CLEAR");s.complete(before+1,true,0,reply(before+1,1),6550);
        s.pump("peer",6700);s.pump("peer",7700);yes(sent.size()==before+1,"CLEAR once");
        // A map offer with a stale or future pose is withdrawn like a missing one.
        s.mapOffer(m2,null,pose(2,0),1000,6000);yes(!s.hasMap(),"stale offer refused");s.mapOffer(m2,null,pose(2,0),7000,6000);yes(!s.hasMap(),"future pose refused");s.mapOffer(m2,null,pose(3,0),6000,6000);yes(!s.hasMap(),"generation mismatch refused");
        // POSE deadline is 3 s (other ops 8 s).
        List<byte[]> out=new ArrayList<>();NativeNavSession d=new NativeNavSession("peer",77,(b,id,seq)->{out.add(b);return true;});d.mapOffer(m1,null,pose(1,0),0,0);d.start(scene(),0);d.complete(1,true,0,reply(1,0),10);d.pump("peer",10);d.complete(2,true,0,reply(2,0),20);
        d.mapOffer(m1,map2(m1),pose(1,0),20,20);d.pump("peer",20);yes(op(out.get(2))==7,"SCENE even with SCENE2 offered: no v2 capability");d.complete(3,true,0,reply(3,0),30);d.mapOffer(m1,null,pose(1,5),300,300);d.pump("peer",300);yes(op(out.get(3))==8,"POSE");
        d.pump("peer",3299);yes(d.state()==NativeNavSession.State.RUNNING,"before 3 s");d.pump("peer",3300);yes(d.state()==NativeNavSession.State.UNCERTAIN,"POSE 3 s deadline");
        // No map offered: a plain TNV1 session never probes.
        List<byte[]> plain=new ArrayList<>();NativeNavSession n=new NativeNavSession("peer",77,(b,id,seq)->{plain.add(b);return true;});n.start(scene(),0);n.complete(1,true,0,reply(1,0),10);n.pump("peer",1010);yes(plain.size()==1&&!n.extended(),"plain session: no QUERY");
        System.out.println("NativeNavMapTest: "+checks+" checks; QUERY, SCENE2 age, POSE rate/keep-alive, urgent UPDATE, stale, CLEAR, deadline");
    }
}
