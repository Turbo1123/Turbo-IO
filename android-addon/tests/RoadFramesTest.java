package com.turboio.addon;
import java.nio.file.*;import java.util.*;

/** Navigation-side TNR3 glue (iOS NavigationRoadMap.inc / NavigationCore.m): replay interpolation, TNV1 replay
 * scene (TIONavDisplay + TNVNormalizeCoordinates), AMap icon mapping, route heading and the ≤512-point window. */
public final class RoadFramesTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("road frames "+n+" "+why);}
    static double d(Object o){return ((Number)o).doubleValue();}
    public static void main(String[] a)throws Exception{
        List<Object> frames=BoundedJson.list(BoundedJson.readLarge(Files.readAllBytes(Paths.get(a[0]).resolve("replay.json")),RoadFrames.REPLAY_BYTES,RoadScene.FIXTURE_NODES));
        RoadFrames.Replay replay=new RoadFrames.Replay(frames);
        Map<String,Object> f0=BoundedJson.map(frames.get(0)),f1=BoundedJson.map(frames.get(1));List<Object> p0=BoundedJson.list(f0.get("position")),p1=BoundedJson.list(f1.get("position"));
        RoadFrames.Sample s=replay.at(0);ok(s.position[0]==d(p0.get(0))&&s.position[1]==d(p0.get(1))&&s.route.size()==BoundedJson.list(f0.get("route")).size(),"first sample");
        s=replay.at(.5);ok(Math.abs(s.position[0]-(d(p0.get(0))+d(p1.get(0)))/2)<1e-12&&Math.abs(s.position[1]-(d(p0.get(1))+d(p1.get(1)))/2)<1e-12,"linear position");
        ok(s.icon==((Number)f0.get("icon")).intValue()&&s.road.equals(f0.get("road"))&&s.meters==63&&s.remaining==6808&&s.seconds==1702&&Objects.equals(s.segment,f0.get("segment")),"sample fields from the current frame");
        ok(replay.at(178.5)!=null&&replay.at(179)==null&&replay.at(-1)==null,"ends at the last frame");
        List<Object> turning=new ArrayList<>();for(double h:new double[]{350,10}){Map<String,Object> m=new TreeMap<>(f0);m.put("heading",h);turning.add(m);}
        ok(Math.abs(new RoadFrames.Replay(turning).at(.5).heading)<1e-9,"heading interpolates the short way (350→10 = 0)");
        boolean refused=false;try{new RoadFrames.Replay(frames.subList(0,1));}catch(IllegalArgumentException e){refused=true;}ok(refused,"one frame refused");
        // Icons and text (AMapNaviIconType → TNV1 icon, TIONavTurn).
        int[][] icons={{2,2},{3,3},{4,4},{5,5},{6,6},{7,7},{8,8},{19,8},{9,1},{20,1},{11,9},{12,9},{17,9},{18,9},{15,10},{1,0},{13,0},{29,0}};
        for(int[] c:icons)ok(RoadFrames.icon(c[0])==c[1],"icon "+c[0]);
        ok(RoadFrames.turn(3).equals("前方右转")&&RoadFrames.turn(20).equals("继续直行")&&RoadFrames.turn(99).equals("请查看手机指引"),"turn text");
        // TNV1 replay scene: road "进入 …", schematic from TNVNormalizeCoordinates, heading from the first segment.
        s=replay.at(0);NativeNavCodec.Scene scene=RoadFrames.scene(s,s.route,true);
        ok(scene.road.equals("进入 前方道路")&&scene.turn.equals("前方右转")&&scene.mode==1&&scene.distance==63&&scene.remaining==6808&&scene.seconds==1702,"scene text and numbers");
        ok(scene.points.length>=2&&scene.points.length<=32&&scene.x==scene.points[0][0]&&scene.y==scene.points[0][1]&&Math.abs(scene.heading-90)<=1&&NativeNavCodec.scene(scene).length>0,"schematic and heading");
        Map<String,Object> blank=new TreeMap<>(f0);blank.put("road","");RoadFrames.Sample b2=new RoadFrames.Replay(Arrays.asList(blank,f1)).at(0);ok(RoadFrames.scene(b2,b2.route,false).road.equals("按照道路实际指示通行"),"empty road text");
        List<double[]> line=new ArrayList<>();for(int i=0;i<600;i++)line.add(new double[]{22.5,114+i*1e-4});
        ok(RoadFrames.normalize(line.subList(0,1),new int[1])==null&&RoadFrames.normalize(line,new int[1])==null&&RoadFrames.normalize(Arrays.asList(new double[]{22.5,114},new double[]{22.5,114}),new int[1])==null,"normalize bounds");
        int[] h=new int[1];int[][] pts=RoadFrames.normalize(line.subList(0,100),h);ok(pts.length==32&&h[0]==90&&pts[0][0]<pts[31][0],"normalize samples 32, heading east");
        // Route heading and window for live navigation.
        ok(Math.abs(RoadFrames.heading(line,new double[]{22.5001,114.0105})-90)<1e-6,"heading of the nearest segment");
        List<double[]> north=Arrays.asList(new double[]{22.5,114},new double[]{22.6,114});ok(Math.abs(RoadFrames.heading(north,new double[]{22.55,114})-0)<1e-6,"north");
        List<double[]> w=RoadFrames.window(line,new double[]{22.5,114+550e-4});ok(w.size()==512&&w.get(w.size()-1)==line.get(599)&&w.contains(line.get(550)),"window ≤512 around the position");
        ok(RoadFrames.window(line.subList(0,100),line.get(0)).size()==100,"short route whole");
        System.out.println("RoadFramesTest: "+n+" checks; replay, icons, scene, normalize, heading, window");
    }
}
