package com.turboio.addon;
import android.app.*;
import android.widget.*;
import java.util.*;

/** 设置 → 滴滴出行（沙箱） (iOS RideUI): sandbox key, search pickup and destination among sandbox candidates, estimate,
 * prepare a glasses confirmation card, confirm on the phone, refresh / cancel the sandbox order, demo cards. */
final class RideUI {
    private final Activity a;private final DrService service;private EditorialUI.Screen s;private TextView keyLabel,note,fromLabel,toLabel;private LinearLayout placeBox,productBox;private EditText city;
    private String fromId,toId,fromName,toName;private boolean pickingFrom=true;
    private RideUI(Activity a){this.a=a;service=Ride.service(a);}
    static void show(Activity a){new RideUI(a).open();}
    private boolean gone(){return a.isFinishing()||a.isDestroyed()||!s.dialog.isShowing();}
    private void open(){
        s=new EditorialUI.Screen(a,"滴滴出行");LinearLayout b=s.body;
        b.addView(EditorialUI.text(a,"先在沙箱练一遍\n眼镜确认，手机执行。不会实际叫车。",15,EditorialUI.MUTED));
        b.addView(EditorialUI.text(a,"环境与密钥",17,EditorialUI.INK));keyLabel=EditorialUI.text(a,"",14,EditorialUI.INK);b.addView(keyLabel);
        EditorialUI.button(a,b,"沙箱 API Key",false,this::configure);
        b.addView(EditorialUI.text(a,"调试模式 · 沙箱\n生产模式未开放，所有接口固定走沙箱",13,EditorialUI.MUTED));
        b.addView(EditorialUI.text(a,"选择行程",17,EditorialUI.INK));
        city=new EditText(a);city.setSingleLine();city.setHint("城市，例如北京市");city.setTextColor(EditorialUI.INK);city.setHintTextColor(EditorialUI.MUTED);b.addView(city);
        fromLabel=EditorialUI.text(a,"起点：未选",14,EditorialUI.INK);b.addView(fromLabel);EditorialUI.button(a,b,"搜索上车点",false,()->search(true));
        toLabel=EditorialUI.text(a,"终点：未选",14,EditorialUI.INK);b.addView(toLabel);EditorialUI.button(a,b,"搜索目的地",false,()->search(false));
        b.addView(EditorialUI.text(a,"沙箱可能返回固定地点，请按实际候选选择",13,EditorialUI.MUTED));placeBox=EditorialUI.column(a);b.addView(placeBox);
        EditorialUI.button(a,b,"获取沙箱报价",true,this::estimate);
        b.addView(EditorialUI.text(a,"预估车型 · 点击进入确认（只准备确认卡片，不直接叫车）",13,EditorialUI.MUTED));productBox=EditorialUI.column(a);b.addView(productBox);
        b.addView(EditorialUI.text(a,"确认与状态",17,EditorialUI.INK));note=EditorialUI.text(a,"",14,EditorialUI.LIME);b.addView(note);
        EditorialUI.button(a,b,"在手机确认本次沙箱操作",true,()->{service.confirmOnPhone();render();});
        b.addView(EditorialUI.text(a,"也可在眼镜用旋钮选确认后短按，无需手机再次确认",13,EditorialUI.MUTED));
        EditorialUI.button(a,b,"刷新沙箱订单",false,()->service.tool(args("action","status"),r->render()));
        EditorialUI.button(a,b,"准备取消沙箱订单（显示取消确认，未经确认不调用取消接口）",false,()->service.tool(args("action","prepare_cancel"),r->render()));
        EditorialUI.button(a,b,"在眼镜显示当前卡片",false,()->{service.showOnGlasses();render();});
        EditorialUI.button(a,b,"退出眼镜页面（只退出页面，不取消订单）",false,Ride::close);
        EditorialUI.button(a,b,"切换眼镜演示卡片（无网络）",false,()->{service.previewNext();render();});
        b.addView(EditorialUI.text(a,"演示：轮流显示待命、报价、接驾、行程等示例。无确认按钮、不调用订单接口。",13,EditorialUI.MUTED));
        Ride.listen(()->{if(!gone())render();});s.dialog.setOnDismissListener(d->Ride.listen(null));render();
    }
    private static Map<String,Object> args(Object...kv){Map<String,Object> r=new LinkedHashMap<>();for(int i=0;i<kv.length;i+=2)r.put((String)kv[i],kv[i+1]);return r;}
    private void render(){
        keyLabel.setText(Ride.ready(a)?"已保存于本机 · 点击替换，不显示原值":"点此填写 · 不写入源码或日志");
        DrWire.Scene sc=service.scene();note.setText(service.note()+"\n当前卡片："+sc.title+" · "+sc.metric+(service.pending()?"\n等待确认（60 秒内有效）":""));
    }
    private void configure(){
        EditText k=new EditText(a);k.setHint("粘贴沙箱 Key");k.setSingleLine();k.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD);
        new AlertDialog.Builder(a).setTitle("滴滴沙箱 Key").setMessage("仅保存到此手机本机加密存储。本版不支持生产环境。").setView(k).setNegativeButton("取消",null)
            .setPositiveButton("保存",(d,w)->{String v=k.getText().toString().trim();k.setText("");if(!Ride.saveKey(a,v))EditorialUI.notice(a,"Key 无效，未保存。");else{service.invalidateConsent();render();}}).show();
    }
    private void search(boolean from){
        String c=city.getText().toString().trim();if(c.isEmpty()){EditorialUI.notice(a,"先选城市，再搜索地点");return;}
        EditText q=new EditText(a);q.setSingleLine();q.setHint("地点或地址");
        new AlertDialog.Builder(a).setTitle(from?"查找上车点":"查找目的地").setMessage("选择返回的候选地点；沙箱可能返回固定样例。").setView(q).setNegativeButton("取消",null).setPositiveButton("搜索",(d,w)->{
            String text=q.getText().toString().trim();if(text.isEmpty()||text.length()>120)return;pickingFrom=from;
            service.tool(args("action","search","city",c,"query",text),r->{if(gone())return;render();placeBox.removeAllViews();Object places=r.get("places");
                placeBox.addView(EditorialUI.text(a,pickingFrom?"搜索结果 · 点击设为起点":"搜索结果 · 点击设为终点",13,EditorialUI.MUTED));
                if(places instanceof List)for(Object o:(List<?>)places){Map<?,?> p=(Map<?,?>)o;TextView row=EditorialUI.text(a,String.valueOf(p.get("name"))+"\n沙箱测试地点 · 不代表真实搜索命中",14,EditorialUI.INK);row.setPadding(0,10,0,10);
                    row.setOnClickListener(v->{if(pickingFrom){fromId=(String)p.get("id");fromName=(String)p.get("name");fromLabel.setText("起点："+fromName);}else{toId=(String)p.get("id");toName=(String)p.get("name");toLabel.setText("终点："+toName);}placeBox.removeAllViews();});placeBox.addView(row);}});}).show();
    }
    private void estimate(){
        if(fromId==null||toId==null){EditorialUI.notice(a,"请先选定起点和终点");return;}
        service.tool(args("action","estimate","from_id",fromId,"to_id",toId),r->{if(gone())return;render();productBox.removeAllViews();Object items=r.get("products");
            if(items instanceof List)for(Object o:(List<?>)items){Map<?,?> p=(Map<?,?>)o;TextView row=EditorialUI.text(a,p.get("name")+" · "+p.get("price"),15,EditorialUI.INK);row.setPadding(0,10,0,10);
                row.setOnClickListener(v->service.tool(args("action","prepare","product_id",p.get("id")),x->render()));productBox.addView(row);}});
    }
}
