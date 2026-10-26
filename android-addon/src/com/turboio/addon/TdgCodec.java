package com.turboio.addon;

/** TVP2 glasses diagnostics: TDQ1 start/stop commands (sent as a file) and TDG1 128-byte samples.
 * Mirrors diagnostics-v1 command.c / diagnostics.c. */
public final class TdgCodec {
    public static final int START=1,STOP=2,COMMAND_BYTES=24,SAMPLE_BYTES=128,METRICS=20,RESERVED=19,RING=64;
    public static final long MAX_LEASE_MS=600000;
    /** Report names in TDMetric order (TD_RESERVED excluded), as the iOS report uses them. */
    public static final String[] NAMES={"lv_configured_bytes","lv_used_bytes","lv_peak_bytes","lv_free_bytes","lv_largest_free_bytes","system_arena_bytes","system_used_bytes","system_peak_bytes","system_free_bytes","system_largest_free_bytes","instrumented_owned_bytes","instrumented_owned_peak_bytes","allocation_failures","rx_packets","rx_bytes","rx_max_ms","render_submissions","render_max_ms","errors"};
    private TdgCodec(){}
    public static final class Sample {
        public final long session,sequence,tickMs,probeMs,valid,build,eventCount,eventsLost,flags;public final long[] values=new long[METRICS];
        private Sample(byte[] p){session=HexCarrier.u32(p,8);sequence=HexCarrier.u32(p,12);tickMs=HexCarrier.u32(p,16);probeMs=HexCarrier.u32(p,20);valid=HexCarrier.u32(p,24);build=HexCarrier.u32(p,28);
            for(int i=0;i<METRICS;i++)values[i]=HexCarrier.u32(p,32+4*i);eventCount=HexCarrier.u32(p,112);eventsLost=HexCarrier.u32(p,116);flags=HexCarrier.u32(p,120);}
        public boolean measured(int i){return (valid&(1L<<i))!=0;}
    }
    private static boolean u32(long v){return v>=0&&v<=0xffffffffL;}
    public static byte[] command(int op,long session,long sequence,long leaseMs){
        boolean ok=u32(session)&&session!=0&&u32(sequence)&&sequence!=0&&(op==START&&leaseMs>0&&leaseMs<=MAX_LEASE_MS||op==STOP&&leaseMs==0);
        if(!ok)throw new IllegalArgumentException("diagnostics command");
        byte[] p=new byte[COMMAND_BYTES];p[0]='T';p[1]='D';p[2]='Q';p[3]='1';p[4]=1;p[5]=(byte)op;
        HexCarrier.w32(p,8,session);HexCarrier.w32(p,12,sequence);HexCarrier.w32(p,16,leaseMs);HexCarrier.w32(p,20,HexCarrier.crc(p,20));return p;
    }
    /** Null unless td_decode would accept the bytes. */
    public static Sample sample(byte[] p){
        if(p==null||p.length!=SAMPLE_BYTES||p[0]!='T'||p[1]!='D'||p[2]!='G'||p[3]!='1'||p[4]!=1||p[5]!=0||(p[6]&255)!=128||p[7]!=0||HexCarrier.u32(p,124)!=HexCarrier.crc(p,124))return null;
        Sample s=new Sample(p);if(s.session==0||s.sequence==0||(s.valid>>>RESERVED)!=0)return null;
        for(int i=0;i<METRICS;i++)if(!s.measured(i)&&s.values[i]!=0)return null;
        if(s.eventCount>RING||s.flags>1)return null;return s;
    }
}
