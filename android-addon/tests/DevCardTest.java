package com.turboio.addon;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** TDC1 developer card: the Java validator agrees with the C dc_parse on every case, and the
 * install is the exact shape TVP2 dashboard-compat-v1 package() accepts. */
public final class DevCardTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("devcard "+n+" "+why);}
    public static void main(String[] a)throws Exception{
        int accepted=0;
        for(String line:Files.readAllLines(Paths.get(a[0],"cases.txt"),StandardCharsets.UTF_8)){String[] p=line.split("\t",2);boolean c=p[0].equals("1");
            boolean java;try{CardCodec.devcard(p[1]);java=true;}catch(IllegalArgumentException e){java=false;}ok(java==c,"agree on "+p[1]);if(c)accepted++;}
        ok(accepted==5,"five valid cases (leading zeros allowed, as in C)");
        Map<String,Object> install=CardCodec.devcard("TDC1;99;90;85;375;1280;1400;2000;0;1;2");ok("widget_install".equals(install.get("cmd")),"cmd");
        Map<String,Object> data=BoundedJson.map(BoundedJson.map(install.get("payload")).get("data"));
        ok("turbo_ui_devcard_v1".equals(data.get("id"))&&"a2ui".equals(data.get("type"))&&"Turbo 开发者仪表盘".equals(data.get("name")),"identity");
        Map<String,Object> extras=BoundedJson.map(BoundedJson.read(((String)data.get("extras")).getBytes(StandardCharsets.UTF_8)));
        Map<String,Object> ui=BoundedJson.map(extras.get("uiContent")),create=BoundedJson.map(ui.get("createSurface")),update=BoundedJson.map(ui.get("updateComponents"));
        ok("turbo_ui_devcard_v1".equals(extras.get("widgetId"))&&"Turbo 开发者仪表盘".equals(extras.get("name")),"extras identity");
        ok("turbo_ui_devcard_v1".equals(create.get("surfaceId"))&&"https://rayneo.com/a2ui/catalogs/glasses-base/v1/catalog.json".equals(create.get("catalogId"))&&"turbo_ui_devcard_v1".equals(update.get("surfaceId")),"surface");
        List<Object> components=BoundedJson.list(update.get("components"));Map<String,Object> root=BoundedJson.map(components.get(0));
        ok(components.size()==1&&"root".equals(root.get("id"))&&"Text".equals(root.get("component"))&&"TDC1;99;90;85;375;1280;1400;2000;0;1;2".equals(root.get("text")),"single root text");
        ok(BoundedJson.canonical(install).length<7500,"fits one message");
        System.out.println("DevCardTest: "+n+" checks; agrees with C dc_parse, TVP2 compat install shape");
    }
}
