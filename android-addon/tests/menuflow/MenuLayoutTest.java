package com.turboio.addon;
import android.os.SystemClock;

/** TVP2 menu rows: query → token → set, with no stale token, no resend and no foreign reply. */
public final class MenuLayoutTest {
    static int n;static void ok(boolean b){n++;if(!b)throw new AssertionError("menu flow "+n+" "+MenuLayout.status());}
    static byte[] last(){return HexCarrier.unwrap(NativeTransfer.packets.get(NativeTransfer.packets.size()-1),"TML:",32,32);}
    /** Glasses reply to the last command, as tml_reply would build it. */
    static void reply(String from,int rows,int result,long token,long generation){byte[] q=last();byte[] p=new byte[32];p[0]='T';p[1]='M';p[2]='A';p[3]='2';p[4]=1;p[5]=q[5];p[6]=(byte)rows;p[7]=(byte)result;
        System.arraycopy(q,8,p,8,4);HexCarrier.w32(p,12,token);HexCarrier.w32(p,16,generation);System.arraycopy(q,20,p,20,4);p[24]=28;p[25]=2;p[26]=(byte)220;HexCarrier.w32(p,28,HexCarrier.crc(p,28));
        NativeTransfer.receiver.message(from,HexCarrier.wrap("TMA:",p));}
    static int op(){return last()[5];}static long field(int at){return HexCarrier.u32(last(),at);}
    public static void main(String[] a){MenuLayout.init();
        MenuLayout.query();ok(MenuLayout.busy()&&op()==MenuCodec.QUERY&&NativeTransfer.packets.size()==1);
        reply("test-peer",3,MenuCodec.OK,9,5);ok(!MenuLayout.busy()&&MenuLayout.rows()==3&&NativeTransfer.lease.isEmpty()&&MenuLayout.status().contains("3排"));
        MenuLayout.choose(2);ok(op()==MenuCodec.SET&&last()[6]==2&&field(12)==9&&field(16)==5);
        reply("test-peer",2,MenuCodec.OK,0,6);ok(MenuLayout.rows()==2&&MenuLayout.status().contains("已保存")&&NativeTransfer.lease.isEmpty());
        // The query token is single-use and expires after 110 s: a later choose queries first.
        int before=NativeTransfer.packets.size();MenuLayout.choose(3);ok(op()==MenuCodec.QUERY&&NativeTransfer.packets.size()==before+1);
        reply("test-peer",2,MenuCodec.OK,11,6);ok(op()==MenuCodec.SET&&last()[6]==3&&field(12)==11);reply("test-peer",3,MenuCodec.OK,0,7);ok(MenuLayout.rows()==3);
        MenuLayout.query();reply("test-peer",3,MenuCodec.OK,12,7);SystemClock.now+=110001;before=NativeTransfer.packets.size();MenuLayout.choose(2);ok(op()==MenuCodec.QUERY&&NativeTransfer.packets.size()==before+1);
        // No reply within 3 s: unknown result, nothing resent.
        before=NativeTransfer.packets.size();NativeTransfer.MAIN.expire();ok(!MenuLayout.busy()&&MenuLayout.status().contains("未回执")&&NativeTransfer.packets.size()==before&&MenuLayout.rows()==0);
        // Foreign or uncorrelated replies are ignored while waiting.
        MenuLayout.query();reply("other-glasses",3,MenuCodec.OK,13,7);ok(MenuLayout.busy());
        byte[] q=last();q[8]^=1;NativeTransfer.packets.add(HexCarrier.wrap("TML:",q));reply("test-peer",3,MenuCodec.OK,13,7);ok(MenuLayout.busy());NativeTransfer.packets.remove(NativeTransfer.packets.size()-1);
        reply("test-peer",3,MenuCodec.OK,13,7);ok(!MenuLayout.busy()&&MenuLayout.rows()==3);
        // Glasses refusals map to the iOS notes and never leave a usable token.
        String[] notes={"不允许修改","凭证已过期","保存/读取失败"};int[] codes={MenuCodec.BLOCKED,MenuCodec.SESSION,MenuCodec.STORAGE};
        for(int i=0;i<3;i++){MenuLayout.query();reply("test-peer",3,MenuCodec.OK,20+i,7);MenuLayout.choose(2);reply("test-peer",3,codes[i],0,7);ok(MenuLayout.status().contains(notes[i])&&MenuLayout.rows()==0&&NativeTransfer.lease.isEmpty());}
        // A SET reply that does not show the requested rows is a mismatch, not success.
        MenuLayout.query();reply("test-peer",3,MenuCodec.OK,30,7);MenuLayout.choose(2);reply("test-peer",3,MenuCodec.OK,0,8);ok(MenuLayout.status().contains("不一致")&&MenuLayout.rows()==0);
        // Send failure releases the lease.
        MenuLayout.query();NativeTransfer.fail.run();ok(!MenuLayout.busy()&&NativeTransfer.lease.isEmpty()&&MenuLayout.status().contains("发送未确认"));
        // Only 2 or 3 rows; never sent while another owner holds the link.
        before=NativeTransfer.packets.size();MenuLayout.choose(4);ok(NativeTransfer.packets.size()==before);
        NativeTransfer.lease="someone-else";MenuLayout.query();ok(NativeTransfer.packets.size()==before&&!MenuLayout.busy());NativeTransfer.lease="";
        System.out.println("MenuLayoutTest: "+n+" checks; token, freshness, timeout, foreign reply, refusals, lease");
    }
}
