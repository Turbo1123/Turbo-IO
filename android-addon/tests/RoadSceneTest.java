package com.turboio.addon;
import java.nio.file.*;import java.util.*;

/** TNR3 road scene builder (port of iOS RoadMap.m) against the bundled public-area fixtures. */
public final class RoadSceneTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("road scene "+n+" "+why);}
    static int u16(byte[] p,int at){return (p[at]&255)|(p[at+1]&255)<<8;}
    static long gen(byte[] p){return HexCarrier.u32(p,0);}
    public static void main(String[] a)throws Exception{
        Path maps=Paths.get(a[0]);RoadScene.Fixtures fixtures=name->{try{return Files.readAllBytes(maps.resolve(name+".json"));}catch(Exception e){return null;}};
        // Large map documents use their own bound; the default 64 KiB reader is unchanged.
        byte[] big=Files.readAllBytes(maps.resolve("shenzhen.json"));boolean refused=false;try{BoundedJson.read(big);}catch(IllegalArgumentException e){refused=true;}ok(refused,"default reader still bounded");
        List<Object> replay=BoundedJson.list(BoundedJson.readLarge(Files.readAllBytes(maps.resolve("replay.json")),2*1024*1024,400000));ok(replay.size()==180,"replay");
        RoadScene rs=new RoadScene((lat,lon)->new double[]{lat,lon},fixtures);rs.setEnabled(true);double now=1000;long lastGen=0;int scenes=0,named=0;
        for(int i=0;i<180;i+=6){Map<String,Object> s=BoundedJson.map(replay.get(i));now+=6;
            List<double[]> route=new ArrayList<>();for(Object p:BoundedJson.list(s.get("route"))){List<Object> q=BoundedJson.list(p);route.add(new double[]{((Number)q.get(0)).doubleValue(),((Number)q.get(1)).doubleValue()});}
            List<Object> pos=BoundedJson.list(s.get("position"));double[] position={((Number)pos.get(0)).doubleValue(),((Number)pos.get(1)).doubleValue()};
            RoadScene.Result r=rs.decorate("navigating",route,position,now,((Number)s.get("heading")).doubleValue(),s.get("segment"),now);
            ok(r!=null&&r.scene!=null&&r.scene2!=null&&r.pose!=null,"scene and scene2 at sample "+i);
            ok(NavMapCodec.bodyValid(NavMapCodec.SCENE,r.scene)&&NavMapCodec.bodyValid(NavMapCodec.POSE,r.pose)&&gen(r.pose)==gen(r.scene),"valid scene/pose "+i);
            if(r.scene2!=null){ok(NavMapCodec.bodyValid(NavMapCodec.SCENE2,r.scene2)&&gen(r.scene2)==gen(r.scene),"valid scene2 "+i);int labels=u16(r.scene2,10),paths2=u16(r.scene2,6),pts2=u16(r.scene2,8);ok(labels<=4,"labels<=4");named+=labels;Set<String> names=new HashSet<>();for(int k=0;k<labels;k++){int q=16+8*paths2+4*pts2+40*k;ok(names.add(new String(r.scene2,q+8,r.scene2[q+4]&255,"UTF-8")),"unique label "+i);}}
            int paths=u16(r.scene,6);ok(paths<=96&&u16(r.scene,8)<=768,"budget "+i);ok((r.scene[16+8*(paths-1)+2]&255)==6,"route style 6 last "+i);
            ok(gen(r.scene)>=lastGen,"generation monotonic");if(gen(r.scene)>lastGen)scenes++;lastGen=gen(r.scene);
            ok(r.note.contains("OpenStreetMap"),"attribution "+r.note);}
        ok(named>0,"road names labelled ("+named+")");ok(scenes>=2,"rebuilt as the position moved ("+scenes+")");
        // Same place, same heading, same segment, within 3 s: the scene is reused (no new generation).
        Map<String,Object> s0=BoundedJson.map(replay.get(60));List<double[]> route=new ArrayList<>();for(Object p:BoundedJson.list(s0.get("route"))){List<Object> q=BoundedJson.list(p);route.add(new double[]{((Number)q.get(0)).doubleValue(),((Number)q.get(1)).doubleValue()});}
        List<Object> pos=BoundedJson.list(s0.get("position"));double[] here={((Number)pos.get(0)).doubleValue(),((Number)pos.get(1)).doubleValue()};double h=((Number)s0.get("heading")).doubleValue();
        RoadScene.Result r1=rs.decorate("navigating",route,here,now+10,h,"seg-x",now+10),r2=rs.decorate("navigating",route,here,now+11,h+5,"seg-x",now+11);
        ok(r1!=null&&r2!=null&&gen(r1.scene)==gen(r2.scene),"reused within 100 m / 3 s / same segment");
        ok(rs.decorate("navigating",route,here,now+12,h,"seg-y",now+12).scene!=r2.scene,"segment change rebuilds");
        // Pass-through cases.
        ok(rs.decorate("navigating",route,here,now,h,"seg-y",now+20)==null,"stale position (>4 s)");
        ok(rs.decorate("arrived",route,here,now+30,h,"seg-y",now+30)==null,"not navigating");
        RoadScene off=new RoadScene((lat,lon)->new double[]{lat,lon},fixtures);ok(off.decorate("navigating",route,here,now,h,0,now)==null,"disabled by default");
        // Coordinate inverse: identity converges; a broken converter refuses to show roads.
        ok(Arrays.equals(rs.wgs(here),here),"identity inverse");
        RoadScene bad=new RoadScene((lat,lon)->new double[]{lat*2,lon},fixtures);bad.setEnabled(true);ok(bad.decorate("navigating",route,here,now,h,0,now)==null&&bad.note().contains("未收敛"),"non-converging inverse");
        // Outside fixture coverage and no network consent: no scene, request wanted.
        RoadScene far=new RoadScene((lat,lon)->new double[]{lat,lon},fixtures);far.setEnabled(true);double[] paris={48.8566,2.3522};
        RoadScene.Result bare=far.decorate("navigating",Arrays.asList(paris,new double[]{48.857,2.353}),paris,now,0,0,now);
        ok(bare!=null&&u16(bare.scene,6)==1&&bare.scene[18]==6&&far.needsRequest(paris)&&bare.note.contains("未授权"),"no coverage: route-only scene (as iOS), needs request");
        // Fixtures are read and parsed at most once per name, not on every uncovered frame.
        int[] reads={0};RoadScene once=new RoadScene((lat,lon)->new double[]{lat,lon},name->{reads[0]++;return fixtures.read(name);});once.setEnabled(true);
        for(int k=0;k<5;k++)once.decorate("navigating",Arrays.asList(paris,new double[]{48.857,2.353}),paris,now+k,0,0,now+k);
        ok(reads[0]==2,"each fixture read once while uncovered ("+reads[0]+")");
        RoadScene.Result in=once.decorate("navigating",route,here,now+6,h,0,now+6);ok(reads[0]==2&&in!=null&&u16(in.scene,6)>1,"cached fixture installs on entering its area");
        // Building blocks.
        List<int[]> line=Arrays.asList(new int[]{0,0},new int[]{40,3},new int[]{80,0},new int[]{120,200});List<int[]> simple=RoadScene.simplify(line);ok(simple.size()==3&&simple.get(0)[0]==0&&simple.get(2)[1]==200,"simplify drops a point within 2 m, keeps ends");
        ok(RoadScene.style("motorway")==0&&RoadScene.style("trunk_link")==0&&RoadScene.style("primary_link")==1&&RoadScene.style("secondary")==2&&RoadScene.style("tertiary_link")==3&&RoadScene.style("living_street")==4&&RoadScene.style("footway")==5,"style table");
        ok(new String(RoadScene.nameData("Main‮St"),"UTF-8").equals("MainSt")&&RoadScene.nameData("深南大道深南大道").length<=31&&NavMapCodec.textWidth(RoadScene.nameData("深南大道深南大道"),0,RoadScene.nameData("深南大道深南大道").length)>0,"name filter and width cap");
        System.out.println("RoadSceneTest: "+n+" checks; fixtures, budgets, refresh rules, inverse, building blocks");
    }
}
