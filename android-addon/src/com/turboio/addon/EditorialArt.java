package com.turboio.addon;
import android.animation.ValueAnimator;
import android.app.Activity;
import android.graphics.*;
import android.os.*;
import android.util.LruCache;
import android.view.View;
import java.io.*;
import java.util.concurrent.*;

/** Reuses approved iOS art. Bounded shared cache, one atlas, no per-frame bitmap churn. */
final class EditorialArt extends View {
    private static final LruCache<String,Bitmap> CACHE=new LruCache<String,Bitmap>(16*1024){protected int sizeOf(String k,Bitmap b){return b.getAllocationByteCount()/1024;}};
    private static final ExecutorService IO=Executors.newSingleThreadExecutor();
    private final String asset;private final boolean hero;private Bitmap bitmap;private ValueAnimator animator;private int frame=23,generation;
    private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);
    EditorialArt(Activity a,String name,boolean animate){super(a);asset=name;hero=animate;setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);}
    protected void onAttachedToWindow(){super.onAttachedToWindow();int token=++generation;Bitmap hit=CACHE.get(asset);if(hit!=null){accept(hit);return;}final android.content.Context context=getContext().getApplicationContext();IO.execute(()->{Bitmap b=null;try{BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;try(InputStream in=context.getAssets().open("turboio/art/"+asset+".png")){BitmapFactory.decodeStream(in,null,bounds);}int cap=hero?1536:768;BitmapFactory.Options opts=new BitmapFactory.Options();opts.inSampleSize=1;while(Math.max(bounds.outWidth,bounds.outHeight)/opts.inSampleSize>cap)opts.inSampleSize*=2;try(InputStream in=context.getAssets().open("turboio/art/"+asset+".png")){b=BitmapFactory.decodeStream(in,null,opts);}if(b!=null)CACHE.put(asset,b);}catch(IOException ignored){}Bitmap ready=b;new Handler(Looper.getMainLooper()).post(()->{if(token==generation&&isAttachedToWindow())accept(ready);});});}
    private void accept(Bitmap b){bitmap=b;if(hero&&ValueAnimator.areAnimatorsEnabled()&&b!=null){animator=ValueAnimator.ofInt(0,23);animator.setDuration(1200);animator.addUpdateListener(a->{frame=(int)a.getAnimatedValue();invalidate();});animator.start();}invalidate();}
    protected void onDetachedFromWindow(){generation++;if(animator!=null){animator.cancel();animator.removeAllUpdateListeners();animator=null;}bitmap=null;super.onDetachedFromWindow();}
    protected void onWindowVisibilityChanged(int v){super.onWindowVisibilityChanged(v);if(v!=VISIBLE&&animator!=null){animator.cancel();frame=23;}}
    protected void onDraw(Canvas c){if(bitmap==null)return;int w=hero?bitmap.getWidth()/6:bitmap.getWidth(),h=hero?bitmap.getHeight()/4:bitmap.getHeight();int x=hero?(frame%6)*w:0,y=hero?(frame/6)*h:0;boolean contain=hero||asset.equals("focus-tomato-v2");float scale=contain?Math.min((float)getWidth()/w,(float)getHeight()/h):Math.max((float)getWidth()/w,(float)getHeight()/h);float dw=w*scale,dh=h*scale;c.drawBitmap(bitmap,new Rect(x,y,x+w,y+h),new RectF((getWidth()-dw)/2,(getHeight()-dh)/2,(getWidth()+dw)/2,(getHeight()+dh)/2),paint);}
}
