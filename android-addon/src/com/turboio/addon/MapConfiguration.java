package com.turboio.addon;
import android.app.*;
import android.content.*;
import android.content.pm.*;
import android.text.InputType;
import android.widget.*;
import java.security.MessageDigest;
import java.util.Locale;

/** Re-signed apps require the user's own Android package+certificate-bound key. */
final class MapConfiguration {
    static boolean ready(Context c){try{return SecretStore.get(c,"amap_android_key").matches("[a-fA-F0-9]{32}");}catch(Exception e){return false;}}
    static void apply(Context c)throws Exception{String key=SecretStore.get(c,"amap_android_key");if(!key.matches("[a-fA-F0-9]{32}"))throw new IllegalStateException("AMap key missing");NavReflect.call(NavReflect.type("com.amap.api.maps.MapsInitializer"),"setApiKey",key);NavReflect.call(NavReflect.type("com.amap.api.location.AMapLocationClient"),"setApiKey",key);Object settings=NavReflect.call(NavReflect.type("com.amap.api.services.core.ServiceSettings"),"getInstance");NavReflect.call(settings,"setApiKey",key);}
    static String identity(Context c){try{PackageInfo p=c.getPackageManager().getPackageInfo(c.getPackageName(),PackageManager.GET_SIGNING_CERTIFICATES);android.content.pm.Signature[] signatures=p.signingInfo.getApkContentsSigners();if(signatures.length!=1)return c.getPackageName()+"\n签名数量异常，请自行核对";byte[] sha=MessageDigest.getInstance("SHA-1").digest(signatures[0].toByteArray());StringBuilder b=new StringBuilder();for(byte v:sha){if(b.length()>0)b.append(':');b.append(String.format(Locale.ROOT,"%02X",v&255));}return "包名："+c.getPackageName()+"\n当前安装签名 SHA-1：\n"+b;}catch(Exception e){return "无法读取当前签名，请使用 apksigner 验证";}}
    static void show(Activity a){EditorialUI.Screen s=new EditorialUI.Screen(a,"Android 高德配置");s.body.addView(EditorialUI.text(a,"iOS / 鸿蒙 Key 不能直接替代 Android Key。重签后请按下面包名和签名配置你自己的 Key。",15,EditorialUI.INK));String identity=identity(a);s.body.addView(EditorialUI.text(a,identity,13,EditorialUI.MUTED));EditorialUI.button(a,s.body,"复制包名及签名 SHA-1",false,()->{((ClipboardManager)a.getSystemService(Context.CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("高德Android配置",identity));Toast.makeText(a,"已复制",Toast.LENGTH_SHORT).show();});EditText key=new EditText(a);key.setHint(ready(a)?"已加密保存；留空不修改":"填入你自己的 Android Key");key.setTextColor(EditorialUI.INK);key.setHintTextColor(EditorialUI.MUTED);key.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_PASSWORD);key.setSingleLine();s.body.addView(key);TextView state=EditorialUI.text(a,"不会预填、展示或上传其他端的私人密钥。",13,EditorialUI.MUTED);s.body.addView(state);EditorialUI.button(a,s.body,"加密保存",true,()->{String value=key.getText().toString().trim();if(value.isEmpty()){state.setText("没有修改已保存配置");return;}if(!value.matches("[a-fA-F0-9]{32}")){state.setText("请输入32位高德Key");return;}try{SecretStore.put(a,"amap_android_key",value);key.setText("");state.setText("已加密保存。若地图已经初始化，请重启 App 后使用。");}catch(Exception e){state.setText("保存失败，未改变地图配置");}});}
}
