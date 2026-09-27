package android.content;
public interface SharedPreferences {boolean getBoolean(String k,boolean d);String getString(String k,String d);Editor edit();interface Editor {Editor putBoolean(String k,boolean v);Editor putString(String k,String v);boolean commit();}}
