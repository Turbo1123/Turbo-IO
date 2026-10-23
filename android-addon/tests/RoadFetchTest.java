package com.turboio.addon;
import java.nio.charset.StandardCharsets;import java.util.*;

/** Overpass road fetch (iOS RoadMap.m request/parse): exact query, bounded parse, per-session consent budget. */
public final class RoadFetchTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("road fetch "+n+" "+why);}
    static byte[] b(String s){return s.getBytes(StandardCharsets.UTF_8);}
    static String way(int id,String tags,String geom){return "{\"type\":\"way\",\"id\":"+id+(tags==null?"":",\"tags\":"+tags)+",\"geometry\":"+geom+"}";}
    public static void main(String[] a){
        double[] here={22.54,114.05};
        ok(RoadFetch.query(here).equals("[out:json][timeout:15][maxsize:16777216];way[highway](22.534000,114.043504,22.546000,114.056496);out tags geom;"),"query "+RoadFetch.query(here));
        ok(RoadFetch.url(here).equals("https://overpass-api.de/api/interpreter?data=%5Bout:json%5D%5Btimeout:15%5D%5Bmaxsize:16777216%5D;way%5Bhighway%5D(22.534000,114.043504,22.546000,114.056496);out%20tags%20geom;"),"url");
        double[] box=RoadFetch.bbox(here);ok(Math.abs(box[0]-22.534)<1e-9&&Math.abs(box[3]-114.0564962)<1e-6,"bbox");
        String g2="[{\"lat\":22.54,\"lon\":114.05},{\"lat\":22.541,\"lon\":114.051}]";
        String reply="{\"version\":0.6,\"elements\":["+way(1,"{\"highway\":\"primary\",\"name\":\"深南大道\"}",g2)+","+way(2,null,g2)+","+way(3,"{\"highway\":\"service\",\"bridge\":\"yes\"}","[{\"lat\":22.54,\"lon\":114.05},{\"lat\":22.542,\"lon\":114.052},{\"lat\":22.543,\"lon\":114.053}]")
            +",{\"type\":\"node\",\"id\":9,\"lat\":1,\"lon\":2},"+way(4,"{\"highway\":\"x\"}","[{\"lat\":22.54,\"lon\":114.05},{\"lat\":99,\"lon\":114.05},{\"lat\":22.55,\"lon\":114.06},{\"lat\":22.56,\"lon\":114.07}]")+"]}";
        List<Object> f=RoadFetch.parse(b(reply));ok(f!=null&&f.size()==3,"3 ways kept; node and invalid-coordinate way dropped");
        Map<String,Object> f0=BoundedJson.map(f.get(0)),p0=BoundedJson.map(f0.get("properties")),g0=BoundedJson.map(f0.get("geometry"));
        ok("road".equals(p0.get("kind"))&&"深南大道".equals(p0.get("name"))&&"primary".equals(p0.get("highway"))&&"LineString".equals(g0.get("type")),"tags and kind");
        List<Object> c0=BoundedJson.list(BoundedJson.list(g0.get("coordinates")).get(0));ok(((Number)c0.get(0)).doubleValue()==114.05&&((Number)c0.get(1)).doubleValue()==22.54,"lon/lat order");
        ok("road".equals(BoundedJson.map(BoundedJson.map(f.get(1)).get("properties")).get("kind")),"untagged way still a road");
        ok(RoadFetch.parse(b("{\"remark\":\"runtime error\",\"elements\":["+way(1,null,g2)+"]}"))==null,"remark refused");
        StringBuilder many=new StringBuilder("{\"elements\":[");for(int i=0;i<5001;i++){if(i>0)many.append(',');many.append("{\"type\":\"node\"}");}many.append("]}");
        ok(RoadFetch.parse(b(many.toString()))==null,"5001 elements refused");
        StringBuilder pts=new StringBuilder("[");for(int i=0;i<40001;i++){if(i>0)pts.append(',');pts.append("{\"lat\":22.5,\"lon\":114}");}pts.append(']');
        ok(RoadFetch.parse(b("{\"elements\":["+way(1,null,pts.toString())+"]}"))==null,">40000 points refused");
        ok(RoadFetch.parse(b("not json"))==null&&RoadFetch.parse(null)==null&&RoadFetch.parse(b("{\"elements\":[]}"))==null,"malformed or empty refused");
        // Budget: explicit consent, 6 per session, ≥60 s apart, revoke refuses everything and resets.
        RoadFetch.Budget bu=new RoadFetch.Budget();ok(!bu.allow(10),"no consent, no request");bu.consent();
        for(int i=0;i<6;i++){ok(bu.allow(100+60*i),"request "+(i+1));ok(!bu.allow(100+60*i+59),"too early after "+(i+1));}
        ok(!bu.allow(10000)&&bu.used()==6,"7th refused");bu.revoke();ok(!bu.allow(20000)&&!bu.consented()&&bu.used()==0,"revoked");
        // Glue: consent gates the network, the reply installs a region, stop drops a late reply.
        List<String> calls=new ArrayList<>();List<Runnable> pending=new ArrayList<>();
        RoadScene scene=new RoadScene((lat,lon)->new double[]{lat,lon},name->null);scene.setEnabled(true);
        RoadFetch fetch=new RoadFetch(scene,url->{calls.add(url);return b(reply);},pending::add);
        fetch.maybeRequest(here,100);ok(calls.isEmpty()&&pending.isEmpty(),"no consent: no request");
        fetch.consent();fetch.maybeRequest(here,100);ok(pending.size()==1&&scene.note().contains("试验图源请求中"),"queued with note");
        fetch.maybeRequest(here,200);ok(pending.size()==1,"one in flight at a time");
        pending.remove(0).run();ok(calls.size()==1&&calls.get(0).equals(RoadFetch.url(here))&&scene.note().contains("联网路网就绪")&&!scene.needsRequest(here),"installed region");
        RoadFetch.Http failing=url->{throw new java.io.IOException("offline");};RoadFetch bad=new RoadFetch(scene,failing,Runnable::run);bad.consent();bad.maybeRequest(new double[]{30,120},100);ok(scene.note().contains("图源不可用"),"failure note");
        RoadFetch late=new RoadFetch(scene,url->b(reply),pending::add);late.consent();late.maybeRequest(new double[]{31,121},100);late.stop();pending.remove(0).run();
        ok(scene.needsRequest(new double[]{31,121})&&!late.consented(),"late reply after stop dropped");
        System.out.println("RoadFetchTest: "+n+" checks; query, parse bounds, consent budget, glue");
    }
}
