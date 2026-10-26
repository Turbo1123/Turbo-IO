package com.turboio.addon;
import android.os.SystemClock;
import java.security.SecureRandom;
import java.util.UUID;

/** TVP2 glasses menu rows (2 or 3). Query issues a single-use token; set must carry it within 110 s.
 * One command at a time, 3 s reply window, no automatic retry. Port of iOS TIOMenuLayoutLink. */
final class MenuLayout {
    private static final SecureRandom RANDOM=new SecureRandom();
    private static String owner="",peer="",note="读取眼镜布局后可切换；需 TVP2 固件";
    private static long token,generation,client,request,confirmedAt;private static int rows,op,target,pendingRows;private static long epoch;
    private static boolean initialized;private static Runnable changed;
    static void init(){if(!initialized){initialized=true;NativeTransfer.receive(MenuLayout::message);}}
    static void listen(Runnable r){changed=r;}static void detach(){changed=null;}
    static String status(){return note;}static boolean busy(){return !owner.isEmpty();}
    static int rows(){return peer.equals(NativeTransfer.connected())?rows:0;}
    private static boolean ready(){return token!=0&&peer.equals(NativeTransfer.connected())&&SystemClock.elapsedRealtime()-confirmedAt<110000&&SystemClock.elapsedRealtime()>=confirmedAt;}
    private static long nonzero(){long v;do{v=RANDOM.nextInt()&0xffffffffL;}while(v==0);return v;}
    private static void mark(String s){note=s;if(changed!=null)changed.run();}
    private static void finish(String s){String old=owner;owner="";request=0;epoch++;NativeTransfer.releaseMessages(old);mark(s);
        int next=pendingRows;pendingRows=0;if(next!=0&&ready())choose(next);}
    static void query(){if(busy())return;peer=NativeTransfer.connected();token=0;rows=0;client=nonzero();send(MenuCodec.QUERY,0);}
    static void choose(int wanted){
        if(wanted!=2&&wanted!=3||busy())return;
        if(!ready()){pendingRows=wanted;query();if(!busy())pendingRows=0;return;}
        long t=token;token=0;send(MenuCodec.SET,wanted,t);
    }
    private static void send(int command,int wanted){send(command,wanted,0);}
    private static void send(int command,int wanted,long withToken){
        String lease=UUID.randomUUID().toString();
        if(peer.isEmpty()||!peer.equals(NativeTransfer.connected())||!NativeTransfer.acquireMessages(lease)){token=0;mark("请连接眼镜、保持 App 前台并结束升级保护");return;}
        owner=lease;request=nonzero();op=command;target=wanted;long mine=++epoch;
        try{
            byte[] wire=HexCarrier.wrap("TML:",MenuCodec.command(command,wanted,request,withToken,command==MenuCodec.SET?generation:0,client));
            mark(command==MenuCodec.QUERY?"正在读取眼镜布局…":"等待眼镜保存布局…");
            NativeTransfer.sendMessage(owner,peer,wire,()->{if(owner.equals(lease)&&epoch==mine){token=0;finish("发送未确认，请重新读取；没有自动重试");}});
            NativeTransfer.MAIN.postDelayed(()->{if(owner.equals(lease)&&epoch==mine){token=0;rows=0;finish("眼镜未回执；需 TVP2 固件。结果未知，请重新读取，不自动重试");}},3000);
        }catch(Exception e){token=0;finish("布局请求未发送："+e.getClass().getSimpleName());}
    }
    private static void message(String from,byte[] bytes){
        MenuCodec.Reply r=MenuCodec.reply(bytes);if(r==null)return;
        if(!busy()||!peer.equals(from)||!peer.equals(NativeTransfer.connected())||r.request!=request||r.client!=client||r.op!=op)return;
        token=0;rows=0;
        if(r.result!=MenuCodec.OK){pendingRows=0;finish(r.result==MenuCodec.STORAGE?"眼镜保存/读取失败，未确认修改；请重新读取":r.result==MenuCodec.SESSION?"设置凭证已过期，请重新读取":"眼镜当前不允许修改布局（升级、折叠或非支持页面）");return;}
        if((op==MenuCodec.QUERY&&r.token==0)||(op==MenuCodec.SET&&(r.token!=0||r.rows!=target))){pendingRows=0;finish("布局回执不一致，请重新读取");return;}
        rows=r.rows;generation=r.generation;confirmedAt=SystemClock.elapsedRealtime();if(op==MenuCodec.QUERY)token=r.token;
        finish("眼镜已确认："+rows+"排 · 每页"+(rows*3)+"项"+(op==MenuCodec.SET?" · 已保存":""));
    }
}
