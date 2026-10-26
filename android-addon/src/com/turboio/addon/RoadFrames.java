package com.turboio.addon;
import java.util.*;

/** Navigation-side TNR3 helpers (iOS NavigationRoadMap.inc / NavigationCore.m): the public-area replay, its TNV1
 * scene (TIONavDisplay + TNVNormalizeCoordinates), AMap icon mapping, and route heading / window for live frames. */
final class RoadFrames {
    static final int REPLAY_BYTES=1024*1024;
    private RoadFrames(){}
    static final class Sample{
        double[] position;List<double[]> route;double heading;Object segment;int icon,meters,remaining,seconds;String road;
    }
    private static double num(Object o){if(!(o instanceof Number))throw new IllegalArgumentException("replay number");double v=((Number)o).doubleValue();if(!Double.isFinite(v))throw new IllegalArgumentException("replay number");return v;}
    private static double[] ll(Object o){List<Object> p=BoundedJson.list(o);if(p.size()!=2)throw new IllegalArgumentException("replay point");double[] v={num(p.get(0)),num(p.get(1))};if(!RoadScene.ll(v))throw new IllegalArgumentException("replay point");return v;}
    /** Bundled replay.json frames (2..300), one per second; positions and routes are WGS-84. */
    static final class Replay{
        private final List<Map<String,Object>> frames=new ArrayList<>();
        Replay(List<Object> list){
            if(list==null||list.size()<2||list.size()>300)throw new IllegalArgumentException("replay frames");
            for(Object o:list){Map<String,Object> m=BoundedJson.map(o);ll(m.get("position"));num(m.get("heading"));List<Object> r=BoundedJson.list(m.get("route"));if(r.size()<2||r.size()>512)throw new IllegalArgumentException("replay route");frames.add(m);}
        }
        int size(){return frames.size();}
        /** Interpolated sample at elapsed seconds; null once the last frame is reached (iOS stops the replay). */
        Sample at(double elapsed){
            if(!(elapsed>=0))return null;int index=(int)elapsed;if(index>=frames.size()-1)return null;double fraction=elapsed-index;
            Map<String,Object> m=frames.get(index),next=frames.get(index+1);double[] a=ll(m.get("position")),b=ll(next.get("position"));
            Sample s=new Sample();s.position=new double[]{a[0]+(b[0]-a[0])*fraction,a[1]+(b[1]-a[1])*fraction};
            s.route=new ArrayList<>();for(Object p:BoundedJson.list(m.get("route")))s.route.add(ll(p));
            double heading=num(m.get("heading")),delta=((num(next.get("heading"))-heading+540)%360+360)%360-180;s.heading=((heading+delta*fraction)%360+360)%360;
            s.segment=m.get("segment");s.icon=(int)num(m.get("icon"));s.meters=(int)num(m.get("meters"));s.remaining=(int)num(m.get("remaining"));s.seconds=(int)num(m.get("seconds"));
            s.road=m.get("road") instanceof String?(String)m.get("road"):"";return s;
        }
    }
    /** AMapNaviIconType → TNV1 icon (TNVScene). */
    static int icon(int amap){switch(amap){case 2:return 2;case 3:return 3;case 4:return 4;case 5:return 5;case 6:return 6;case 7:return 7;case 8:case 19:return 8;case 9:case 20:return 1;case 11:case 12:case 17:case 18:return 9;case 15:return 10;default:return 0;}}
    /** TIONavTurn: unknown values never imply straight ahead. */
    static String turn(int amap){switch(amap){case 2:return "前方左转";case 3:return "前方右转";case 4:return "向左前方";case 5:return "向右前方";case 6:return "向左后方";case 7:return "向右后方";case 8:case 19:return "前方掉头";case 9:case 20:return "继续直行";case 10:return "到达途经点";case 11:case 17:return "进入环岛";case 12:case 18:return "离开环岛";case 15:return "到达目的地";case 29:return "通过人行横道";case 30:return "通过过街天桥";case 31:return "通过地下通道";default:return "请查看手机指引";}}
    /** TNVNormalizeCoordinates: ≤32 schematic points in 0..1023 (north-up, fitted to 900 px) and the first-segment heading. */
    static int[][] normalize(List<double[]> coords,int[] heading){
        if(coords==null||coords.size()<2||coords.size()>512)return null;int n=coords.size();double[] xs=new double[n],ys=new double[n];double loX=Double.MAX_VALUE,loY=Double.MAX_VALUE,hiX=-Double.MAX_VALUE,hiY=-Double.MAX_VALUE;
        double ref=coords.get(0)[0],lon0=coords.get(0)[1];
        for(int i=0;i<n;i++){double[] p=coords.get(i);if(p==null||p.length!=2||!Double.isFinite(p[0])||!Double.isFinite(p[1])||Math.abs(p[0])>85||Math.abs(p[1])>180)return null;
            xs[i]=(p[1]-lon0)*Math.cos(ref*Math.PI/180);ys[i]=-(p[0]-ref);loX=Math.min(loX,xs[i]);hiX=Math.max(hiX,xs[i]);loY=Math.min(loY,ys[i]);hiY=Math.max(hiY,ys[i]);}
        double span=Math.max(hiX-loX,hiY-loY);if(span<1e-10)return null;int count=Math.min(n,32);int[][] out=new int[count][2];
        for(int i=0;i<count;i++){int at=i*(n-1)/(count-1);out[i][0]=(int)Math.round(511.5+(xs[at]-(loX+hiX)*.5)*900/span);out[i][1]=(int)Math.round(511.5+(ys[at]-(loY+hiY)*.5)*900/span);}
        double h=Math.atan2(xs[1]-xs[0],-(ys[1]-ys[0]))*180/Math.PI;if(h<0)h+=360;heading[0]=(int)Math.round(h)%360;return out;
    }
    /** TNV1 scene for a replay sample (TIONavDisplay "navigating" + TNVScene); coords in the map datum. */
    static NativeNavCodec.Scene scene(Sample s,List<double[]> coords,boolean always){
        NativeNavCodec.Scene out=new NativeNavCodec.Scene();out.icon=icon(s.icon);out.mode=always?1:0;out.distance=Math.max(0,Math.min(1000000,s.meters));out.remaining=Math.max(0,Math.min(10000000,s.remaining));out.seconds=Math.max(0,Math.min(604800,s.seconds));
        out.road=NativeNavCodec.clip(s.road.isEmpty()?"按照道路实际指示通行":"进入 "+s.road,96);out.turn=NativeNavCodec.clip(turn(s.icon),48);
        int[] h=new int[1];int[][] pts=normalize(coords,h);if(pts!=null){out.points=pts;out.x=pts[0][0];out.y=pts[0][1];out.heading=h[0];}return out;
    }
    private static double[] local(double[] p,double[] o){return new double[]{(p[1]-o[1])*111319.49*Math.cos(o[0]*Math.PI/180),(p[0]-o[0])*111319.49};}
    /** Bearing (degrees clockwise from north) of the route segment nearest to p; NaN when undefined. */
    static double heading(List<double[]> route,double[] p){
        double best=Double.MAX_VALUE,bearing=Double.NaN;
        for(int i=1;i<route.size();i++){double[] a=local(route.get(i-1),p),b=local(route.get(i),p);double dx=b[0]-a[0],dy=b[1]-a[1],len=dx*dx+dy*dy;if(len<1e-6)continue;
            double t=Math.max(0,Math.min(1,-(a[0]*dx+a[1]*dy)/len)),ex=a[0]+dx*t,ey=a[1]+dy*t,dist=ex*ex+ey*ey;if(dist<best){best=dist;double h=Math.atan2(dx,dy)*180/Math.PI;bearing=h<0?h+360:h;}}
        return bearing;
    }
    /** At most 512 consecutive route points around the vertex nearest p (RoadScene refuses longer routes). */
    static List<double[]> window(List<double[]> route,double[] p){
        if(route.size()<=512)return route;int at=0;double best=Double.MAX_VALUE;for(int i=0;i<route.size();i++){double[] q=local(route.get(i),p);double d=q[0]*q[0]+q[1]*q[1];if(d<best){best=d;at=i;}}
        int start=Math.max(0,Math.min(at-255,route.size()-512));return route.subList(start,start+512);
    }
}
