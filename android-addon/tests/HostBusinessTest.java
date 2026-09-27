package com.turboio.addon;
public final class HostBusinessTest {
    static int count;
    static void expect(Object raw,int id){count++;if(HostBusiness.id(raw)!=id)throw new AssertionError("business "+raw);}
    public static void main(String[] args){
        for(Object raw:new Object[]{15,15L,"15","LAUNCHER"})expect(raw,15);
        for(Object raw:new Object[]{9,9L,"9","MARS_FOTA"})expect(raw,9);
        for(Object raw:new Object[]{19,"19","AI_SUBTITLE"})expect(raw,19);
        for(Object raw:new Object[]{20,"20","TELEPROMPTER"})expect(raw,20);
        for(Object raw:new Object[]{null,"",true,15.0,15.1,"15.0","launcher"," LAUNCHER","LAUNCHER_SUFFIX",0,18,-1,4294967311L,new Object()})expect(raw,-1);
        System.out.println("HostBusiness: "+count+" checks");
    }
}
