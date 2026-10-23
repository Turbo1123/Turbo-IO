package com.turboio.addon;
import java.net.URI;
import java.util.*;

/** Knowledge page rules and texts (iOS KnowledgeUI.m / KnowledgeClient.m). Pure. */
final class KnowledgeView {
    static final List<String> AGENTS=Collections.unmodifiableList(Arrays.asList("Codex","Claude Code","Hermes","WorkBuddy","OpenClaw"));
    private KnowledgeView(){}
    /** Private HTTPS gateway at exactly /api/turbo-knowledge, no user/query/fragment. */
    static boolean validEndpoint(String endpoint){try{URI u=new URI(endpoint);return "https".equals(u.getScheme())&&u.getHost()!=null&&u.getUserInfo()==null&&u.getQuery()==null&&u.getFragment()==null&&"/api/turbo-knowledge".equals(u.getPath());}catch(Exception e){return false;}}
    /** TIOKnowledgeEnabled: switch on, Codex selected (the only wired executor), endpoint and token configured. */
    static boolean gate(boolean enabled,String agent,String endpoint,String token){return enabled&&"Codex".equals(agent)&&validEndpoint(endpoint)&&token!=null&&!token.isEmpty();}
    /** Poll stops on a final state or 80 s after the query started. */
    static boolean terminal(String status,long startedMs,long nowMs){return "completed".equals(status)||"failed".equals(status)||"interrupted".equals(status)||nowMs-startedMs>80000;}
    static boolean validJob(String id){if(id==null)return false;try{return UUID.fromString(id).toString().equals(id.toLowerCase(Locale.ROOT));}catch(IllegalArgumentException e){return false;}}
    static boolean validQuery(String q){return q!=null&&q.length()>=2&&q.length()<=200;}
    private static String str(Object o,String fallback){return o==null?fallback:String.valueOf(o);}
    static String source(Map<?,?> s){
        return (Boolean.TRUE.equals(s.get("available"))?"可读取":"不可用")+" · "+str(s.get("count"),"0")+" 条\n更新时间："+str(s.get("updatedAt"),"未知")+"\n"+str(s.get("scope"),"")+(Boolean.TRUE.equals(s.get("partial"))?"\n存在范围限制或跳过文件":"");
    }
    static String job(Map<?,?> j){if(j==null)return "尚无查询\n";Object detail=j.get("answer")!=null?j.get("answer"):j.get("error");return str(j.get("status"),"尚无查询")+"\n"+str(detail,"");}
    static String citation(Map<?,?> e){Object at=e.get("messageAt")!=null?e.get("messageAt"):e.get("updatedAt");return str(e.get("sourceLabel"),"")+" · "+str(at,"")+"\n"+str(e.get("excerpt"),"");}
}
