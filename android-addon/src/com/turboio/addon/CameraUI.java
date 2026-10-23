package com.turboio.addon;
import android.Manifest;
import android.app.Activity;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.widget.*;

/** 遥控拍照 · TCM1: the phone camera previews on the TVP2 lens; the glasses dial takes the photo. */
final class CameraUI {
    private static final String[] PROFILE_NAMES={"128×72 · 4级灰（最快）","192×108 · 16级灰","256×144 · 4级灰","256×144 · 16级灰（最清楚）"};
    static void show(Activity a){
        CameraPreview.init();SharedPreferences prefs=a.getSharedPreferences("turboio_camera",0);
        EditorialUI.Screen s=new EditorialUI.Screen(a,"遥控拍照");LinearLayout b=s.body;
        b.addView(EditorialUI.text(a,"把手机横放好（多数手机听筒朝左时镜片取景为正；保存的照片按实际方向旋转），在这里开启相机后用眼镜旋钮拍照。镜片显示低帧率压缩取景，照片原图保存在手机相册 Pictures/TurboIO。旋钮：按下快门、旋转变焦、长按退出。需 TVP2 固件。",14,EditorialUI.MUTED));
        TextView state=EditorialUI.text(a,"未开启",14,EditorialUI.LIME);b.addView(state);
        int[] profile={Math.max(0,Math.min(3,prefs.getInt("profile",CameraCodec.DEFAULT_PROFILE)))},delay={Math.max(0,Math.min(3,prefs.getInt("delay",0)))};
        CameraPreview[] session={null};
        Runnable refresh=()->{state.setText(session[0]==null?"未开启":session[0].status());};
        EditorialUI.button(a,b,"开启相机与眼镜取景",true,()->{
            if(session[0]!=null&&session[0].active()){EditorialUI.notice(a,"取景已开启");return;}
            if(a.checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED){a.requestPermissions(new String[]{Manifest.permission.CAMERA},7401);state.setText("正在请求相机权限；允许后再点一次开启。");return;}
            session[0]=new CameraPreview(a,profile[0],delay[0],refresh::run);session[0].start();refresh.run();});
        EditorialUI.button(a,b,"停止取景",false,()->{if(session[0]!=null)session[0].stop();});
        EditorialUI.button(a,b,"清晰度："+PROFILE_NAMES[profile[0]],false,()->{profile[0]=(profile[0]+1)%4;prefs.edit().putInt("profile",profile[0]).apply();EditorialUI.notice(a,"清晰度："+PROFILE_NAMES[profile[0]]+"\n下次开启取景时生效。越清楚越慢。");});
        EditorialUI.button(a,b,"快门延时："+CameraPreview.DELAYS[delay[0]]+" 秒",false,()->{delay[0]=(delay[0]+1)%4;prefs.edit().putInt("delay",delay[0]).apply();EditorialUI.notice(a,"快门延时："+CameraPreview.DELAYS[delay[0]]+" 秒\n下次开启取景时生效。");});
        // Keep the phone awake while this screen is open; a sleeping screen would cut the camera off mid-shoot.
        if(s.dialog.getWindow()!=null)s.dialog.getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        s.dialog.setOnDismissListener(d->{if(session[0]!=null)session[0].stop();});
    }
}
