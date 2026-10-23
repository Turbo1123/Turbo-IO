package com.turboio.addon;
import java.nio.charset.StandardCharsets;
import java.text.BreakIterator;
import java.util.*;

/** TNR3 road scene builder (port of iOS 1.0.7 RoadMap.m): OSM road features around the AMap position become a
 * heading-up SCENE / SCENE2 (≤4 road-name labels) plus POSE in quarter-metre units around a GCJ-02 origin. Only the
 * fixture/Overpass coverage uses WGS-84; OSM lon/lat converts to the map datum exactly once. Network fetching lives
 * outside (RoadFetch); this class only reports whether a request is wanted. Thread-safe. */
final class RoadScene {
    interface Converter{double[] toMap(double lat,double lon);}
    interface Fixtures{byte[] read(String name);}
    static final class Result{
        final byte[] scene,scene2,pose;final double poseAt;final String note;
        Result(byte[] scene,byte[] scene2,byte[] pose,double poseAt,String note){this.scene=scene;this.scene2=scene2;this.pose=pose;this.poseAt=poseAt;this.note=note;}
    }
    static final int FIXTURE_BYTES=2*1024*1024,FIXTURE_NODES=400000,REQUEST_LIMIT=6;
    private static final class Item{List<int[]> points;int style,flags,layer;String name;double rank;}
    private static final class Region{final double[] bbox;final List<?> features;Region(double[] b,List<?> f){bbox=b;features=f;}}

    private final Converter convert;private final Fixtures fixtures;
    private boolean enabled,allowNetwork,inFlight;private int requests;
    private List<Object> features=new ArrayList<>();private final List<Region> regions=new ArrayList<>();
    private double[] origin;private double labelHeading,sceneAt;private byte[] scene,scene2;private long generation;private Object segment;
    private String note="路网关闭 · 保留原路线示意图";
    RoadScene(Converter convert,Fixtures fixtures){this.convert=convert;this.fixtures=fixtures;}
    synchronized void setEnabled(boolean on){enabled=on;}
    synchronized boolean enabled(){return enabled;}
    synchronized String note(){return note==null?"":note;}
    /** Network consent and request bookkeeping owned by RoadFetch; only used for the status note. */
    synchronized void fetchState(boolean allowNetwork,boolean inFlight,int requests){this.allowNetwork=allowNetwork;this.inFlight=inFlight;this.requests=requests;}
    synchronized void setNote(String s){note=s;}
    synchronized void reset(){regions.clear();features=new ArrayList<>();scene=scene2=null;origin=null;segment=null;allowNetwork=inFlight=false;requests=0;note="路网缓存已清理";}

    static boolean ll(double[] p){return p!=null&&p.length==2&&Double.isFinite(p[0])&&Double.isFinite(p[1])&&p[0]>=-85&&p[0]<=85&&p[1]>=-180&&p[1]<=180;}
    private static double num(Object o){return o instanceof Number?((Number)o).doubleValue():Double.NaN;}
    private static double[] xy(double[] ll,double[] origin){double y=(ll[0]-origin[0])*111319.49,x=(ll[1]-origin[1])*111319.49*Math.cos(origin[0]*Math.PI/180);return new double[]{x,y};}
    private static double distance(double[] a,double[] b){double[] p=xy(a,b);return Math.hypot(p[0],p[1]);}
    private static long lround(double x){return x<0?-Math.round(-x):Math.round(x);}
    private static void w16(byte[] p,int at,long x){p[at]=(byte)x;p[at+1]=(byte)(x>>8);}
    private static void w32(byte[] p,int at,long x){w16(p,at,x);w16(p,at+2,x>>16);}
    /** Liang–Barsky clip to the ±500 m square; s = {x,y,xx,yy} updated in place. */
    private static boolean clip(double[] s){
        double dx=s[2]-s[0],dy=s[3]-s[1],t0=0,t1=1;double[] p={-dx,dx,-dy,dy},q={s[0]+500,500-s[0],s[1]+500,500-s[1]};
        for(int i=0;i<4;i++){if(Math.abs(p[i])<1e-9){if(q[i]<0)return false;}else{double t=q[i]/p[i];if(p[i]<0)t0=Math.max(t0,t);else t1=Math.min(t1,t);if(t0>t1)return false;}}
        double ox=s[0],oy=s[1];s[0]=ox+dx*t0;s[1]=oy+dy*t0;s[2]=ox+dx*t1;s[3]=oy+dy*t1;return true;
    }
    /** Clipped, quarter-metre polyline pieces; null entries break the line (invalid coordinates). */
    private static List<List<int[]>> pieces(List<double[]> coords,double[] origin){
        List<List<int[]>> out=new ArrayList<>();List<int[]> part=null;double[] last=null;int budget=0;
        for(double[] ll:coords){if(!ll(ll)){last=null;part=null;continue;}double[] p=xy(ll,origin);
            if(last!=null){double[] s={last[0],last[1],p[0],p[1]};if(clip(s)){
                int[] a={(int)lround(s[0]*4),(int)lround(s[1]*4)},b={(int)lround(s[2]*4),(int)lround(s[3]*4)};
                if(part==null||!Arrays.equals(part.get(part.size()-1),a)){part=new ArrayList<>();part.add(a);out.add(part);}
                if(!Arrays.equals(part.get(part.size()-1),b))part.add(b);if(++budget>=2048)break;
            }else part=null;}
            last=p;}
        return out;
    }
    /** OSM [lon,lat] pairs → map-datum [lat,lon]; an invalid pair or conversion yields null (a break). */
    private List<double[]> osm(List<?> coords){
        List<double[]> out=new ArrayList<>();
        for(Object pair:coords){double[] ll=null;
            if(pair instanceof List&&((List<?>)pair).size()==2){ll=new double[]{num(((List<?>)pair).get(1)),num(((List<?>)pair).get(0))};if(!ll(ll))ll=null;else if(convert!=null)ll=convert.toMap(ll[0],ll[1]);}
            out.add(ll(ll)?ll:null);}
        return out;
    }
    static String text(Object v){if(v instanceof String)return (String)v;if(v instanceof java.math.BigDecimal)return ((java.math.BigDecimal)v).toPlainString();if(v instanceof Number)return v.toString();if(v instanceof Boolean)return (Boolean)v?"1":"0";return "";}
    /** NSString intValue: optional leading space and sign, then digits; 0 when none. */
    private static int intValue(String s){int i=0,n=s.length();while(i<n&&Character.isWhitespace(s.charAt(i)))i++;boolean neg=false;if(i<n&&(s.charAt(i)=='-'||s.charAt(i)=='+'))neg=s.charAt(i++)=='-';long v=0;while(i<n&&s.charAt(i)>='0'&&s.charAt(i)<='9'&&v<=Integer.MAX_VALUE)v=v*10+s.charAt(i++)-'0';v=neg?-v:v;return (int)Math.max(Integer.MIN_VALUE,Math.min(Integer.MAX_VALUE,v));}
    /** Douglas–Peucker with a 2 m (64 quarter-metre²) tolerance; endpoints always kept. */
    static List<int[]> simplify(List<int[]> p){
        if(p.size()<3||p.size()>2049)return p;BitSet keep=new BitSet();keep.set(0);keep.set(p.size()-1);
        ArrayDeque<int[]> todo=new ArrayDeque<>();todo.push(new int[]{0,p.size()-1});
        while(!todo.isEmpty()){int[] r=todo.pop();int a=r[0],b=r[1],at=0;double ax=p.get(a)[0],ay=p.get(a)[1],dx=p.get(b)[0]-ax,dy=p.get(b)[1]-ay,den=dx*dx+dy*dy,best=64;
            for(int i=a+1;i<b;i++){double x=p.get(i)[0]-ax,y=p.get(i)[1]-ay,t=den!=0?Math.max(0,Math.min(1,(x*dx+y*dy)/den)):0,ex=x-dx*t,ey=y-dy*t,d=ex*ex+ey*ey;if(d>best){best=d;at=i;}}
            if(at!=0){keep.set(at);todo.push(new int[]{a,at});todo.push(new int[]{at,b});}}
        List<int[]> out=new ArrayList<>();for(int i=keep.nextSetBit(0);i>=0;i=keep.nextSetBit(i+1))out.add(p.get(i));return out;
    }
    /** Label text: single-unit printable characters only, ≤104 px (9 ASCII / 16 other) and <32 UTF-8 bytes. */
    static byte[] nameData(Object value){
        String name=text(value);StringBuilder s=new StringBuilder();int width=0,bytes=0;BreakIterator it=BreakIterator.getCharacterInstance(Locale.ROOT);it.setText(name);
        for(int a=it.first(),b=it.next();b!=BreakIterator.DONE;a=b,b=it.next()){
            if(b-a!=1)continue;char u=name.charAt(a);if(u<32||(u>=127&&u<=159)||(u>=0x200b&&u<=0x202e)||(u>=0x2060&&u<=0x206f)||u>=0xfff0||Character.isSurrogate(u))continue;
            int w=u<128?9:16,n=String.valueOf(u).getBytes(StandardCharsets.UTF_8).length;if(width+w>104||bytes+n>=NavMapCodec.LABEL_BYTES)break;width+=w;bytes+=n;s.append(u);}
        return s.toString().getBytes(StandardCharsets.UTF_8);
    }
    static int style(String h){
        if(Arrays.asList("motorway","trunk","motorway_link","trunk_link").contains(h))return 0;if(h.startsWith("primary"))return 1;if(h.startsWith("secondary"))return 2;if(h.startsWith("tertiary"))return 3;
        if(Arrays.asList("residential","unclassified","living_street").contains(h))return 4;return 5;
    }

    /** Iterative inverse of the WGS→map converter (≤6 steps, 0.5 m); null when it does not converge. */
    synchronized double[] wgs(double[] map){
        if(!ll(map))return null;if(convert==null)return map.clone();double lat=map[0],lon=map[1];
        for(int i=0;i<6;i++){double[] candidate={lat,lon};if(!ll(candidate))return null;double[] q=convert.toMap(lat,lon);if(!ll(q))return null;
            if(distance(q,map)<=.5)return candidate;lat-=q[0]-map[0];lon-=q[1]-map[1];}
        return null;
    }
    private static boolean contains(double[] b,double[] ll,double metres){
        if(b==null||b.length!=4||!ll(ll))return false;double lat=ll[0],lon=ll[1],dy=metres/111319.49,dx=dy/Math.max(.2,Math.cos(lat*Math.PI/180));
        return lat>=b[0]+dy&&lat<=b[2]-dy&&lon>=b[1]+dx&&lon<=b[3]-dx;
    }
    private boolean hasCoverage(double[] ll,double metres){for(Region r:regions)if(contains(r.bbox,ll,metres))return true;return false;}
    /** True when the WGS position is within 300 m of the edge of every known region (iOS prefetch rule). */
    synchronized boolean needsRequest(double[] wgs){return ll(wgs)&&!hasCoverage(wgs,300);}
    /** Keeps the two most recent regions; current region first, deduplicated, ≤10000 features. */
    synchronized void installFeatures(List<?> list,double[] bbox){
        if(list==null||list.isEmpty()||list.size()>5000||bbox==null||bbox.length!=4)return;
        for(Iterator<Region> i=regions.iterator();i.hasNext();)if(Arrays.equals(i.next().bbox,bbox))i.remove();
        regions.add(new Region(bbox.clone(),list));while(regions.size()>2)regions.remove(0);
        List<Object> all=new ArrayList<>();Set<Object> seen=new HashSet<>();
        for(int r=regions.size()-1;r>=0;r--)for(Object f:regions.get(r).features){if(all.size()>=10000)break;if(seen.add(f))all.add(f);}
        features=all;scene=scene2=null;
    }
    /** Bundled public-area fixtures (shenzhen, hongkong) whose bbox contains the WGS position. */
    private boolean loadFixture(double[] wgs){
        if(fixtures==null)return false;
        for(String name:new String[]{"shenzhen","hongkong"}){
            try{byte[] d=fixtures.read(name);if(d==null||d.length>FIXTURE_BYTES)continue;
                Map<String,Object> j=BoundedJson.map(BoundedJson.readLarge(d,FIXTURE_BYTES,FIXTURE_NODES));
                List<Object> b=BoundedJson.list(BoundedJson.map(j.get("meta")).get("bbox")),list=BoundedJson.list(BoundedJson.map(j.get("geojson")).get("features"));
                if(b.size()!=4||list.size()>5000)continue;double[] box=new double[4];boolean valid=true;
                for(int i=0;i<4;i++){box[i]=num(b.get(i));valid&=Double.isFinite(box[i])&&box[i]>=-180&&box[i]<=180;}
                if(!valid||wgs[0]<box[0]||wgs[0]>box[2]||wgs[1]<box[1]||wgs[1]>box[3])continue;
                installFeatures(list,box);note="公开区域离线路网 · © OpenStreetMap";return true;
            }catch(RuntimeException e){/* malformed fixture: try the next one */}
        }
        return false;
    }
    private static boolean sameSegment(Object a,Object b){if(a==null||b==null)return false;if(a instanceof Number&&b instanceof Number)return ((Number)a).doubleValue()==((Number)b).doubleValue();return a.equals(b);}
    private boolean hasVisibleLabelsAt(double[] position,int heading){
        if(scene2==null||origin==null)return false;double[] p=xy(position,origin);double x=p[0]*4,y=p[1]*4;if(Math.abs(x)>2000||Math.abs(y)>2000)return false;
        return !NavMapCodec.labels(scene2,(int)lround(x),(int)lround(y),heading%360).isEmpty();
    }
    private static int headingInt(double h){return Double.isFinite(h)?(int)(((long)h%360+360)%360):0;}

    /** Decorates a navigating frame (route and position in the map datum, times in seconds on one monotonic clock).
     * Null means "pass through": disabled, not navigating, stale (>4 s) position, failed inverse, or no scene. */
    synchronized Result decorate(String phase,List<double[]> route,double[] position,double positionAt,double heading,Object seg,double now){
        if(!enabled||!"navigating".equals(phase)||route==null||route.size()<2||route.size()>512||!ll(position)||!Double.isFinite(positionAt)||positionAt<0||now-positionAt>4)return null;
        double[] w=wgs(position);if(w==null){note="坐标转换未收敛 · 不显示错位路网";return null;}
        boolean covered=hasCoverage(w,0);if(!covered)covered=loadFixture(w);
        if(covered)note=inFlight?"周边路网已显示 · 正在预取下一段":"周边路网已就绪 · © OpenStreetMap";
        else note=inFlight?"正在加载周边道路 · 保留已知路网":allowNetwork?(requests>=REQUEST_LIMIT?"本次图源请求已达上限 · 仅显示已有道路":"当前区域路网暂缺 · 保留已有道路"):"未授权周边道路 · 仅显示已有道路";
        double turn=Math.abs(((heading-labelHeading+540)%360+360)%360-180);
        boolean refreshNames=!features.isEmpty()&&now-sceneAt>=3&&(turn>=30||distance(position,origin!=null?origin:position)>50||!hasVisibleLabelsAt(position,headingInt(heading)));
        if(scene==null||origin==null||distance(position,origin)>100||!sameSegment(segment,seg)||refreshNames){
            origin=position.clone();segment=seg;labelHeading=heading;sceneAt=now;scene=build(route,origin);}
        if(scene==null)return null;double[] p=xy(position,origin);double x=p[0]*4,y=p[1]*4;if(Math.abs(x)>2000||Math.abs(y)>2000)return null;
        byte[] pose=new byte[12];w32(pose,0,generation);w16(pose,4,lround(x));w16(pose,6,lround(y));w16(pose,8,headingInt(heading));
        return new Result(scene,scene2,pose,positionAt,note);
    }

    private byte[] build(List<double[]> route,double[] origin){
        List<Item> items=new ArrayList<>();int visited=0;
        outer:for(Object fo:features){if(++visited>10000)break;if(!(fo instanceof Map))continue;Map<?,?> f=(Map<?,?>)fo;
            if(!(f.get("properties") instanceof Map)||!(f.get("geometry") instanceof Map))continue;Map<?,?> p=(Map<?,?>)f.get("properties"),g=(Map<?,?>)f.get("geometry");
            if(!"road".equals(p.get("kind"))||!"LineString".equals(g.get("type"))||!(g.get("coordinates") instanceof List))continue;
            if("yes".equals(text(p.get("area"))))continue;
            int st=style(text(p.get("highway")));String bridge=text(p.get("bridge")),tunnel=text(p.get("tunnel")),zh=text(p.get("name:zh"));
            for(List<int[]> part:pieces(osm((List<?>)g.get("coordinates")),origin)){if(part.size()<2)continue;double rank=Double.MAX_VALUE;
                for(int i=1;i<part.size();i++){double x=part.get(i-1)[0],y=part.get(i-1)[1],dx=part.get(i)[0]-x,dy=part.get(i)[1]-y,t=Math.max(0,Math.min(1,-(x*dx+y*dy)/Math.max(1,dx*dx+dy*dy)));rank=Math.min(rank,Math.hypot(x+dx*t,y+dy*t)/4);}
                Item it=new Item();it.points=part;it.style=st;it.flags=(!bridge.isEmpty()&&!bridge.equals("no")?1:0)|(!tunnel.isEmpty()&&!tunnel.equals("no")?2:0);
                it.layer=Math.max(-8,Math.min(8,intValue(text(p.get("layer")))));it.name=!zh.isEmpty()?zh:text(p.get("name"));it.rank=rank+st*18;items.add(it);if(items.size()>4096)break outer;}
        }
        Comparator<Item> byRank=(a,b)->Double.compare(a.rank,b.rank);items.sort(byRank);
        List<Item> candidates=new ArrayList<>();
        for(List<int[]> part:pieces(route,origin))if(part.size()>=2){Item it=new Item();it.points=part;it.style=6;it.layer=8;it.name="";candidates.add(it);}
        candidates.addAll(items);
        List<Item> selected=new ArrayList<>();int points=0;
        for(Item item:candidates){List<int[]> part=simplify(item.points);
            if(selected.size()>=NavMapCodec.MAX_PATHS||points+part.size()>NavMapCodec.MAX_POINTS||16+8*(selected.size()+1)+4*(points+part.size())+40*NavMapCodec.MAX_LABELS+12>NavMapCodec.MAX_BYTES-32)continue;
            points+=part.size();Item s=new Item();s.points=part;s.style=item.style;s.flags=item.flags;s.layer=item.layer;s.name=item.name;s.rank=item.rank;selected.add(s);}
        selected.sort((a,b)->a.style==6||b.style==6?Integer.compare(a.style==6?1:0,b.style==6?1:0):Integer.compare(a.layer,b.layer));
        if(selected.isEmpty()||points==0||generation==0xffffffffL)return null;
        byte[] out=new byte[16+8*selected.size()+4*points];w32(out,0,++generation);w16(out,4,320);w16(out,6,selected.size());w16(out,8,points);int at=16+8*selected.size();
        for(int i=0;i<selected.size();i++){Item r=selected.get(i);w16(out,16+8*i,r.points.size());out[18+8*i]=(byte)r.style;out[19+8*i]=(byte)r.flags;out[20+8*i]=(byte)r.layer;
            for(int[] q:r.points){w16(out,at,q[0]);w16(out,at+2,q[1]);at+=4;}}
        // Labels come only from real road tags: ≤4 unique names anchored on visible road points, using the firmware's
        // heading transform and occlusion zones with an extra margin; the firmware still culls on every pose.
        java.io.ByteArrayOutputStream labels=new java.io.ByteArrayOutputStream();Set<String> seen=new HashSet<>();List<double[]> occupied=new ArrayList<>();
        double radians=labelHeading*Math.PI/180,ss=Math.sin(radians),cc=Math.cos(radians);
        List<Item> ranked=new ArrayList<>(selected);ranked.sort(byRank);
        for(Item item:ranked){byte[] name=nameData(item.name);String key=new String(name,StandardCharsets.UTF_8);if(name.length==0||seen.contains(key))continue;
            int width=0;for(int j=0;j<key.length();j++)width+=key.charAt(j)<128?9:16;
            List<int[]> part=item.points;int[] anchor=null;double[] rect=null;double best=Double.MAX_VALUE;
            for(int j=1;j<part.size();j++)for(int step=0;step<=16;step++){
                double t=step/16.,x=part.get(j-1)[0]*(1-t)+part.get(j)[0]*t,y=part.get(j-1)[1]*(1-t)+part.get(j)[1]*t;
                double px=96+(x*cc-y*ss)*192/1280.,py=101-(x*ss+y*cc)*192/1280.,left=px-width/2.,top=py-10;
                if(left<7||left+width>185||top<7||top+20>137||(left<115&&left+width>77&&top<118&&top+20>79)||(left<74&&left+width>0&&top<147&&top+20>112))continue;
                boolean collision=false;for(double[] r:occupied)if(left<r[0]+r[2]+8&&left+width+8>r[0]&&top<r[1]+28&&top+28>r[1]){collision=true;break;}if(collision)continue;
                double score=(px-96)*(px-96)+(py-48)*(py-48);if(score<best){best=score;anchor=new int[]{(int)lround(x),(int)lround(y)};rect=new double[]{left,top,width};}}
            if(anchor==null)continue;byte[] q=new byte[40];w16(q,0,anchor[0]);w16(q,2,anchor[1]);q[4]=(byte)name.length;System.arraycopy(name,0,q,8,name.length);labels.write(q,0,40);
            seen.add(key);occupied.add(rect);if(seen.size()>=NavMapCodec.MAX_LABELS)break;}
        byte[] lb=labels.toByteArray(),v2=Arrays.copyOf(out,out.length+lb.length+12);System.arraycopy(lb,0,v2,out.length,lb.length);w32(v2,v2.length-12,generation);w16(v2,10,seen.size());
        scene2=NavMapCodec.bodyValid(NavMapCodec.SCENE2,v2)?v2:null;
        return NavMapCodec.bodyValid(NavMapCodec.SCENE,out)?out:null;
    }
}
