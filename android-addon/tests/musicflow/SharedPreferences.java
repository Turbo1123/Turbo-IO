package android.content;
import java.util.*;
public class SharedPreferences {final Map<String,Long> values=new HashMap<>();public long getLong(String k,long d){return values.getOrDefault(k,d);}public Editor edit(){return new Editor();}public class Editor{public Editor putLong(String k,long v){values.put(k,v);return this;}public boolean commit(){return true;}public void apply(){}}}
