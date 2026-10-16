package com.turboio.addon;

/** Obfuscated host names per pinned host build; selected once by probing the 1.0.6 manager. */
final class HostAbi {
    final String manager, message, priority, business, error, core, send, file, version;
    private HostAbi(String version,String pkg,String sdk,String core,String send,String file){
        this.version=version;manager=pkg+".u";message=pkg+".Q";priority=pkg+".b";business=sdk+".h";error=sdk+".A";this.core=core+".q";this.send=send;this.file=file;
    }
    static final HostAbi V105=new HostAbi("1.0.5","E3","P3","Q3","u","v");
    static final HostAbi V106=new HostAbi("1.0.6","X3","i4","j4","t","u");
    private static volatile HostAbi current;
    static HostAbi get(){
        HostAbi a=current;if(a!=null)return a;
        a=matches(V106)?V106:V105;current=a;return a;
    }
    private static boolean matches(HostAbi a){
        try{Class<?> m=Class.forName(a.manager);return m.getField("h").getType()==m&&Class.forName(a.business).isEnum();}catch(Throwable e){return false;}
    }
    static String manager(){return get().manager;}
    static String message(){return get().message;}
    static String priority(){return get().priority;}
    static String business(){return get().business;}
    static String error(){return get().error;}
    static String core(){return get().core;}
    static String send(){return get().send;}
    static String file(){return get().file;}
}
