package com.turboio.addon;
import android.content.Context;
import android.graphics.*;
import android.text.*;
import android.view.View;
import java.util.*;
import static com.turboio.addon.BoundedJson.*;

/** Same 540x180 coordinates as the SDK; phone fonts are a preview, not LVGL glyphs. */
final class AppPreview extends View {
    private final Map<String,Object> doc;private int page;private final Map<String,Bitmap> images=new HashMap<>();
    AppPreview(Context c,AppCodec.Package pkg){super(c);doc=pkg.document;List<Object> pages=list(doc.get("pages"));for(int i=0;i<pages.size();i++)if(map(pages.get(i)).get("id").equals(doc.get("entry")))page=i;setContentDescription(pkg.name+"布局预览");for(Map.Entry<String,Object> e:map(doc.get("assets")).entrySet()){Map<String,Object> a=map(e.getValue());int w=((Number)a.get("width")).intValue(),h=((Number)a.get("height")).intValue();byte[] data=Base64.getDecoder().decode((String)a.get("pixels"));int[] pixels=new int[w*h];for(int i=0;i<pixels.length;i++)pixels[i]=(data[i/8]&(128>>>(i%8)))!=0?0xff5dff65:0xff000000;images.put(e.getKey(),Bitmap.createBitmap(pixels,w,h,Bitmap.Config.ARGB_8888));}setOnClickListener(v->{page=(page+1)%pages.size();invalidate();});}
    protected void onMeasure(int w,int h){int width=MeasureSpec.getSize(w);setMeasuredDimension(width,width/3);}
    protected void onDraw(Canvas canvas){super.onDraw(canvas);canvas.drawColor(Color.BLACK);canvas.save();canvas.scale(getWidth()/540f,getHeight()/180f);Paint p=new Paint(Paint.ANTI_ALIAS_FLAG);p.setColor(0xff5dff65);p.setStrokeWidth(1);Map<String,Object> current=map(list(doc.get("pages")).get(page));for(Object o:list(current.get("components"))){Map<String,Object> c=map(o);float x=n(c,"x"),y=n(c,"y"),w=n(c,"w"),h=n(c,"h");String kind=(String)c.get("kind");canvas.save();canvas.clipRect(x,y,x+w,y+h);p.setStyle(Paint.Style.FILL);p.setColor(0xff5dff65);
            if(kind.equals("frame")||kind.equals("button")){p.setStyle(Paint.Style.STROKE);canvas.drawRoundRect(x+1,y+1,x+w-1,y+h-1,4,4,p);p.setStyle(Paint.Style.FILL);}
            if(kind.equals("text")||kind.equals("button")){TextPaint text=new TextPaint(p);text.setTextSize(n(c,"font"));String s=(String)c.get("text");StaticLayout layout=StaticLayout.Builder.obtain(s,0,s.length(),text,(int)w).setIncludePad(false).setAlignment(kind.equals("button")?Layout.Alignment.ALIGN_CENTER:Layout.Alignment.ALIGN_NORMAL).build();canvas.translate(x,y+2);layout.draw(canvas);}
            else if(kind.equals("progress")){p.setColor(0xff193d1b);canvas.drawRoundRect(x,y,x+w,y+h,h/2,h/2,p);p.setColor(0xff5dff65);canvas.drawRoundRect(x,y,x+w*n(c,"value")/100f,y+h,h/2,h/2,p);}
            else if(kind.equals("image")){Bitmap b=images.get(c.get("asset"));if(b!=null)canvas.drawBitmap(b,x,y,p);}canvas.restore();}canvas.restore();}
    private static int n(Map<String,Object> d,String k){return ((Number)d.get(k)).intValue();}
}
