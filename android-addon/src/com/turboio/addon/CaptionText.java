package com.turboio.addon;
import java.util.*;
/** Provider event reducer. Source and translated text never share identity. */
final class CaptionText {
 static final class Update{final String channel,id,text;final boolean end;Update(String c,String i,String t,boolean e){channel=c;id=i;text=t;end=e;}}
 private final Map<String,String> lines=new LinkedHashMap<>();private final Set<String> finished=new HashSet<>(),seen=new LinkedHashSet<>();
 Update accept(String type,String event,String id,String text,int index){String channel;boolean end;if(type.equals("conversation.item.input_audio_transcription.delta")){channel="source";end=false;}else if(type.equals("conversation.item.input_audio_transcription.completed")){channel="source";end=true;}else if(type.equals("response.text.delta")){channel="translation";end=false;}else if(type.equals("response.text.done")){channel="translation";end=true;}else return null;
  if(id==null||id.isEmpty()||id.length()>256||text==null||text.length()>16384||index!=0||event!=null&&event.length()>256)throw new IllegalArgumentException("event bounds");if(event!=null&&!event.isEmpty()){if(!seen.add(event))return null;if(seen.size()>256)seen.remove(seen.iterator().next());}String k=channel+":"+id;if(finished.contains(k))return null;if(!lines.containsKey(k)&&lines.size()>=64){String first=lines.keySet().iterator().next();if(!finished.remove(first))throw new IllegalArgumentException("unfinished backlog");lines.remove(first);}String value=end?text:lines.getOrDefault(k,"")+text;if(value.getBytes(java.nio.charset.StandardCharsets.UTF_8).length>16384)throw new IllegalArgumentException("text limit");lines.put(k,value);if(end)finished.add(k);return new Update(channel,id,value,end);
 }
}
