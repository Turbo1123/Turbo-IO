package com.turboio.addon;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** didi_ride model tool (port of iOS RideTool.m): exact spec text and strict per-action arguments. */
final class DrTool {
    static final String SPEC="{\"type\":\"function\",\"function\":{\"name\":\"didi_ride\",\"description\":\"滴滴出行沙箱（非真实订单）。用户要打车时调用。search(city,query)搜索地点并返回可选id；estimate(from_id,to_id)用已经选定的地点预估；prepare(product_id)显示车型价格并等待眼镜旋钮确认；status查询；prepare_cancel显示取消确认。不得自行确认、不得说已叫到真实车。未指定起点/目的地时追问；地点不唯一让用户选择；坐标/车型/订单ID只能来自本工具。一次只调用一个工具。\",\"parameters\":{\"type\":\"object\",\"properties\":{\"action\":{\"type\":\"string\",\"enum\":[\"search\",\"estimate\",\"prepare\",\"status\",\"prepare_cancel\"]},\"city\":{\"type\":\"string\"},\"query\":{\"type\":\"string\"},\"from_id\":{\"type\":\"string\"},\"to_id\":{\"type\":\"string\"},\"product_id\":{\"type\":\"string\"}},\"required\":[\"action\"],\"additionalProperties\":false}}}";
    private static final Map<String,List<String>> KEYS=new HashMap<>();
    static{KEYS.put("search",Arrays.asList("city","query"));KEYS.put("estimate",Arrays.asList("from_id","to_id"));KEYS.put("prepare",Collections.singletonList("product_id"));KEYS.put("status",Collections.emptyList());KEYS.put("prepare_cancel",Collections.emptyList());}
    private DrTool(){}
    /** Arguments for exactly one action; every value 1..120 characters without controls; null otherwise. */
    static Map<String,Object> arguments(String raw){
        if(raw==null||raw.length()>2000)return null;Map<String,Object> j;try{j=BoundedJson.map(BoundedJson.readDevice(raw.getBytes(StandardCharsets.UTF_8)));}catch(RuntimeException e){return null;}
        List<String> keys=j.get("action") instanceof String?KEYS.get(j.get("action")):null;if(keys==null||j.size()!=keys.size()+1)return null;
        for(String k:keys){Object v=j.get(k);if(!(v instanceof String)||((String)v).isEmpty()||((String)v).length()>120||CeCore.control((String)v))return null;}
        return j;
    }
}
