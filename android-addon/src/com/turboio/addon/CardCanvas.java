package com.turboio.addon;
import android.content.Context;
import android.graphics.*;
import android.text.*;
import android.view.*;
import java.util.*;
import static com.turboio.addon.BoundedJson.*;

final class CardCanvas extends View {
    interface Changed {void selected(int i);void moved(Map<String,Object> doc);}
    private Map<String,Object> doc;private byte[] wire;private final boolean interactive;private Changed callback;int selected=-1;private float downX,downY;private int oldX,oldY;private boolean moved;
    CardCanvas(Context c,Map<String,Object> d,boolean interactive){super(c);this.interactive=interactive;set(d);setContentDescription("仪表盘布局预览；在组件列表中也可选择并编辑");}
    void listen(Changed c){callback=c;}
    void set(Map<String,Object> d){wire=CardCodec.encode(d,CardIcons::pixels);doc=map(read(canonical(d)));if(selected>=list(doc.get("components")).size())selected=-1;invalidate();}
    void select(int i){selected=i;if(callback!=null)callback.selected(i);invalidate();}
    protected void onMeasure(int w,int h){int width=MeasureSpec.getSize(w);setMeasuredDimension(width,Math.round(width*194f/256));}
    protected void onDraw(Canvas canvas){canvas.drawColor(Color.BLACK);canvas.save();canvas.scale(getWidth()/256f,getHeight()/194f);Paint p=new Paint(Paint.ANTI_ALIAS_FLAG);p.setColor(0xff5dff65);int at=8;for(int i=0;i<(wire[4]&255);i++){int type=wire[at]&255,x=wire[at+1]&255,y=wire[at+2]&255,w=wire[at+3]&255,h=wire[at+4]&255,a=wire[at+5]&255,b=wire[at+6]&255,n=AppCodec.u16(wire,at+8);at+=10;canvas.save();canvas.clipRect(x,y,x+w,y+h);p.setColor(0xff5dff65);p.setStyle(Paint.Style.FILL);p.setStrokeWidth(1);
            if(type==1){String text=utf8(Arrays.copyOfRange(wire,at,at+n));TextPaint tp=new TextPaint(p);tp.setTextSize(a);StaticLayout l=StaticLayout.Builder.obtain(text,0,text.length(),tp,w).setAlignment(b==1?Layout.Alignment.ALIGN_CENTER:b==2?Layout.Alignment.ALIGN_OPPOSITE:Layout.Alignment.ALIGN_NORMAL).setIncludePad(false).build();canvas.translate(x,y+1);l.draw(canvas);}
            else if(type==2){p.setAntiAlias(false);for(int j=0;j<w*h;j++)if((wire[at+j/8]&(128>>>(j%8)))!=0)canvas.drawRect(x+j%w,y+j/w,x+j%w+1,y+j/w+1,p);p.setAntiAlias(true);}
            else if(type==3){p.setColor(0xff183e1a);canvas.drawRoundRect(x,y,x+w,y+h,h/2f,h/2f,p);p.setColor(0xff5dff65);canvas.drawRoundRect(x,y,x+w*a/100f,y+h,h/2f,h/2f,p);}
            else if(type==4||type==5){float dx=w/(float)(type==4?n:n-1);for(int j=0;j<n;j++){float yy=y+h-((wire[at+j]&255)/100f)*(h-2);if(type==4)canvas.drawRect(x+j*dx+2,yy,x+(j+1)*dx-2,y+h,p);else if(j>0)canvas.drawLine(x+(j-1)*dx,y+h-((wire[at+j-1]&255)/100f)*(h-2),x+j*dx,yy,p);}}
            else if(type==6)canvas.drawRect(x,y,x+w,y+h,p);else{p.setStyle(Paint.Style.STROKE);canvas.drawRoundRect(x+1,y+1,x+w-1,y+h-1,4,4,p);}canvas.restore();if(interactive&&selected==i){p.setColor(EditorialUI.LIME);p.setStyle(Paint.Style.STROKE);canvas.drawRect(x-1,y-1,x+w+1,y+h+1,p);}at+=n;
        }canvas.restore();}
    public boolean onTouchEvent(MotionEvent e){if(!interactive)return super.onTouchEvent(e);float x=e.getX()*256/getWidth(),y=e.getY()*194/getHeight();List<Object> cs=list(doc.get("components"));if(e.getActionMasked()==MotionEvent.ACTION_DOWN){int hit=-1;for(int i=cs.size()-1;i>=0;i--){Map<String,Object> c=map(cs.get(i));if(x>=n(c,"x")&&x<=n(c,"x")+n(c,"w")&&y>=n(c,"y")&&y<=n(c,"y")+n(c,"h")){hit=i;break;}}select(hit);if(hit<0)return false;Map<String,Object> c=map(cs.get(hit));oldX=n(c,"x");oldY=n(c,"y");downX=x;downY=y;moved=false;getParent().requestDisallowInterceptTouchEvent(true);return true;}
        if(selected<0)return false;Map<String,Object> c=map(cs.get(selected));if(e.getActionMasked()==MotionEvent.ACTION_MOVE){int xx=Math.max(6,Math.min(250-n(c,"w"),Math.round((oldX+x-downX)/2)*2)),yy=Math.max(6,Math.min(188-n(c,"h"),Math.round((oldY+y-downY)/2)*2));c.put("x",xx);c.put("y",yy);moved|=xx!=oldX||yy!=oldY;wire=CardCodec.encode(doc,CardIcons::pixels);invalidate();return true;}if(e.getActionMasked()==MotionEvent.ACTION_UP||e.getActionMasked()==MotionEvent.ACTION_CANCEL){getParent().requestDisallowInterceptTouchEvent(false);if(e.getActionMasked()==MotionEvent.ACTION_CANCEL){c.put("x",oldX);c.put("y",oldY);wire=CardCodec.encode(doc,CardIcons::pixels);invalidate();}else if(moved&&callback!=null)callback.moved(doc);else performClick();return true;}return true;}
    public boolean performClick(){super.performClick();return true;}
    private static int n(Map<String,Object> c,String k){return ((Number)c.get(k)).intValue();}
}
