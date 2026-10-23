package com.turboio.addon;
import java.nio.charset.StandardCharsets;
import java.text.BreakIterator;
import java.util.*;
import java.util.regex.Pattern;

/** Didi display text (iOS RideService Clean/Text and RideStatus.m): bounded card fields, and sandbox prose that is
 * display-only — never interpreted as permission, a terminal state, creation or cancellation. */
final class DrText {
    private static final Pattern URL=Pattern.compile("(?i)https?://[^\\s]+"),LONG_NUMBER=Pattern.compile("(?<![0-9])[0-9]{11,}(?![0-9])");
    private static final String[] PRIVATE={"电话","手机号","订单号","order_id","orderid","token","cookie","authorization","api_key","apikey","?key="};
    private DrText(){}
    private static boolean ctl(int cp){int t=Character.getType(cp);return t==Character.CONTROL||t==Character.FORMAT;}
    /** iOS Clean: controls become spaces, at most max UTF-16 units. */
    static String clean(Object x,int max){
        String s=x instanceof String?(String)x:x instanceof Number?(((Number)x).doubleValue()==Math.rint(((Number)x).doubleValue())&&!(x instanceof java.math.BigDecimal&&((java.math.BigDecimal)x).scale()>0)?String.valueOf(((Number)x).longValue()):x.toString()):"";
        StringBuilder b=new StringBuilder();for(int i=0;i<s.length();){int cp=s.codePointAt(i);i+=Character.charCount(cp);if(ctl(cp))b.append(' ');else b.appendCodePoint(cp);}
        String r=b.toString();return r.length()>max?r.substring(0,max):r;
    }
    private static List<String> chars(String s){List<String> out=new ArrayList<>();BreakIterator it=BreakIterator.getCharacterInstance(Locale.ROOT);it.setText(s);for(int a=it.first(),z=it.next();z!=BreakIterator.DONE;a=z,z=it.next())out.add(s.substring(a,z));return out;}
    /** iOS Text(out,cap,s): Clean(s,150), then drop whole trailing characters until < cap UTF-8 bytes. */
    static String text(Object s,int cap){List<String> c=chars(clean(s,150));StringBuilder b=new StringBuilder();for(String x:c)b.append(x);String v=b.toString();
        while(!c.isEmpty()&&v.getBytes(StandardCharsets.UTF_8).length>=cap){c.remove(c.size()-1);b.setLength(0);for(String x:c)b.append(x);v=b.toString();}return v;}
    static String safeMessage(String input){
        List<String> keep=new ArrayList<>();
        for(String line:input.split("\r\n|[\n\r\u0085  ]",-1)){String lower=line.toLowerCase(Locale.ROOT);boolean priv=false;for(String f:PRIVATE)if(lower.contains(f)){priv=true;break;}if(!priv)keep.add(line);}
        String s=String.join("\n",keep);s=URL.matcher(s).replaceAll("[已隐藏]");s=LONG_NUMBER.matcher(s).replaceAll("[已隐藏]");
        StringBuilder b=new StringBuilder();for(int i=0;i<s.length();){int cp=s.codePointAt(i);i+=Character.charCount(cp);if(cp!='\n'&&ctl(cp))b.append(' ');else b.appendCodePoint(cp);}
        s=b.toString().trim();
        if(s.length()>2000){BreakIterator it=BreakIterator.getCharacterInstance(Locale.ROOT);it.setText(s);int start=it.preceding(2000);s=s.substring(0,start<0?0:start)+"…";}
        return s;
    }
    /** RideStatus DRNormalizeOrder: structured results pass; prose becomes display text only. */
    static Map<String,Object> normalizeOrder(Map<String,Object> r){
        if(r==null)return null;if(r.get("statusCode") instanceof Number)return r;Object t=r.get("serverMessage");
        if(!(t instanceof String)||((String)t).length()>4000)return null;String s=safeMessage((String)t);if(s.isEmpty())return null;
        Map<String,Object> out=new LinkedHashMap<>();out.put("sourceFormat","sandbox-text");out.put("displayText",s);return out;
    }
    /** Two card lines of ≤18 characters; overflow shown with an ellipsis. */
    static String[] messageLines(String text){
        String flat=String.join(" ",text.split("[\\s\u0085  ]",-1));List<String> all=chars(flat),parts=all.subList(0,Math.min(37,all.size()));
        int n=Math.min(parts.size(),36);String a=String.join("",parts.subList(0,Math.min(n,18))),b=n>18?String.join("",parts.subList(18,n)):"";
        if(parts.size()>36)b=String.join("",parts.subList(18,35))+"…";return new String[]{a,b};
    }
}
