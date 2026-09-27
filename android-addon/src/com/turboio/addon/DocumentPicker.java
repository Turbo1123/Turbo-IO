package com.turboio.addon;
import android.app.*;
import android.content.*;
import android.os.*;
import java.io.*;
import java.util.concurrent.*;

/** System document picker, no storage permission, no arbitrary path or URI logging. */
@SuppressWarnings("deprecation")
public final class DocumentPicker extends Fragment {
    interface Result {void accept(byte[] bytes);}
    private Result result;private int limit;private boolean launched;
    public DocumentPicker(){}
    static void pick(Activity a,int max,Result result){if(a.getFragmentManager().isStateSaved())return;DocumentPicker f=new DocumentPicker();f.result=result;f.limit=max;a.getFragmentManager().beginTransaction().add(f,"turboio-document-"+System.nanoTime()).commit();}
    public void onResume(){super.onResume();if(launched)return;launched=true;if(result==null){remove();return;}try{Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*");startActivityForResult(i,1);}catch(Exception e){EditorialUI.notice(getActivity(),"没有可用的文件选择器");remove();}}
    public void onActivityResult(int request,int code,Intent data){if(request!=1||code!=Activity.RESULT_OK||data==null||data.getData()==null){remove();return;}Activity a=getActivity();Result callback=result;int cap=limit;android.net.Uri uri=data.getData();new Thread(()->{byte[] bytes=null;try(InputStream in=a.getContentResolver().openInputStream(uri);ByteArrayOutputStream out=new ByteArrayOutputStream()){if(in==null)throw new IOException();byte[] buffer=new byte[4096];int n;while((n=in.read(buffer))!=-1){if(n>cap-out.size())throw new IOException();out.write(buffer,0,n);}bytes=out.toByteArray();}catch(Exception ignored){}byte[] received=bytes;new Handler(Looper.getMainLooper()).post(()->{if(!isAdded()||a.isFinishing())return;if(received==null)EditorialUI.notice(a,"文件读取失败或超过大小限制");else if(callback!=null)callback.accept(received);remove();});},"TurboIO-document").start();}
    private void remove(){result=null;if(isAdded())getFragmentManager().beginTransaction().remove(this).commitAllowingStateLoss();}
    public void onDestroy(){result=null;super.onDestroy();}
}
