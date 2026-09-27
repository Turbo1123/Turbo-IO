package com.turboio.addon;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.os.*;
import android.view.*;
import android.view.inputmethod.*;
import android.widget.*;
import java.lang.reflect.InvocationTargetException;
import java.util.*;
import java.util.concurrent.*;

/** Foreground experimental guidance using the host's existing public AMap APIs. */
public final class NavigationUI {
    private static NavigationUI current;
    private final Activity host;private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService network=Executors.newSingleThreadExecutor();
    private Dialog dialog;private LinearLayout box,results,routeBox,mapBox;private TextView state,hud,connection,guidanceState;
    private EditText search,city;private Object mapView,map,locationClient,locationListener;
    private NavCore.Point origin,destination;private String destinationName="",mode="Walk",plannedMode="";
    private long fixAt;private float accuracy;private boolean closed,running,planning,searching,positionValidated;
    private int generation,searchGeneration,stepIndex;private List<NavCore.Step> steps=new ArrayList<>();
    private double distance;private long duration;private NavCore.Point plannedOrigin;
    private final List<Object> nativePaths=new ArrayList<>();private final List<NavCore.Point> routePoints=new ArrayList<>();
    private Application.ActivityLifecycleCallbacks lifecycle;
    private NavSimulation simulation;private Object simulationMarker;private TextView simulationStatus;
    private int simulationSpeed=1,runEpoch;private Button pauseSimulation;private boolean nativeDisplay=true,alwaysOn;
    public static void show(Activity a){if(current!=null){current.dialog.show();return;}current=new NavigationUI(a);current.open();}
    public static void shutdown(){if(current!=null)current.dialog.dismiss();}
    private NavigationUI(Activity a){host=a;}
    private void open(){
        box=TurboStyle.column(host);state=TurboStyle.text(host,"搜索目的地，选择路线，再开启眼镜显示",14,TurboStyle.MUTED);box.addView(state);TurboStyle.gap(host,box,12);
        LinearLayout inputs=TurboStyle.card(host,box,0xffffffff);
        TurboStyle.button(host,inputs,"Android 高德 Key 与签名配置",false,()->MapConfiguration.show(host));
        city=new EditText(host);city.setSingleLine();city.setHint("城市（可选，例如北京）");TurboStyle.field(host,city);inputs.addView(city);
        search=new EditText(host);search.setSingleLine();search.setHint("搜索地点、道路或地址");search.setImeOptions(EditorInfo.IME_ACTION_SEARCH);TurboStyle.field(host,search);inputs.addView(search);
        TurboStyle.button(host,inputs,"搜索目的地",true,()->consent(this::search));
        search.setOnEditorActionListener((v,id,event)->{if(id==EditorInfo.IME_ACTION_SEARCH){consent(this::search);return true;}return false;});
        RadioGroup modes=new RadioGroup(host);modes.setOrientation(0);String[] names={"步行","骑行","驾车"},values={"Walk","Ride","Drive"};
        for(int i=0;i<3;i++){final String value=values[i];RadioButton r=new RadioButton(host);r.setText(names[i]);r.setTextColor(TurboStyle.INK);r.setButtonTintList(android.content.res.ColorStateList.valueOf(TurboStyle.INK));r.setId(View.generateViewId());modes.addView(r,new RadioGroup.LayoutParams(0,TurboStyle.dp(host,50),1));if(i==0)r.setChecked(true);r.setOnClickListener(v->{if(!mode.equals(value)){stopGuidance();mode=value;invalidateRoute();state.setText("已切换出行方式，请重新规划路线");}});}inputs.addView(modes);
        results=TurboStyle.column(host);box.addView(results);
        mapBox=TurboStyle.card(host,box,0xffe8eee8);mapBox.addView(TurboStyle.text(host,"地图将在你同意导航服务后加载\n可长按地图选终点；地图不是示意图",14,TurboStyle.MUTED));
        LinearLayout locate=TurboStyle.column(host);box.addView(locate);TurboStyle.button(host,locate,"定位我的位置",false,()->consent(this::locate));
        routeBox=TurboStyle.column(host);box.addView(routeBox);
        TurboStyle.button(host,box,"规划路线",true,()->consent(this::plan));
        LinearLayout lens=TurboStyle.card(host,box,0xff151218);lens.addView(TurboStyle.text(host,"眼镜显示预览",14,0xffbcd2c4));
        hud=TurboStyle.text(host,"选择一条路线\n转向与距离将在这里显示",23,TurboStyle.LIME);lens.addView(hud);TurboStyle.gap(host,lens,8);
        Switch nativeSwitch=new Switch(host);nativeSwitch.setText("TNV1 原生导航（需要兼容固件）");nativeSwitch.setTextColor(TurboStyle.LIME);nativeSwitch.setChecked(true);lens.addView(nativeSwitch);nativeSwitch.setOnCheckedChangeListener((v,on)->{if(running||!displayPhase().equals("idle")){nativeSwitch.setChecked(nativeDisplay);return;}nativeDisplay=on;});
        Switch power=new Switch(host);power.setText("保持常亮（默认60秒无内容更新息屏）");power.setTextColor(TurboStyle.LIME);lens.addView(power);power.setOnCheckedChangeListener((v,on)->{alwaysOn=on;if(running)offerDisplay(hud.getText().toString());});
        connection=TurboStyle.text(host,NavGlasses.connection()+" · "+displayStatus(),13,0xffd2e6d7);lens.addView(connection);
        guidanceState=TurboStyle.text(host,"尚未开始导航",14,TurboStyle.LIME);lens.addView(guidanceState);
        TurboStyle.button(host,lens,"开始前台导航并显示到眼镜",true,this::begin);
        TurboStyle.gap(host,lens,12);
        lens.addView(TurboStyle.text(host,"模拟导航 · 在家预演整条路线",17,TurboStyle.LIME));
        simulationStatus=TurboStyle.text(host,"不使用模拟 GPS；仅沿当前路线回放，手机与眼镜均标注模拟",13,0xffd2e6d7);lens.addView(simulationStatus);
        Spinner speeds=new Spinner(host);ArrayAdapter<String> speedAdapter=new ArrayAdapter<>(host,android.R.layout.simple_spinner_dropdown_item,new String[]{"1× 原速","2× 加速","4× 加速","8× 快速预演"});speeds.setBackgroundColor(0xffe8eee8);speeds.setAdapter(speedAdapter);speeds.setContentDescription("模拟速度");lens.addView(speeds,new LinearLayout.LayoutParams(-1,TurboStyle.dp(host,48)));
        speeds.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){public void onNothingSelected(AdapterView<?> p){}public void onItemSelected(AdapterView<?> p,View v,int index,long id){simulationSpeed=new int[]{1,2,4,8}[index];if(simulation!=null)simulation.speed(simulationSpeed,SystemClock.elapsedRealtime());}});
        TurboStyle.button(host,lens,"开始模拟导航并显示到眼镜",true,()->begin(true));
        pauseSimulation=TurboStyle.button(host,lens,"暂停模拟",false,()->{});pauseSimulation.setEnabled(false);
        pauseSimulation.setOnClickListener(v->{if(simulation!=null&&running){simulation.pause(!simulation.paused(),SystemClock.elapsedRealtime());pauseSimulation.setText(simulation.paused()?"继续模拟":"暂停模拟");renderSimulation();}});
        TurboStyle.button(host,lens,"停止导航 / 关闭眼镜显示",false,()->{stopGuidance();stopDisplay();});
        TurboStyle.button(host,box,"测试眼镜显示 · 7392（非真实路线）",false,()->new AlertDialog.Builder(host).setTitle("纯显示测试").setMessage("确认眼镜没有录音、字幕、提词或语音任务。仅显示固定测试文字，不开始定位或录音；TNV1模式只发固定示例，测试完请点停止。").setNegativeButton("取消",null).setPositiveButton("眼镜空闲，开始",(d,w)->startDisplay("导航显示测试 7392\n前方右转 80 米\n测试数据 · 非真实路线")).show());
        TurboStyle.button(host,box,"确认眼镜已退出",false,()->new AlertDialog.Builder(host).setMessage("请实际确认眼镜已回首页；此操作不代表设备回执。").setNegativeButton("取消",null).setPositiveButton("已回首页",(d,w)->confirmDisplayIdle()).show());
        TurboStyle.gap(host,box,12);box.addView(TurboStyle.text(host,"研究预览 · 请保持此页前台\n使用宿主已有高德组件；首版为路线 + 定位引导，不含专业导航引擎的车道级指引、实时路况重算或后台服务。定位过期/不准时暂停指引，偏航请重新规划。勿作为驾驶时唯一依据。",12,TurboStyle.MUTED));
        dialog=TurboStyle.screen(host,"导航",box,null);dialog.setOnDismissListener(d->close());
        NavGlasses.listen(()->{if(!closed)connection.setText(NavGlasses.connection()+" · "+displayStatus());});
        NativeNavigation.listen(()->{if(!closed)connection.setText(NavGlasses.connection()+" · "+displayStatus());});
        lifecycle=new Application.ActivityLifecycleCallbacks(){public void onActivityPaused(Activity a){if(a==host&&!closed&&!BackgroundWork.held("导航")){stopGuidance();stopDisplay();if(locationClient!=null)try{NavReflect.call(locationClient,"stopLocation");}catch(Exception ignored){}state.setText("离开前台，定位和眼镜更新已停止");}}public void onActivityResumed(Activity a){}public void onActivityCreated(Activity a,Bundle b){}public void onActivityStarted(Activity a){}public void onActivityStopped(Activity a){}public void onActivitySaveInstanceState(Activity a,Bundle b){}public void onActivityDestroyed(Activity a){if(a==host)dialog.dismiss();}};
        host.getApplication().registerActivityLifecycleCallbacks(lifecycle);main.postDelayed(tick,1000);
    }
    private void consent(Runnable action){
        if(!MapConfiguration.ready(host)){MapConfiguration.show(host);return;}
        if(host.getSharedPreferences("turboio_settings",0).getBoolean("navigation_consent",false)){initMap();action.run();return;}
        new AlertDialog.Builder(host).setTitle("使用地图与定位").setMessage("目的地检索词和起终点位置会交给高德地图服务。Turbo IO 不存储位置历史、不将位置发送给大模型。只在本导航页前台请求定位。是否继续？").setNegativeButton("取消",null).setPositiveButton("同意并继续",(d,w)->{host.getSharedPreferences("turboio_settings",0).edit().putBoolean("navigation_consent",true).apply();initMap();action.run();}).show();
    }
    private void privacy()throws Exception{
        MapConfiguration.apply(host);
        for(String c:new String[]{"com.amap.api.maps.MapsInitializer","com.amap.api.services.core.ServiceSettings","com.amap.api.location.AMapLocationClient"}){
            NavReflect.call(NavReflect.type(c),"updatePrivacyShow",host,true,true);NavReflect.call(NavReflect.type(c),"updatePrivacyAgree",host,true);
        }
    }
    private void initMap(){if(mapView!=null)return;try{privacy();mapView=NavReflect.make("com.amap.api.maps.MapView",host);NavReflect.call(mapView,"onCreate",(Object)null);map=NavReflect.call(mapView,"getMap");mapBox.removeAllViews();mapBox.setPadding(0,0,0,0);mapBox.addView((View)mapView,new LinearLayout.LayoutParams(-1,TurboStyle.dp(host,300)));NavReflect.call(mapView,"onResume");
        Object longClick=NavReflect.proxy("com.amap.api.maps.AMap$OnMapLongClickListener",(n,args)->main.post(()->{try{choose(point(args[0]),"地图选点");}catch(Exception e){error(e);}}));NavReflect.call(map,"setOnMapLongClickListener",longClick);
    }catch(Exception e){map=null;mapBox.removeAllViews();mapBox.addView(TurboStyle.text(host,"地图加载失败，可继续使用搜索列表。需要有效的 Android 高德配置。",14,TurboStyle.MUTED));}}
    private void search(){
        String q=search.getText().toString().trim(),c=city.getText().toString().trim();if(q.isEmpty()){search.setError("请输入目的地");return;}
        if(q.length()>120||c.length()>80){state.setText("搜索内容过长");return;}if(searching)return;
        ((InputMethodManager)host.getSystemService(Context.INPUT_METHOD_SERVICE)).hideSoftInputFromWindow(search.getWindowToken(),0);
        searching=true;int request=++searchGeneration;state.setText("正在搜索…");results.removeAllViews();
        network.execute(()->{try{Object query=NavReflect.make("com.amap.api.services.poisearch.PoiSearch$Query",q,"",c);NavReflect.call(query,"setPageSize",12);Object api=NavReflect.make("com.amap.api.services.poisearch.PoiSearch",host,query);Object result=NavReflect.call(api,"searchPOI");List<?> pois=(List<?>)NavReflect.call(result,"getPois");
            main.post(()->{if(closed||request!=searchGeneration)return;searching=false;state.setText(pois.isEmpty()?"没有搜索结果，请换关键词或城市":"点击目的地，或长按地图选点");for(Object poi:pois)try{String title=(String)NavReflect.call(poi,"getTitle"),snippet=String.valueOf(NavReflect.call(poi,"getSnippet"));NavCore.Point p=point(NavReflect.call(poi,"getLatLonPoint"));TurboStyle.row(host,results,"⌖",title,snippet,()->choose(p,title));}catch(Exception ignored){}});
        }catch(Exception e){main.post(()->{if(!closed&&request==searchGeneration){searching=false;error(e);}});}});
    }
    private void choose(NavCore.Point p,String name){stopGuidance();destination=p;destinationName=name;invalidateRoute();results.removeAllViews();TurboStyle.row(host,results,"⌖",name,"已选为终点 · 点击重新定位地图",()->center(p));center(p);state.setText("终点已选择，请定位后规划路线");}
    private void center(NavCore.Point p){if(map==null)return;try{Object ll=latLng(p),camera=NavReflect.call(NavReflect.type("com.amap.api.maps.CameraUpdateFactory"),"newLatLngZoom",ll,15f);NavReflect.call(map,"moveCamera",camera);Object marker=NavReflect.make("com.amap.api.maps.model.MarkerOptions");NavReflect.call(marker,"position",ll);NavReflect.call(map,"addMarker",marker);}catch(Exception ignored){}}
    private Object latLng(NavCore.Point p)throws Exception{return NavReflect.make("com.amap.api.maps.model.LatLng",p.lat,p.lon);}
    private static NavCore.Point point(Object p)throws Exception{double lat,lon;try{lat=((Number)NavReflect.call(p,"getLatitude")).doubleValue();lon=((Number)NavReflect.call(p,"getLongitude")).doubleValue();}catch(NoSuchMethodException e){lat=((Number)NavReflect.field(p,"latitude")).doubleValue();lon=((Number)NavReflect.field(p,"longitude")).doubleValue();}return new NavCore.Point(lat,lon);}
    private void locate(){
        if(host.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)!=PackageManager.PERMISSION_GRANTED){host.requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION},7302);state.setText("允许定位后，再点一次定位");return;}
        try{privacy();if(locationClient==null){locationClient=NavReflect.make("com.amap.api.location.AMapLocationClient",host.getApplicationContext());locationListener=NavReflect.proxy("com.amap.api.location.AMapLocationListener",(name,args)->{if(args.length>0&&args[0]!=null)main.post(()->fix(args[0]));});NavReflect.call(locationClient,"setLocationListener",locationListener);Object option=NavReflect.make("com.amap.api.location.AMapLocationClientOption");NavReflect.call(option,"setInterval",2000L);NavReflect.call(option,"setNeedAddress",false);NavReflect.call(locationClient,"setLocationOption",option);}NavReflect.call(locationClient,"startLocation");state.setText("定位中…室内可能需要较长时间");}catch(Exception e){error(e);}
    }
    private void fix(Object loc){if(closed)return;try{int code=((Number)NavReflect.call(loc,"getErrorCode")).intValue();if(code!=0){fixAt=0;state.setText("定位失败，错误码 "+code+"；请检查位置权限和高德配置");return;}origin=point(loc);accuracy=((Number)NavReflect.call(loc,"getAccuracy")).floatValue();fixAt=SystemClock.elapsedRealtime();if(!running&&!planning&&!searching)state.setText("已定位 · 精度约 "+Math.round(accuracy)+" 米");}catch(Exception e){fixAt=0;}}
    private boolean fresh(){return origin!=null&&fixAt>0&&SystemClock.elapsedRealtime()-fixAt<15000&&Float.isFinite(accuracy)&&accuracy>=0&&accuracy<=50;}
    private boolean planningFix(){return origin!=null&&fixAt>0&&SystemClock.elapsedRealtime()-fixAt<30000&&Float.isFinite(accuracy)&&accuracy>=0&&accuracy<=1000;}
    private void invalidateRoute(){generation++;planning=false;steps.clear();nativePaths.clear();routePoints.clear();routeBox.removeAllViews();plannedOrigin=null;hud.setText("等待重新规划路线");}
    private void plan(){
        if(destination==null){state.setText("请先选择搜索结果或长按地图选终点");return;}if(!planningFix()){state.setText("需要近期定位，请先定位");locate();return;}if(planning)return;
        stopGuidance();invalidateRoute();planning=true;int request=generation;String selectedMode=mode;NavCore.Point start=origin,end=destination;state.setText("正在规划路线…");
        network.execute(()->{try{
            Object from=NavReflect.make("com.amap.api.services.core.LatLonPoint",start.lat,start.lon),to=NavReflect.make("com.amap.api.services.core.LatLonPoint",end.lat,end.lon),pair=NavReflect.make("com.amap.api.services.route.RouteSearch$FromAndTo",from,to);
            Object query=selectedMode.equals("Drive")?NavReflect.make("com.amap.api.services.route.RouteSearch$DriveRouteQuery",pair,0,null,null,null):NavReflect.make("com.amap.api.services.route.RouteSearch$"+selectedMode+"RouteQuery",pair,0);
            Object api=NavReflect.make("com.amap.api.services.route.RouteSearch",host),response=NavReflect.call(api,"calculate"+selectedMode+"Route",query);List<?> paths=(List<?>)NavReflect.call(response,"getPaths");
            main.post(()->{if(closed||request!=generation)return;planning=false;plannedOrigin=start;plannedMode=selectedMode;nativePaths.addAll(paths);state.setText(paths.isEmpty()?"没有可用路线":"路线已规划 · 请选择方案");for(int i=0;i<paths.size();i++){final int index=i;try{Object path=paths.get(i);String summary=NavCore.meters(((Number)NavReflect.call(path,"getDistance")).doubleValue())+" · "+Math.max(1,(((Number)NavReflect.call(path,"getDuration")).longValue()+59)/60)+" 分钟";TurboStyle.row(host,routeBox,"↗","方案 "+(i+1),summary,()->selectPath(index));}catch(Exception ignored){}}if(!paths.isEmpty())selectPath(0);});
        }catch(Exception e){main.post(()->{if(!closed&&request==generation){planning=false;error(e);}});}});
    }
    private void selectPath(int index){stopGuidance();try{Object path=nativePaths.get(index);steps.clear();routePoints.clear();distance=((Number)NavReflect.call(path,"getDistance")).doubleValue();duration=((Number)NavReflect.call(path,"getDuration")).longValue();
        for(Object raw:(List<?>)NavReflect.call(path,"getSteps")){String text=String.valueOf(NavReflect.call(raw,"getInstruction"));List<NavCore.Point> points=new ArrayList<>();for(Object p:(List<?>)NavReflect.call(raw,"getPolyline"))points.add(point(p));if(points.size()>=2){steps.add(new NavCore.Step(text,points));routePoints.addAll(points);}}
        if(steps.isEmpty())throw new IllegalStateException("empty geometry");stepIndex=0;hud.setText("路线预览 · "+destinationName+"\n"+steps.get(0).instruction+"\n全程 "+NavCore.meters(distance)+" · 约 "+Math.max(1,(duration+59)/60)+" 分钟");state.setText("已选方案 "+(index+1)+" · 起点精度约 "+Math.round(accuracy)+" 米 · 眼镜显示未开启");drawRoute();
    }catch(Exception e){steps.clear();error(e);}}
    private void drawRoute(){if(map==null||routePoints.size()<2)return;try{NavReflect.call(map,"clear");Object poly=NavReflect.make("com.amap.api.maps.model.PolylineOptions");List<Object> coords=new ArrayList<>();Object bounds=NavReflect.make("com.amap.api.maps.model.LatLngBounds$Builder");for(NavCore.Point p:routePoints){Object ll=latLng(p);coords.add(ll);NavReflect.call(bounds,"include",ll);}NavReflect.call(poly,"addAll",coords);NavReflect.call(poly,"color",TurboStyle.INK);NavReflect.call(poly,"width",12f);NavReflect.call(map,"addPolyline",poly);Object update=NavReflect.call(NavReflect.type("com.amap.api.maps.CameraUpdateFactory"),"newLatLngBounds",NavReflect.call(bounds,"build"),60);NavReflect.call(map,"moveCamera",update);}catch(Exception ignored){}}
    private void guidanceMessage(String message){state.setText(message);guidanceState.setText(message);Toast.makeText(host,message,Toast.LENGTH_LONG).show();}
    private boolean routeReady(){
        if(!NavSessionPolicy.canOpen(!steps.isEmpty(),plannedMode.equals(mode))){guidanceMessage("请先规划并选择路线");return false;}
        return true;
    }
    private String routeOverview(String reason){return "路线概览 · "+destinationName+"\n全程 "+NavCore.meters(distance)+" · 约 "+Math.max(1,(duration+59)/60)+" 分钟\n"+reason;}
    private void begin(){begin(false);}
    private void begin(boolean simulated){
        if(!routeReady())return;
        NavSessionPolicy.Action action=NavSessionPolicy.action(displayPhase());
        if(action==NavSessionPolicy.Action.CONFIRM_EXIT){
            guidanceMessage("上一次显示退出待确认；确认后会继续本次导航");
            new AlertDialog.Builder(host).setTitle("确认上一轮眼镜显示已结束")
                .setMessage("手机还保留着上一轮测试的退出状态。请实际确认眼镜已回首页；如果仍在显示，先用眼镜按钮退出。确认后会继续开启当前路线，不需要回页面底部操作。")
                .setNegativeButton("还没退出",null).setPositiveButton("已回首页，继续导航",(d,w)->{confirmDisplayIdle();begin(simulated);}).show();return;
        }
        if(action==NavSessionPolicy.Action.WAIT){guidanceMessage("正在等待眼镜初始化回执，请稍后再点开始；没有重复发送初始化");return;}
        final int selectedGeneration=generation;
        new AlertDialog.Builder(host).setTitle(simulated?"开始模拟导航 · 非真实位置":action==NavSessionPolicy.Action.REUSE?"切换为真实路线指引":"开始眼镜导航")
            .setMessage((simulated?"沿已规划路线自动前进，不修改系统定位。手机和镜片均显示“模拟”，支持暂停及1/2/4/8倍速。":"定位不足时先显示路线概览与等待提示，定位达标后才开始转向指引。")+"确认眼镜没有其他任务；保持本页面前台。TNV1会自动进入原生导航，时间/距离为路线估算；旧字幕通道最多4分钟。")
            .setNegativeButton("取消",null).setPositiveButton("开始",(d,w)->{
                if(!routeReady()||selectedGeneration!=generation)return;
                NavSessionPolicy.Action next=NavSessionPolicy.action(displayPhase());
                if(next!=NavSessionPolicy.Action.START&&next!=NavSessionPolicy.Action.REUSE){begin(simulated);return;}
                NavSimulation candidate=null;
                if(simulated)try{candidate=new NavSimulation(steps,mode,SystemClock.elapsedRealtime());candidate.speed(simulationSpeed,SystemClock.elapsedRealtime());}catch(IllegalArgumentException e){guidanceMessage("路线缺少可回放的路径，请重新规划");return;}
                runEpoch++;stepIndex=0;positionValidated=false;clearSimulation();
                running=startDisplay(simulated?"模拟导航 · 非真实位置\n"+steps.get(0).instruction+"\n等待眼镜显示就绪":routeOverview("等待定位后开始转向指引"),true);
                if(running&&simulated){simulation=candidate;pauseSimulation.setEnabled(true);pauseSimulation.setText("暂停模拟");}
                guidanceMessage(running?"路线已接入显示会话，等待眼镜文字更新":"没有开始：显示通道未就绪，请检查下方状态");
            }).show();
    }
    private void clearSimulation(){simulation=null;if(pauseSimulation!=null){pauseSimulation.setEnabled(false);pauseSimulation.setText("暂停模拟");}if(simulationMarker!=null)try{NavReflect.call(simulationMarker,"remove");}catch(Exception ignored){}simulationMarker=null;}
    private void stopGuidance(){BackgroundWork.release("导航");runEpoch++;running=false;clearSimulation();if(guidanceState!=null)guidanceState.setText("导航已停止；可以选择新路线");if(simulationStatus!=null)simulationStatus.setText("模拟未运行 · 可从起点重新开始");stopDisplay();}
    private void finishDisplayLater(){final int owner=runEpoch;main.postDelayed(()->{if(owner==runEpoch&&!running)stopDisplay();},8000);}
    private void renderSimulation(){
        NavSimulation.Frame frame=simulation.frame();stepIndex=frame.step;
        String label=simulation.paused()?"模拟 · 已暂停":"模拟 · "+simulation.speed()+"×";
        String text=frame.finished?"模拟导航已结束\n"+destinationName+"\n仅路线回放 · 非真实到达":label+" · 非真实位置\n"+steps.get(frame.step).instruction+"\n本段剩余 "+NavCore.meters(frame.remainingStep)+" · "+(frame.step+1)+"/"+steps.size()+"段";
        hud.setText(text);offerDisplay(text);
        simulationStatus.setText(label+" · 进度 "+Math.round(frame.progress*100)+"% · 第 "+(frame.step+1)+" / "+steps.size()+" 段");
        guidanceState.setText(frame.finished?"模拟到达；约8秒后请求关闭显示":simulation.paused()?"已暂停推进；等待眼镜确认":"沿规划路线回放；TNV1合并最新帧，确认后至少间隔1秒，非真实定位");
        if(map!=null)try{
            if(simulationMarker==null){Object options=NavReflect.make("com.amap.api.maps.model.MarkerOptions");NavReflect.call(options,"position",latLng(frame.point));NavReflect.call(options,"title","模拟位置 · 非真实定位");simulationMarker=NavReflect.call(map,"addMarker",options);}
            else NavReflect.call(simulationMarker,"setPosition",latLng(frame.point));
        }catch(Exception ignored){}
        if(frame.finished&&running){running=false;pauseSimulation.setEnabled(false);finishDisplayLater();}
    }
    private final Runnable tick=new Runnable(){public void run(){if(closed)return;
        if(running){
            String phase=displayPhase();
            if(!phase.equals("ready")&&!phase.equals("starting")){running=false;clearSimulation();guidanceState.setText("眼镜显示已结束或连接中断；请确认镜片状态后重新开始");simulationStatus.setText("模拟已停止 · 不会继续在后台推进");}
            else if(simulation!=null){simulation.advance(SystemClock.elapsedRealtime(),phase.equals("ready"));if(phase.equals("ready"))renderSimulation();else simulationStatus.setText("等待眼镜初始化，模拟暂不推进");}
            else {
            NavSessionPolicy.Position position=NavSessionPolicy.position(fresh(),positionValidated,plannedOrigin==null||origin==null?Double.POSITIVE_INFINITY:NavCore.distance(plannedOrigin,origin));
            if(position==NavSessionPolicy.Position.WAIT_FIX){hud.setText(routeOverview("等待准确定位 · 暂无转向指引"));offerDisplay(hud.getText().toString());guidanceState.setText("先显示路线概览；当前定位精度约 "+Math.round(accuracy)+" 米，需要15秒内、50米内的位置才更新转向。发送状态见上方。");}
            else if(position==NavSessionPolicy.Position.REPLAN){hud.setText(routeOverview("起点位置已变化 · 请重新规划"));offerDisplay(hud.getText().toString());guidanceState.setText("当前路线仅作概览；请重新规划后开始实时指引");}
            else{NavCore.Match match=NavCore.match(steps,origin,stepIndex);
                positionValidated=true;guidanceState.setText("实时定位已达标，正在更新路线指引");
                if(match.step<0||match.offRoute>60){hud.setText("已偏离规划路线\n请停止并重新规划");offerDisplay(hud.getText().toString());}
                else {stepIndex=match.step;boolean arrived=stepIndex==steps.size()-1&&NavCore.distance(origin,destination)<20;
                    String text=arrived?"已接近目的地\n"+destinationName:steps.get(stepIndex).instruction+"\n本段剩余 "+NavCore.meters(match.remainingStep)+"\n第 "+(stepIndex+1)+" / "+steps.size()+" 段";
                    hud.setText(text);offerDisplay(text);if(arrived){running=false;finishDisplayLater();}
                }
            }
            }
        }
        main.postDelayed(this,1000);
    }};
    private String displayPhase(){return nativeDisplay?NativeNavigation.phase():NavGlasses.phase();}
    private String displayStatus(){return nativeDisplay?NativeNavigation.status():NavGlasses.status();}
    private void stopDisplay(){BackgroundWork.release("导航");if(nativeDisplay)NativeNavigation.stop();else NavGlasses.stop();}
    private void confirmDisplayIdle(){if(nativeDisplay)NativeNavigation.confirmIdle();else NavGlasses.confirmIdle();}
    private boolean startDisplay(String text){return startDisplay(text,false);}
    private boolean startDisplay(String text,boolean navigation){if(!nativeDisplay)return NavGlasses.start(text,navigation);try{boolean ok=NativeNavigation.start(scene(text,navigation));if(ok){BackgroundWork.register("导航",this::stopGuidance);BackgroundWork.acquire("导航",navigation?24:16);}return ok;}catch(RuntimeException e){guidanceMessage("原生导航数据超出预算，未发送");return false;}}
    private void offerDisplay(String text){if(!nativeDisplay){NavGlasses.offer(text);return;}try{NativeNavigation.offer(scene(text,true));}catch(RuntimeException e){guidanceState.setText("原生导航数据暂不可用，未发送旧位置");}}
    private NativeNavCodec.Scene scene(String text,boolean navigation){
        if(!navigation||steps.isEmpty()){NativeNavCodec.Scene demo=new NativeNavCodec.Scene();demo.road="模拟 · 校验7392";demo.turn="前方右转";demo.icon=3;demo.distance=80;demo.remaining=2048;demo.seconds=420;demo.x=512;demo.y=800;demo.points=new int[][]{{512,800},{512,256},{900,256}};demo.mode=alwaysOn?1:0;return demo;}
        if(text.contains("等待")||text.contains("偏离")||text.contains("重新规划")||text.contains("路线概览")){NativeNavCodec.Scene waiting=new NativeNavCodec.Scene();waiting.mode=alwaysOn?1:0;waiting.road=NativeNavCodec.clip(destinationName,96);waiting.turn=NativeNavCodec.clip(text.contains("模拟")?"模拟 · 等待通道就绪":text.contains("偏离")?"已偏离路线，请重新规划":text.contains("重新规划")?"请重新规划路线":"等待准确定位",48);return waiting;}
        boolean sim=simulation!=null;NavCore.Point point=sim?simulation.frame().point:origin;if(point==null)point=plannedOrigin;double remaining=sim?simulation.frame().remainingStep:NavCore.match(steps,point,stepIndex).remainingStep;
        boolean arrived=text.contains("已接近目的地")||text.contains("模拟导航已结束");
        return NativeNavRoute.scene(steps,Math.min(stepIndex,steps.size()-1),point,remaining,duration,sim,alwaysOn,arrived);
    }
    private void error(Exception e){Throwable t=e;while(t instanceof InvocationTargetException&&((InvocationTargetException)t).getTargetException()!=null)t=((InvocationTargetException)t).getTargetException();String code="";try{code="（高德错误码 "+NavReflect.call(t,"getErrorCode")+"）";}catch(Exception ignored){}state.setText("操作未完成"+code+"，请检查网络、定位权限和 Android 高德配置");}
    private void close(){BackgroundWork.release("导航");if(closed)return;closed=true;generation++;searchGeneration++;runEpoch++;running=false;clearSimulation();main.removeCallbacksAndMessages(null);stopDisplay();NavGlasses.listen(null);NativeNavigation.listen(null);network.shutdownNow();if(lifecycle!=null)host.getApplication().unregisterActivityLifecycleCallbacks(lifecycle);
        if(locationClient!=null)try{NavReflect.call(locationClient,"stopLocation");NavReflect.call(locationClient,"onDestroy");}catch(Exception ignored){}
        if(mapView!=null)try{NavReflect.call(mapView,"onPause");NavReflect.call(mapView,"onDestroy");}catch(Exception ignored){}current=null;
    }
}
