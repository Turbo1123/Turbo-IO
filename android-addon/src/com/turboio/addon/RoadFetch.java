package com.turboio.addon;
import java.util.*;
import java.util.concurrent.Executor;

/** Nearby OSM roads from Overpass (iOS RoadMap.m request path): only with explicit per-session consent, ≤6 requests
 * ≥60 s apart, one in flight, bbox-only query, no redirects, HTTP 200, ≤2 MiB, ≤5000 elements, ≤40000 points, and a
 * reply carrying "remark" is refused. Coordinates are never persisted. Results land in RoadScene as a region. */
final class RoadFetch {
    interface Http{byte[] get(String url)throws Exception;}
    static final String USER_AGENT="TurboIO-TNR1-private-pilot/1.0";
    static final int MAX_BYTES=2*1024*1024,MAX_NODES=400000;

    /** Per-session consent and request budget (iOS: allowNetwork, _requests ≤ 6, _lastRequest ≥ 60 s). */
    static final class Budget{
        private boolean consented;private int used;private double last;
        synchronized void consent(){consented=true;}
        synchronized void revoke(){consented=false;used=0;last=0;}
        synchronized boolean consented(){return consented;}
        synchronized int used(){return used;}
        synchronized boolean allow(double now){if(!consented||used>=RoadScene.REQUEST_LIMIT||(last!=0&&now-last<60))return false;last=now;used++;return true;}
    }

    static double[] bbox(double[] wgs){double lat=wgs[0],lon=wgs[1],dlat=.006,dlon=.006/Math.max(.2,Math.cos(lat*Math.PI/180));return new double[]{lat-dlat,lon-dlon,lat+dlat,lon+dlon};}
    static String query(double[] wgs){double[] b=bbox(wgs);return String.format(Locale.ROOT,"[out:json][timeout:15][maxsize:16777216];way[highway](%.6f,%.6f,%.6f,%.6f);out tags geom;",b[0],b[1],b[2],b[3]);}
    /** Percent-encoding as NSCharacterSet.URLQueryAllowedCharacterSet. */
    static String url(double[] wgs){
        StringBuilder out=new StringBuilder("https://overpass-api.de/api/interpreter?data=");
        for(byte c:query(wgs).getBytes(java.nio.charset.StandardCharsets.UTF_8)){int u=c&255;
            if((u>='a'&&u<='z')||(u>='A'&&u<='Z')||(u>='0'&&u<='9')||"!$&'()*+,-./:;=?@_~".indexOf(u)>=0)out.append((char)u);else out.append(String.format(Locale.ROOT,"%%%02X",u));}
        return out.toString();
    }
    private static boolean num(Object v,double lo,double hi){if(!(v instanceof Number))return false;double d=((Number)v).doubleValue();return Double.isFinite(d)&&d>=lo&&d<=hi;}
    /** Overpass JSON → GeoJSON-like road features ([lon,lat] coordinates, tags + kind=road); null when refused or empty. */
    static List<Object> parse(byte[] body){
        Map<String,Object> j;try{j=BoundedJson.map(BoundedJson.readLarge(body,MAX_BYTES,MAX_NODES));}catch(RuntimeException e){return null;}
        if(!(j.get("elements") instanceof List)||j.containsKey("remark"))return null;List<?> elements=(List<?>)j.get("elements");if(elements.size()>5000)return null;
        List<Object> features=new ArrayList<>();int points=0;
        for(Object e:elements){if(!(e instanceof Map))continue;Map<?,?> way=(Map<?,?>)e;if(!"way".equals(way.get("type"))||!(way.get("geometry") instanceof List))continue;
            List<Object> coords=new ArrayList<>();
            for(Object point:(List<?>)way.get("geometry")){
                if(!(point instanceof Map)||!num(((Map<?,?>)point).get("lat"),-85,85)||!num(((Map<?,?>)point).get("lon"),-180,180)){coords.clear();break;}
                coords.add(Arrays.asList(((Map<?,?>)point).get("lon"),((Map<?,?>)point).get("lat")));if(++points>40000)return null;}
            if(coords.size()>=2){Map<String,Object> p=new TreeMap<>();if(way.get("tags") instanceof Map)for(Map.Entry<?,?> t:((Map<?,?>)way.get("tags")).entrySet())p.put(String.valueOf(t.getKey()),t.getValue());p.put("kind","road");
                Map<String,Object> g=new TreeMap<>();g.put("coordinates",coords);g.put("type","LineString");Map<String,Object> f=new TreeMap<>();f.put("properties",p);f.put("geometry",g);features.add(f);}
        }
        return features.isEmpty()?null:features;
    }

    private final RoadScene scene;private final Http http;private final Executor executor;private final Budget budget=new Budget();
    private boolean inFlight;private long epoch;
    RoadFetch(RoadScene scene,Http http,Executor executor){this.scene=scene;this.http=http;this.executor=executor;}
    void consent(){budget.consent();sync();}
    boolean consented(){return budget.consented();}
    /** Stop / revoke: consent and budget reset, in-flight reply discarded, cached regions cleared (iOS reset). */
    synchronized void stop(){epoch++;inFlight=false;budget.revoke();scene.reset();}
    private synchronized void sync(){scene.fetchState(budget.consented(),inFlight,budget.used());}
    /** Prefetch when the WGS position is within 300 m of every known region's edge (now: monotonic seconds). */
    void maybeRequest(double[] wgs,double now){
        final long mine;final double[] box;final String target;
        synchronized(this){if(inFlight||!RoadScene.ll(wgs)||!scene.needsRequest(wgs)||!budget.allow(now))return;inFlight=true;mine=epoch;box=bbox(wgs);target=url(wgs);}
        sync();scene.setNote("试验图源请求中（最多6次/会话，间隔60秒）");
        executor.execute(()->{byte[] body;try{body=http.get(target);}catch(Exception e){body=null;}List<Object> features=body==null?null:parse(body);finish(mine,body!=null,features,box);});
    }
    private void finish(long mine,boolean reached,List<Object> features,double[] box){
        synchronized(this){if(mine!=epoch)return;inFlight=false;}
        sync();
        if(!reached)scene.setNote("图源不可用 · 不伪造道路，保留路线示意图");
        else if(features!=null){scene.installFeatures(features,box);scene.setNote("联网路网就绪 · © OpenStreetMap · 非高德底图");}
        else scene.setNote("图源格式或容量不合格 · 已拒绝");
    }
    /** Android transport: bounded HTTPS GET, no redirects, HTTP 200 only, ≤2 MiB. */
    static Http https(){return url->BoundedHTTP.request(url,Collections.singletonMap("User-Agent",USER_AGENT),null,MAX_BYTES);}
}
