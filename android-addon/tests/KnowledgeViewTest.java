package com.turboio.addon;
import java.util.*;

/** Knowledge page texts and rules (iOS KnowledgeUI.m / KnowledgeClient.m). */
public final class KnowledgeViewTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("knowledge view "+n+" "+why);}
    static Map<String,Object> m(Object...kv){Map<String,Object> r=new LinkedHashMap<>();for(int i=0;i<kv.length;i+=2)r.put((String)kv[i],kv[i+1]);return r;}
    public static void main(String[] a){
        ok(KnowledgeView.AGENTS.equals(Arrays.asList("Codex","Claude Code","Hermes","WorkBuddy","OpenClaw")),"agents");
        String url="https://mac.example/api/turbo-knowledge";
        ok(KnowledgeView.gate(true,"Codex",url,"tok")&&!KnowledgeView.gate(true,"Hermes",url,"tok")&&!KnowledgeView.gate(false,"Codex",url,"tok")&&!KnowledgeView.gate(true,"Codex","https://mac.example/other","tok")&&!KnowledgeView.gate(true,"Codex",url,""),"gate");
        ok(!KnowledgeView.terminal("running",0,79000)&&KnowledgeView.terminal("running",0,80001)&&KnowledgeView.terminal("completed",0,1)&&KnowledgeView.terminal("failed",0,1)&&KnowledgeView.terminal("interrupted",0,1)&&!KnowledgeView.terminal("queued",0,1),"terminal");
        ok(KnowledgeView.source(m("name","微信","available",true,"count",12L,"updatedAt","2026-10-23","scope","最近 30 天","partial",true)).equals("可读取 · 12 条\n更新时间：2026-10-23\n最近 30 天\n存在范围限制或跳过文件"),"source row");
        ok(KnowledgeView.source(m("name","项目","available",false)).equals("不可用 · 0 条\n更新时间：未知\n"),"source fallbacks");
        ok(KnowledgeView.job(m("status","completed","answer","进展如下")).equals("completed\n进展如下")&&KnowledgeView.job(m("status","failed","error","超时")).equals("failed\n超时")&&KnowledgeView.job(null).equals("尚无查询\n"),"job row");
        ok(KnowledgeView.citation(m("title","周报","sourceLabel","微信","messageAt",null,"updatedAt","10-22","excerpt","要点")).equals("微信 · 10-22\n要点")&&KnowledgeView.citation(m("title","t","sourceLabel","p","messageAt","10-21","updatedAt","10-22","excerpt","e")).equals("p · 10-21\ne"),"citation row");
        ok(KnowledgeView.validJob("0f8fad5b-d9cb-469f-a165-70867728950e")&&!KnowledgeView.validJob("not-a-uuid")&&!KnowledgeView.validJob("../x")&&!KnowledgeView.validJob(null),"job id");
        ok(KnowledgeView.validQuery("项目进展")&&!KnowledgeView.validQuery("a")&&!KnowledgeView.validQuery(new String(new char[201]).replace('\0','x')),"query length");
        System.out.println("KnowledgeViewTest: "+n+" checks; agents, gate, poll, rows");
    }
}
