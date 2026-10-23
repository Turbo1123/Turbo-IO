package android.content;
import java.io.File;import java.util.*;
/** Journal fake: commit() persists to `disk` unless `fail` is set. */
public class Context {
 public final Prefs prefs=new Prefs();
 public Context getApplicationContext(){return this;}
 public SharedPreferences getSharedPreferences(String n,int mode){return prefs;}
 public File getExternalFilesDir(String type){return null;}
 public File getFilesDir(){return new File("/nonexistent-turboio-test");}
 public android.content.res.AssetManager getAssets(){return new android.content.res.AssetManager();}
 public ComponentName startForegroundService(Intent i){return null;}
 public static final class Prefs implements SharedPreferences {
  public boolean fail;public final Map<String,Object> disk=new HashMap<>();
  public boolean getBoolean(String k,boolean d){Object o=disk.get(k);return o==null?d:(Boolean)o;}
  public String getString(String k,String d){Object o=disk.get(k);return o==null?d:(String)o;}
  public Editor edit(){Map<String,Object> staged=new HashMap<>();return new Editor(){
   public Editor putBoolean(String k,boolean v){staged.put(k,v);return this;}
   public Editor putString(String k,String v){staged.put(k,v);return this;}
   public boolean commit(){if(fail)return false;disk.putAll(staged);return true;}
   public void apply(){if(!fail)disk.putAll(staged);}};}
 }
}
