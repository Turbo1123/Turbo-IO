package com.turboio.addon;

/** 540×220 HD frame encoder (port of tar2-display FrameEncoder.m) from an 8-bit luma plane: fit (whole source,
 * black bars) or fill+zoom around a normalized centre, 2/4/8/16 gray levels, four 55-row compressed strips and the
 * displayed-pixel CRC. Area-average resampling stands in for vImage. Pure. */
final class HdEncoder {
    private HdEncoder(){}
    static final class Frame{byte[][] strips;byte[] gray;int bits,sourceWidth,sourceHeight,contentWidth,contentHeight;long pixelCrc,compressedBytes;boolean downgraded;
        int largestPacket(){int m=0;for(byte[] s:strips)m=Math.max(m,s.length+Vp.HEADER);return m;}}

    static Frame encode(byte[] luma,int w,int h,int stride,boolean videoRange,int levels,boolean fit,double zoom,double cx,double cy){
        if(luma==null||(levels!=2&&levels!=4&&levels!=8&&levels!=16)||Double.isNaN(zoom)||Double.isInfinite(zoom)||Double.isNaN(cx)||Double.isInfinite(cx)||Double.isNaN(cy)||Double.isInfinite(cy))return null;
        if(w<=0||h<=0||w>4096||h>2160||stride<w||luma.length<(long)(h-1)*stride+w)return null;
        zoom=Math.max(1,Math.min(4,zoom));cx=Math.max(0,Math.min(1,cx));cy=Math.max(0,Math.min(1,cy));
        int sw=w,sh=h,sx=0,sy=0,dw=Vp.W,dh=Vp.H;
        if(fit){double scale=Math.min(Vp.W/(double)w,Vp.H/(double)h);dw=Math.max(1,Math.min(Vp.W,(int)Math.round(w*scale)));dh=Math.max(1,Math.min(Vp.H,(int)Math.round(h*scale)));}
        else{double scale=Math.max(Vp.W/(double)w,Vp.H/(double)h)*zoom;sw=Math.max(1,Math.min(w,(int)Math.round(Vp.W/scale)));sh=Math.max(1,Math.min(h,(int)Math.round(Vp.H/scale)));sx=(int)Math.round((w-sw)*cx);sy=(int)Math.round((h-sh)*cy);}
        byte[] gray=new byte[Vp.W*Vp.H];int ox=(Vp.W-dw)/2,oy=(Vp.H-dh)/2;
        for(int y=0;y<dh;y++){int y0=sy+(int)((long)y*sh/dh),y1=Math.max(y0+1,sy+(int)((long)(y+1)*sh/dh));
            for(int x=0;x<dw;x++){int x0=sx+(int)((long)x*sw/dw),x1=Math.max(x0+1,sx+(int)((long)(x+1)*sw/dw));long sum=0;
                for(int yy=y0;yy<y1;yy++){int row=yy*stride;for(int xx=x0;xx<x1;xx++)sum+=luma[row+xx]&255;}
                int v=(int)((sum+(long)(y1-y0)*(x1-x0)/2)/((long)(y1-y0)*(x1-x0)));
                // Black bars stay black even with limited-range sources.
                if(videoRange)v=Math.max(0,Math.min(255,(v-16)*255/219));
                int q=(v*(levels-1)+127)/255;if(levels==8)q=(q*15+3)/7;
                gray[(oy+y)*Vp.W+ox+x]=(byte)(q*255/(levels==8?15:levels-1));}}
        int bits=levels<=4?2:4,per=8/bits,max=(1<<bits)-1;byte[][] strips=new byte[(Vp.H+Vp.HD_ROWS-1)/Vp.HD_ROWS][];long total=0;
        for(int y=0,s=0;y<Vp.H;y+=Vp.HD_ROWS,s++){int rows=Math.min(Vp.HD_ROWS,Vp.H-y),count=Vp.W*rows;byte[] packed=new byte[count*bits/8];
            for(int i=0;i<count;i++){int q=(gray[y*Vp.W+i]&255)*max/255;packed[i/per]|=(byte)(q<<(8-bits-bits*(i%per)));}
            byte[] c=Vp.compress(packed,0,packed.length,Vp.COMP_MAX);if(c==null)return null;strips[s]=c;total+=c.length;}
        Frame f=new Frame();f.strips=strips;f.gray=gray;f.bits=bits;f.pixelCrc=Vp.pixelsCrc(gray,Vp.W);f.sourceWidth=w;f.sourceHeight=h;f.contentWidth=dw;f.contentHeight=dh;f.compressedBytes=total;return f;
    }
    /** encode, re-encoded at 4 levels when a 16/8-level strip would not fit the Android 8 KiB message lane. */
    static Frame encodeForLane(byte[] luma,int w,int h,int stride,boolean videoRange,int levels,boolean fit,double zoom,double cx,double cy){
        Frame f=encode(luma,w,h,stride,videoRange,levels,fit,zoom,cx,cy);
        if(f==null||f.largestPacket()<=Vp.LANE||levels<=4)return f;
        Frame g=encode(luma,w,h,stride,videoRange,4,fit,zoom,cx,cy);if(g!=null)g.downgraded=true;return g;
    }
}
