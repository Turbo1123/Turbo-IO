package com.turboio.addon;
import android.app.Activity;
import android.widget.*;

/** Settings → glasses menu rows (TVP2). Reads first; switching always carries a fresh glasses token. */
final class MenuUI {
    static void show(Activity a){
        MenuLayout.init();EditorialUI.Screen s=new EditorialUI.Screen(a,"眼镜菜单排数");LinearLayout b=s.body;
        b.addView(EditorialUI.text(a,"TVP2 菜单默认三排三列（每页九项），可切换为两排三列（每页六项），由眼镜保存。先读取当前布局；每次切换都会先确认眼镜凭证，3 秒无回执即停止，不自动重试。",14,EditorialUI.MUTED));
        TextView state=EditorialUI.text(a,MenuLayout.status(),15,EditorialUI.LIME);b.addView(state);
        Runnable refresh=()->a.runOnUiThread(()->state.setText(MenuLayout.status()));MenuLayout.listen(refresh);
        EditorialUI.button(a,b,"读取眼镜当前布局",false,MenuLayout::query);
        EditorialUI.button(a,b,"切换为三排（每页九项）",true,()->MenuLayout.choose(3));
        EditorialUI.button(a,b,"切换为两排（每页六项）",false,()->MenuLayout.choose(2));
        s.dialog.setOnDismissListener(d->MenuLayout.detach());MenuLayout.query();
    }
}
