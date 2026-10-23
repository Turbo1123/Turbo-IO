package com.turboio.addon;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Didi sandbox MCP JSON-RPC (port of iOS RideRPC.m): only five sandbox tools, JSON or SSE replies matched by id,
 * fixed error texts; the key (URL query) is never part of any message. */
final class DrRpc {
    static final String ENDPOINT="https://mcp.didichuxing.com/mcp-servers-sandbox";
    static final List<String> TOOLS=Collections.unmodifiableList(Arrays.asList("maps_textsearch","taxi_estimate","taxi_create_order","taxi_query_order","taxi_cancel_order"));
    static final int MAX_BYTES=1048576;
    private DrRpc(){}
    static final class Result{final Map<String,Object> result;final String error;Result(Map<String,Object> r,String e){result=r;error=e;}}
    static boolean allowed(String tool){return TOOLS.contains(tool);}
    /** Sandbox key: 1..512 characters, no whitespace. */
    static boolean validKey(String key){if(key==null||key.isEmpty()||key.length()>512)return false;for(int i=0;i<key.length();i++)if(Character.isWhitespace(key.charAt(i))||Character.isISOControl(key.charAt(i)))return false;return true;}
    static byte[] body(String id,String tool,Map<String,Object> args){
        Map<String,Object> params=new LinkedHashMap<>(),b=new LinkedHashMap<>();params.put("name",tool);params.put("arguments",args);
        b.put("jsonrpc","2.0");b.put("id",id);b.put("method","tools/call");b.put("params",params);return BoundedJson.canonical(b);
    }
    private static Object json(byte[] b,int cap){try{return BoundedJson.readLarge(b,cap,200000);}catch(RuntimeException e){return null;}}
    /** DRUnwrap: structuredContent, else the first text content parsed as JSON (array → rows) or kept as serverMessage. */
    static Map<String,Object> unwrap(Object o){
        if(!(o instanceof Map)||Boolean.TRUE.equals(((Map<?,?>)o).get("isError")))return null;Map<?,?> d=(Map<?,?>)o;
        if(d.get("structuredContent") instanceof Map)return BoundedJson.map(d.get("structuredContent"));
        if(d.get("content") instanceof List)for(Object c:(List<?>)d.get("content")){if(!(c instanceof Map)||!(((Map<?,?>)c).get("text") instanceof String))continue;String text=(String)((Map<?,?>)c).get("text");
            Object j=json(text.getBytes(StandardCharsets.UTF_8),MAX_BYTES);
            if(j instanceof Map)return BoundedJson.map(j);
            if(j instanceof List){Map<String,Object> r=new LinkedHashMap<>();r.put("rows",j);return r;}
            if(j==null&&text.length()<=4000){Map<String,Object> r=new LinkedHashMap<>();r.put("serverMessage",text);return r;}}
        return null;
    }
    static Result parse(byte[] data,String id){
        Object j=json(data,MAX_BYTES);
        if(!(j instanceof Map)){String text=new String(data,StandardCharsets.UTF_8);
            for(String line:text.split("\n")){if(!line.startsWith("data:"))continue;Object part=json(line.substring(5).trim().getBytes(StandardCharsets.UTF_8),MAX_BYTES);if(part instanceof Map&&id.equals(((Map<?,?>)part).get("id"))){j=part;break;}}}
        if(j instanceof Map&&id.equals(((Map<?,?>)j).get("id"))&&((Map<?,?>)j).get("error") instanceof Map){Object c=((Map<?,?>)((Map<?,?>)j).get("error")).get("code");long code=c instanceof Number?((Number)c).longValue():0;
            return new Result(null,"沙箱接口错误（"+code+"）"+(code==-32001?"：限流，查询稍后再试；订单操作不自动重试":"：未自动重试"));}
        if(!(j instanceof Map)||!id.equals(((Map<?,?>)j).get("id"))||((Map<?,?>)j).get("error")!=null||!(((Map<?,?>)j).get("result") instanceof Map))return new Result(null,"沙箱 RPC 返回异常，未重试");
        Map<String,Object> r=unwrap(((Map<?,?>)j).get("result"));return r!=null?new Result(r,null):new Result(null,"沙箱返回业务错误，未重试");
    }
}
