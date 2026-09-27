package android.content;import java.util.*;
public class Context {
 public final Prefs prefs=new Prefs();public Context getApplicationContext(){return this;}public SharedPreferences getSharedPreferences(String n,int mode){return prefs;}public Object startForegroundService(Intent i){return null;}
 public static final class Prefs implements SharedPreferences {public boolean fail;public Map<String,Object> m=new HashMap<>(),disk=new HashMap<>();public boolean getBoolean(String k,boolean d){Object o=m.get(k);return o==null?d:(Boolean)o;}public String getString(String k,String d){Object o=m.get(k);return o==null?d:(String)o;}public Editor edit(){return new Editor(){Map<String,Object> changes=new HashMap<>();public Editor putBoolean(String k,boolean v){changes.put(k,v);return this;}public Editor putString(String k,String v){changes.put(k,v);return this;}public boolean commit(){m.putAll(changes);if(fail)return false;disk.putAll(changes);return true;}};}}
}
