package com.turboio.addon;

/** First check in the SDK send-queue hook (before the OTA policies). Fail-open: any error lets the message through.
 * Records recent official LAUNCHER traffic and blocks an official start_log_task while we own a log request. */
public final class QueueTap {
    static final ThreadLocal<Object> OWN=new ThreadLocal<>();
    private QueueTap(){}
    public static boolean allow(Object message){
        try{
            if(message==null||message==OWN.get())return true;
            Object biz=NavReflect.field(message,"c");if(!(biz instanceof Enum))return true;String name=((Enum<?>)biz).name();
            if(!"LAUNCHER".equals(name)&&!"LOG_REPORT".equals(name))return true;
            Object d=NavReflect.field(message,"b"),p=NavReflect.field(message,"e");if(!(d instanceof String)||!(p instanceof byte[])||((byte[])p).length>8192)return true;
            return GlassesLog.queue(name,(String)d,(byte[])p);
        }catch(Throwable t){return true;}
    }
}
