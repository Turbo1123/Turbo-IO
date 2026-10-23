package com.turboio.addon;
import java.nio.charset.StandardCharsets;import java.util.*;

/** TodoProtocol (port of iOS TodoProtocol/TodoProtocolTests) and ToolTurn (WebSearch.m batch rules, TodoToolFlowTests). */
public final class TodoProtocolTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("todo "+n+" "+why);}
    static Map<String,Object> m(Object...kv){Map<String,Object> r=new LinkedHashMap<>();for(int i=0;i<kv.length;i+=2)r.put((String)kv[i],kv[i+1]);return r;}
    static byte[] packet(int type,String json){byte[] j=json.getBytes(StandardCharsets.UTF_8);java.io.ByteArrayOutputStream o=new java.io.ByteArrayOutputStream();o.write(8);o.write(1);o.write(16);o.write(type);o.write(26);int n=j.length;while(n>=128){o.write((n&127)|128);n>>>=7;}o.write(n);o.write(j,0,j.length);return o.toByteArray();}
    static Map<String,Object> event(Object biz,String device,byte[] payload){return m("message",m("businessId",biz,"deviceId",device,"payload",payload));}
    public static void main(String[] a){
        // Turn gate.
        TodoProtocol.TurnGate g=new TodoProtocol.TurnGate();Map<String,Object> params=m("task","{\"content\":\"合成待办\"}");
        ok(!g.official(),"initially not official");
        ok(!g.observe("task","create_task","create_task",params,"new","old",true)&&!g.official(),"session mismatch");
        ok(!g.observe("task","create_task","create_task",params,"s","s",false)&&!g.observe("chat","chat","",params,"s","s",true)&&!g.official(),"other listener / chat");
        ok(g.observe("task","create_task","create_task",params,"s","s",true)&&g.official(),"official create");
        ok(!g.observe("chat","chat","",params,"s","s",true)&&g.official(),"latched for the turn");g.beginTurn();ok(!g.official(),"new turn clears");
        // Physical status.
        String row="{\"eventType\":1,\"status\":1,\"eventID\":9223372036854775807,\"lastModifiedTime\":1789023014}";
        TodoProtocol.Physical p=TodoProtocol.physical("messageReceived",event("SCHEDULE_TODO","dev:1",packet(4,row)));
        ok(p!=null&&"9223372036854775807".equals(p.wireId)&&p.status==1&&"1789023014".equals(p.rawModifiedTime)&&"dev:1".equals(p.deviceId),"physical");
        ok(TodoProtocol.physical("messageSendSuccess",event("SCHEDULE_TODO","dev",packet(4,row)))==null&&TodoProtocol.physical("messageReceived",event(13L,"dev",packet(4,row)))==null&&TodoProtocol.physical("messageReceived",event("SCHEDULE_TODO","dev",packet(14,row)))==null,"physical shape");
        ok(TodoProtocol.physical("messageReceived",event("SCHEDULE_TODO","dev/x",packet(4,row)))==null,"device identifier");
        for(String id:new String[]{"true","-1","1.5","\"123\"","18446744073709551615"})ok(TodoProtocol.physical("messageReceived",event("SCHEDULE_TODO","dev",packet(4,"{\"eventType\":1,\"status\":1,\"eventID\":"+id+",\"lastModifiedTime\":1}")))==null,"eventID "+id);
        for(String st:new String[]{"true","2","\"1\"","null"})ok(TodoProtocol.physical("messageReceived",event("SCHEDULE_TODO","dev",packet(4,"{\"eventType\":1,\"status\":"+st+",\"eventID\":5,\"lastModifiedTime\":1}")))==null,"status "+st);
        // Envelope.
        byte[] good=packet(6,"{\"total\":0,\"isLastBatch\":true,\"eventList\":[]}");ok(TodoProtocol.envelope(good)!=null,"envelope");
        boolean prefixes=true;for(int i=1;i<good.length;i++)if(TodoProtocol.envelope(Arrays.copyOf(good,i))!=null)prefixes=false;ok(prefixes,"every strict prefix rejected");
        byte[] dup=Arrays.copyOf(good,good.length+2);dup[good.length]=8;dup[good.length+1]=1;ok(TodoProtocol.envelope(dup)==null,"duplicate field");
        ok(TodoProtocol.envelope(new byte[]{8,1,16,4,26,(byte)0xff,(byte)0xff,(byte)0xff,(byte)0xff,(byte)0xff,(byte)0xff,(byte)0xff,(byte)0xff,(byte)0xff,2})==null&&TodoProtocol.envelope(packet(6,"[]"))==null&&TodoProtocol.envelope(new byte[]{8,1,16,11})==null,"overflow / array / no json");
        // Snapshot.
        TodoProtocol.Snapshot s=TodoProtocol.snapshot(packet(6,"{\"total\":2,\"isLastBatch\":false,\"eventList\":[{\"eventType\":1,\"status\":0,\"eventID\":9007199254740993,\"title\":\"x\"}]}"));
        ok(s!=null&&"9007199254740993".equals(s.items.get(0).wireId)&&!s.isLastBatch&&!s.full(),"partial snapshot");
        ok(TodoProtocol.snapshot(packet(6,"{\"total\":2,\"isLastBatch\":true,\"eventList\":[{\"eventType\":1,\"status\":0,\"eventID\":5,\"title\":\"a\"},{\"eventType\":1,\"status\":0,\"eventID\":5,\"title\":\"b\"}]}"))==null,"duplicate ids");
        ok(TodoProtocol.snapshot(packet(6,"{\"total\":0,\"isLastBatch\":true,\"eventList\":[{\"eventType\":1,\"status\":0,\"eventID\":5,\"title\":\"a\"}]}"))==null,"count over total");
        ok(TodoProtocol.snapshot(packet(6,"{\"total\":1,\"isLastBatch\":1,\"eventList\":[]}"))==null&&TodoProtocol.snapshot(packet(4,"{\"total\":0,\"isLastBatch\":true,\"eventList\":[]}"))==null,"real bool / type 6");
        StringBuilder big=new StringBuilder("{\"total\":2000,\"isLastBatch\":true,\"eventList\":[");for(int i=0;i<2000;i++){if(i>0)big.append(',');big.append("{\"eventType\":1,\"status\":0,\"eventID\":").append(i+1).append(",\"title\":\"t").append(i).append("\"}");}big.append("]}");
        TodoProtocol.Snapshot full=TodoProtocol.snapshot(packet(6,big.toString()));ok(full!=null&&full.full()&&full.items.size()==2000,"2000-row list");
        // Create intent.
        ok("合成待办".equals(TodoProtocol.createIntent("task","create_task",m("task",m("content"," 合成待办 ")))),"map task");
        ok("合成待办".equals(TodoProtocol.createIntent("task","create_task","{\"task\":{\"content\":\"合成待办\"}}"))&&"网页桥接测试二号".equals(TodoProtocol.createIntent("task","create_task",m("task","{\"content\":\"网页桥接测试二号\"}"))),"json text layers");
        for(Object t:new Object[]{"not-json","[]","null","{\"content\":123}","{\"content\":\" \"}",42L,null})ok(TodoProtocol.createIntent("task","create_task",m("task",t))==null,"bad task "+t);
        ok(TodoProtocol.createIntent("chat","create_task",params)==null&&TodoProtocol.createIntent("task","delete_task",params)==null,"domain/intent");
        // New candidate.
        TodoProtocol.Item old=new TodoProtocol.Item("7","原有合成待办",0),created=new TodoProtocol.Item("9007199254740993","新增合成待办",0);
        ok(TodoProtocol.newCandidate(TodoProtocol.Snapshot.of(old),TodoProtocol.Snapshot.of(created,old),"新增合成待办")!=null&&TodoProtocol.newCandidate(TodoProtocol.Snapshot.of(),TodoProtocol.Snapshot.of(created),"新增合成待办")!=null,"one new row");
        ok(TodoProtocol.newCandidate(TodoProtocol.Snapshot.of(old),TodoProtocol.Snapshot.of(old),"新增合成待办")==null&&TodoProtocol.newCandidate(TodoProtocol.Snapshot.of(old),TodoProtocol.Snapshot.of(created),"新增合成待办")==null,"no change / removal");
        ok(TodoProtocol.newCandidate(TodoProtocol.Snapshot.of(old),TodoProtocol.Snapshot.of(created,old),"别的")==null,"wrong title");
        ok(TodoProtocol.newCandidate(TodoProtocol.Snapshot.of(old),TodoProtocol.Snapshot.of(created,new TodoProtocol.Item("7","原有合成待办",1)),"新增合成待办")==null,"old row edited");
        ok(TodoProtocol.newCandidate(TodoProtocol.Snapshot.of(new TodoProtocol.Item("7","新增合成待办",0)),TodoProtocol.Snapshot.of(created,new TodoProtocol.Item("7","新增合成待办",0)),"新增合成待办")==null,"title already present");
        ok(TodoProtocol.newCandidate(TodoProtocol.Snapshot.of(old),TodoProtocol.Snapshot.of(created,created,old),"新增合成待办")==null,"duplicate created");
        TodoProtocol.Snapshot partial=TodoProtocol.Snapshot.of(old);partial.isLastBatch=false;ok(TodoProtocol.newCandidate(partial,TodoProtocol.Snapshot.of(created,old),"新增合成待办")==null,"partial before");
        for(String w:new String[]{"09007199254740993","9223372036854775808","１２"})ok(TodoProtocol.newCandidate(TodoProtocol.Snapshot.of(old),TodoProtocol.Snapshot.of(new TodoProtocol.Item(w,"新增合成待办",0),old),"新增合成待办")==null,"wire id "+w);
        // Tool title.
        ok("买牛奶".equals(ToolTurn.title("{\"title\":\"  买牛奶  \"}")),"title trim");
        StringBuilder x241=new StringBuilder("{\"title\":\"");for(int i=0;i<241;i++)x241.append('x');x241.append("\"}");
        for(String bad:new String[]{"{}","[]","{\"title\":1}","{\"title\":\" \"}","{\"title\":\"x\",\"due\":1}","{\"title\":\"a\\nb\"}",x241.toString(),"not json"})ok(ToolTurn.title(bad)==null,"bad title "+bad);
        for(String fmt:new String[]{"\u200b","\u202e","\ufeff"})ok(ToolTurn.title("{\"title\":\"买"+fmt+"牛奶\"}")==null,"format char "+Integer.toHexString(fmt.charAt(0)));
        // ToolTurn batch rules (TodoToolFlowTests).
        ToolTurn t=new ToolTurn(true,true,true,true);ok(t.toolChoice().equals("auto")&&t.validate(Arrays.asList("create_todo"))==null,"single write ok");t.attempt("create_todo");ok(t.toolChoice().equals("none"),"none after a write");
        ok(t.validate(Arrays.asList("create_todo")).equals("待办写入未执行：本轮只允许一次独立创建，搜索后不执行写入。"),"repeat write refused");
        ok(new ToolTurn(true,true,true,true).validate(Arrays.asList("create_todo","create_todo")).startsWith("待办写入未执行"),"batch of two");
        ok(new ToolTurn(true,true,true,true).validate(Arrays.asList("create_todo","web_search")).startsWith("待办写入未执行"),"mixed");
        ToolTurn sw=new ToolTurn(true,true,true,true);ok(sw.validate(Arrays.asList("web_search"))==null,"search ok");sw.attempt("web_search");ok(sw.toolChoice().equals("auto")&&sw.validate(Arrays.asList("create_todo")).startsWith("待办写入未执行"),"no write after a search");
        sw.attempt("web_search");ok(sw.toolChoice().equals("none")&&sw.validate(Arrays.asList("web_search")).equals("未启用搜索或达到本轮工具上限。"),"two searches max");
        ok(new ToolTurn(true,false,true,true).validate(Arrays.asList("create_todo")).startsWith("待办写入未执行"),"no handler, no write");
        ok(new ToolTurn(false,true,true,true).validate(Arrays.asList("web_search")).equals("未启用搜索或达到本轮工具上限。"),"search disabled");
        ToolTurn r=new ToolTurn(true,true,true,true);ok(r.validate(Arrays.asList("didi_ride","web_search")).equals("滴滴沙箱未执行：只允许本轮独立调用一次，不混用私人/公开工具。"),"ride mixed");
        ok(r.validate(Arrays.asList("didi_ride"))==null,"ride alone");r.attempt("didi_ride");ok(r.validate(Arrays.asList("web_search")).equals("本轮滴滴工具已完成，请按真实状态继续操作。")&&r.toolChoice().equals("none"),"after ride");
        ToolTurn k=new ToolTurn(true,true,true,true);ok(k.validate(Arrays.asList("knowledge_query","web_search")).equals("知识库查询未执行：不能混合公开搜索或写入。"),"knowledge mixed");ok(k.validate(Arrays.asList("knowledge_query_status"))==null,"knowledge alone");k.attempt("knowledge_query_status");ok(k.toolChoice().equals("none"),"none after knowledge");
        ok(ToolTurn.result("created").equals("{\"glasses_verified\":false,\"retry_allowed\":false,\"status\":\"created\"}")&&ToolTurn.result("weird").contains("\"status\":\"unknown\""),"sanitized result");
        ok(ToolTurn.MAX_ROUNDS==3,"3 rounds");
        System.out.println("TodoProtocolTest: "+n+" checks; turn gate, physical, envelope, snapshot, create intent, new candidate, tool title, batch rules");
    }
}
