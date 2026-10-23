package com.turboio.addon;
import java.util.*;

/** Per-turn model tool rules (port of iOS WebSearch.m TIOWebChatRequest): at most 3 rounds, no parallel calls, the
 * whole batch validated before any effect, no write after untrusted search results, tool_choice none once a private
 * tool ran, and the sanitized create_todo result. Pure. */
final class ToolTurn {
    static final int MAX_ROUNDS=3;
    static final String WRITE_REFUSED="待办写入未执行：本轮只允许一次独立创建，搜索后不执行写入。",SEARCH_REFUSED="未启用搜索或达到本轮工具上限。";
    private final boolean search,todo,ride,knowledge;
    private int searches;private boolean todoAttempted,rideAttempted,knowledgeAttempted;
    ToolTurn(boolean searchEnabled,boolean todoHandler,boolean rideEnabled,boolean knowledgeEnabled){search=searchEnabled;todo=todoHandler;ride=rideEnabled;knowledge=knowledgeEnabled;}
    String toolChoice(){return rideAttempted||todoAttempted||knowledgeAttempted||searches>=2?"none":"auto";}
    boolean todoAttempted(){return todoAttempted;}
    /** null when the batch may run; otherwise the iOS finish text (nothing in the batch runs). */
    String validate(List<String> names){
        int rides=0,writes=0,searchCalls=0,knowledgeCalls=0,calls=names.size();
        for(String n:names){if("didi_ride".equals(n))rides++;else if("create_todo".equals(n))writes++;else if(n!=null&&n.startsWith("knowledge_query"))knowledgeCalls++;else searchCalls++;}
        if(rides>0&&(calls!=1||rideAttempted||todoAttempted||knowledgeAttempted||searches>0||!ride))return "滴滴沙箱未执行：只允许本轮独立调用一次，不混用私人/公开工具。";
        if(rideAttempted&&calls>0)return "本轮滴滴工具已完成，请按真实状态继续操作。";
        if(knowledgeCalls>0&&(knowledgeCalls!=1||calls!=1||knowledgeAttempted||searches>0||todoAttempted||!knowledge))return "知识库查询未执行：不能混合公开搜索或写入。";
        if(writes>0&&(writes!=1||calls!=1||todoAttempted||knowledgeAttempted||searches>0||!todo))return WRITE_REFUSED;
        if(searchCalls>0&&(!search||searchCalls+searches>2||todoAttempted||knowledgeAttempted))return SEARCH_REFUSED;
        return null;
    }
    void attempt(String name){if("didi_ride".equals(name))rideAttempted=true;else if("create_todo".equals(name))todoAttempted=true;else if(name!=null&&name.startsWith("knowledge_query"))knowledgeAttempted=true;else searches++;}
    /** TIOTodoToolTitle: exactly {"title": String}, ≤240 chars, no control characters, non-blank after trimming. */
    static String title(String arguments){
        try{
            if(arguments==null||arguments.length()>4000)return null;Object o=BoundedJson.readDevice(arguments.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            if(!(o instanceof Map)||((Map<?,?>)o).size()!=1)return null;Object t=((Map<?,?>)o).get("title");if(!(t instanceof String))return null;String s=(String)t;
            if(s.length()>240)return null;for(int i=0;i<s.length();i++)if(Character.isISOControl(s.charAt(i))||Character.getType(s.charAt(i))==Character.CONTROL)return null;
            s=TodoProtocol.trim(s);return s.isEmpty()?null:s;
        }catch(RuntimeException e){return null;}
    }
    /** The only data returned to the model: no ids, titles or list contents. */
    static String result(String status){
        String s=Arrays.asList("created","not_ready","rejected","unknown").contains(status)?status:"unknown";
        Map<String,Object> m=new LinkedHashMap<>();m.put("status",s);m.put("glasses_verified",false);m.put("retry_allowed",false);
        return new String(BoundedJson.canonical(m),java.nio.charset.StandardCharsets.UTF_8);
    }
}
