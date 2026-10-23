package com.turboio.addon;
import java.util.*;

/** TNR3 mini-map wire contract (TVP2 navigation-runtime nav_map.c): body validation, TNV1 wrapping, and the
 * firmware's own screen transform / label culling so the phone can predict which names the lens will show. */
public final class NavMapCodec {
    public static final int SCENE=7,POSE=8,CLEAR=9,SCENE2=10;
    public static final int MAX_PATHS=96,MAX_POINTS=768,MAX_BYTES=4096,MAX_LABELS=4,LABEL_BYTES=32,W=192,H=144;
    private NavMapCodec(){}
    private static int u16(byte[] p,int at){return (p[at]&255)|(p[at+1]&255)<<8;}
    private static long u32(byte[] p,int at){return HexCarrier.u32(p,at);}
    private static boolean pointOk(byte[] p,int at){return Math.abs((short)u16(p,at))<=8192&&Math.abs((short)u16(p,at+2))<=8192;}
    /** Strict UTF-8, printable BMP only, 9 px per ASCII and 16 px otherwise; 0 when invalid or wider than 104 px. */
    public static int textWidth(byte[] p,int off,int n){
        int w=0;
        for(int i=0;i<n;){int a=p[off+i++]&255,c;
            if(a<0x80){if(a<32||a==127)return 0;w+=9;continue;}
            int more=a>=0xc2&&a<=0xdf?1:a>=0xe0&&a<=0xef?2:0;if(more==0||i+more>n)return 0;c=a&((1<<(6-more))-1);
            for(int k=0;k<more;k++){int b=p[off+i++]&255;if((b&0xc0)!=0x80)return 0;c=(c<<6)|(b&63);}
            if(c<(more==1?0x80:0x800)||(c>=0xd800&&c<=0xdfff)||(c>=0x7f&&c<=0x9f)||(c>=0x200b&&c<=0x202e)||(c>=0x2060&&c<=0x206f)||c>=0xfff0)return 0;w+=16;
        }
        return w<=104?w:0;
    }
    public static boolean bodyValid(int op,byte[] p){
        int n=p==null?0:p.length;
        if(op==CLEAR)return n==0;if(p==null)return false;
        if(op==POSE)return n==12&&u32(p,0)!=0&&pointOk(p,4)&&u16(p,8)<360&&u16(p,10)<=4000;
        if((op!=SCENE&&op!=SCENE2)||n<16||n>MAX_BYTES-32||u32(p,0)==0||u16(p,4)<180||u16(p,4)>700||u32(p,12)!=0)return false;
        int paths=u16(p,6),points=u16(p,8),labels=u16(p,10),sum=0;
        if(paths==0||paths>MAX_PATHS||points>MAX_POINTS||labels>MAX_LABELS||(op==SCENE&&labels!=0)||n!=16+8*paths+4*points+(op==SCENE2?40*labels+12:0))return false;
        for(int i=0;i<paths;i++){int q=16+8*i,count=u16(p,q);if(count<2||count>points-sum||(p[q+2]&255)>6||((p[q+3]&255)&~3)!=0||p[q+4]<-8||p[q+4]>8||p[q+5]!=0||u16(p,q+6)!=0)return false;sum+=count;}
        if(sum!=points)return false;for(int i=0;i<points;i++)if(!pointOk(p,16+8*paths+4*i))return false;
        if(op==SCENE2){
            for(int i=0;i<labels;i++){int q=16+8*paths+4*points+40*i,len=p[q+4]&255;if(!pointOk(p,q)||len==0||len>=LABEL_BYTES||p[q+5]!=0||u16(p,q+6)!=0||textWidth(p,q+8,len)==0)return false;for(int j=len;j<LABEL_BYTES;j++)if(p[q+8+j]!=0)return false;}
            byte[] pose=Arrays.copyOfRange(p,n-12,n);if(!bodyValid(POSE,pose)||u32(pose,0)!=u32(p,0))return false;
        }
        return true;
    }
    /** TNV1 packet: header, CRC over the whole packet with the CRC field zero; null when the body is invalid. */
    public static byte[] wrap(int op,long sid,long seq,byte[] body){
        int n=body==null?0:body.length;
        if(sid<=0||sid>0xffffffffL||seq<=0||seq>0xffffffffL||n+32>MAX_BYTES||!bodyValid(op,op==CLEAR&&body==null?new byte[0]:body))return null;
        byte[] out=new byte[n+32];out[0]='T';out[1]='N';out[2]='V';out[3]='1';out[4]=1;out[5]=(byte)op;
        HexCarrier.w32(out,8,sid);HexCarrier.w32(out,12,seq);HexCarrier.w32(out,16,n);if(n>0)System.arraycopy(body,0,out,32,n);HexCarrier.w32(out,20,HexCarrier.crc(out,out.length));return out;
    }
    private static final int[] SIN5={0,1428,2845,4240,5604,6924,8192,9397,10531,11585,12551,13421,14189,14849,15396,15826,16135,16322,16384};
    private static int sine(int a){a%=360;int sign=a>=180?-1:1;a%=180;if(a>90)a=180-a;int i=a/5,r=a%5;return sign*(SIN5[i]+(i<18?(SIN5[i+1]-SIN5[i])*r/5:0));}
    /** Firmware screen transform (Q14 sine, heading-up, origin at 96,101): {x,y}. */
    public static int[] screen(int px,int py,int poseX,int poseY,int heading,int range){
        int x=px-poseX,y=py-poseY,s=sine(heading),c=sine(heading+90);int dx=(x*c-y*s)/16384,dy=(x*s+y*c)/16384;
        return new int[]{(short)(96+dx*192/(range*4)),(short)(101-dy*192/(range*4))};
    }
    /** tnr_labels for a freshly received SCENE2 at the given pose: visible {x,y,width}, in label order. */
    public static List<int[]> labels(byte[] scene2,int poseX,int poseY,int heading){
        List<int[]> out=new ArrayList<>();if(!bodyValid(SCENE2,scene2))return out;
        int paths=u16(scene2,6),points=u16(scene2,8),labels=u16(scene2,10),range=u16(scene2,4);
        for(int i=0;i<labels;i++){int q=16+8*paths+4*points+40*i,w=textWidth(scene2,q+8,scene2[q+4]&255);int[] s=screen((short)u16(scene2,q),(short)u16(scene2,q+2),poseX,poseY,heading,range);int x=s[0]-w/2,y=s[1]-10;
            if(x<3||x+w>189||y<3||y+20>141||(x<111&&x+w>81&&y<114&&y+20>83)||(x<70&&x+w>2&&y<143&&y+20>116))continue;
            boolean overlap=false;for(int[] o:out)if(x<o[0]+o[2]+4&&x+w+4>o[0]&&y<o[1]+24&&y+24>o[1])overlap=true;
            if(!overlap)out.add(new int[]{x,y,w});}
        return out;
    }
}
