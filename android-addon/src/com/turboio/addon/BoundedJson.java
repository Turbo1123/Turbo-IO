package com.turboio.addon;

import java.nio.*;
import java.nio.charset.*;
import java.util.*;

/** Small strict, bounded JSON profile for SDK documents; never evaluates code. */
public final class BoundedJson {
    private final String s; private int at, nodes;
    private BoundedJson(String s){this.s=s;}
    public static Object read(byte[] bytes){
        if(bytes==null||bytes.length>65536)throw new IllegalArgumentException("JSON budget");
        String s=utf8(bytes);BoundedJson p=new BoundedJson(s);Object value=p.value(0);p.space();
        if(p.at!=s.length())throw new IllegalArgumentException("Trailing JSON");return value;
    }
    public static String utf8(byte[] bytes){try{return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();}catch(CharacterCodingException e){throw new IllegalArgumentException("Invalid UTF-8");}}
    private void space(){while(at<s.length()&&" \r\n\t".indexOf(s.charAt(at))>=0)at++;}
    private char next(){if(at>=s.length())throw new IllegalArgumentException("Incomplete JSON");return s.charAt(at++);}
    private Object value(int depth){
        if(depth>16||++nodes>4096)throw new IllegalArgumentException("JSON complexity");space();char c=next();
        if(c=='"')return string();
        if(c=='{'){Map<String,Object> map=new TreeMap<>();space();if(at<s.length()&&s.charAt(at)=='}'){at++;return map;}
            while(true){space();if(next()!='"')throw new IllegalArgumentException("JSON key");String key=string();if(map.containsKey(key))throw new IllegalArgumentException("Duplicate JSON key");space();if(next()!=':')throw new IllegalArgumentException("JSON colon");map.put(key,value(depth+1));space();c=next();if(c=='}')return map;if(c!=',')throw new IllegalArgumentException("JSON object");}}
        if(c=='['){List<Object> list=new ArrayList<>();space();if(at<s.length()&&s.charAt(at)==']'){at++;return list;}while(true){list.add(value(depth+1));space();c=next();if(c==']')return list;if(c!=',')throw new IllegalArgumentException("JSON array");}}
        if(c=='t'&&literal("rue"))return Boolean.TRUE;if(c=='f'&&literal("alse"))return Boolean.FALSE;if(c=='n'&&literal("ull"))return null;
        if(c=='-'||(c>='0'&&c<='9')){int start=at-1;while(at<s.length()&&"0123456789.eE+-".indexOf(s.charAt(at))>=0)at++;String n=s.substring(start,at);if(!n.matches("-?(0|[1-9][0-9]*)"))throw new IllegalArgumentException("SDK JSON requires integers");try{return Long.valueOf(n);}catch(NumberFormatException e){throw new IllegalArgumentException("Number overflow");}}
        throw new IllegalArgumentException("Invalid JSON value");
    }
    private boolean literal(String tail){if(!s.startsWith(tail,at))return false;at+=tail.length();return true;}
    private String string(){StringBuilder out=new StringBuilder();while(true){char c=next();if(c=='"')break;if(c<32)throw new IllegalArgumentException("JSON control");if(c=='\\'){c=next();switch(c){case '"':case '\\':case '/':break;case 'b':c='\b';break;case 'f':c='\f';break;case 'n':c='\n';break;case 'r':c='\r';break;case 't':c='\t';break;case 'u':int n=0;for(int i=0;i<4;i++){int v=Character.digit(next(),16);if(v<0)throw new IllegalArgumentException("JSON escape");n=n*16+v;}c=(char)n;break;default:throw new IllegalArgumentException("JSON escape");}}out.append(c);}
        String v=out.toString();for(int i=0;i<v.length();i++){char c=v.charAt(i);if(Character.isHighSurrogate(c)){if(++i>=v.length()||!Character.isLowSurrogate(v.charAt(i)))throw new IllegalArgumentException("Surrogate");}else if(Character.isLowSurrogate(c))throw new IllegalArgumentException("Surrogate");}return v;}
    public static byte[] canonical(Object o){StringBuilder b=new StringBuilder();write(o,b);return b.toString().getBytes(StandardCharsets.UTF_8);}
    private static void quote(String s,StringBuilder b){b.append('"');for(int i=0;i<s.length();i++){char c=s.charAt(i);switch(c){case '"':b.append("\\\"");break;case '\\':b.append("\\\\");break;case '\b':b.append("\\b");break;case '\f':b.append("\\f");break;case '\n':b.append("\\n");break;case '\r':b.append("\\r");break;case '\t':b.append("\\t");break;default:if(c<32)b.append(String.format(Locale.ROOT,"\\u%04x",(int)c));else b.append(c);}}b.append('"');}
    private static void write(Object o,StringBuilder b){if(o==null){b.append("null");return;}if(o instanceof String){quote((String)o,b);return;}if(o instanceof Boolean||o instanceof Long||o instanceof Integer){b.append(o);return;}if(o instanceof Map){b.append('{');boolean comma=false;for(String k:new TreeSet<>(map(o).keySet())){if(comma)b.append(',');comma=true;quote(k,b);b.append(':');write(map(o).get(k),b);}b.append('}');return;}if(o instanceof List){b.append('[');boolean comma=false;for(Object v:(List<?>)o){if(comma)b.append(',');comma=true;write(v,b);}b.append(']');return;}throw new IllegalArgumentException("JSON type");}
    @SuppressWarnings("unchecked") public static Map<String,Object> map(Object o){if(!(o instanceof Map))throw new IllegalArgumentException("Expected object");return (Map<String,Object>)o;}
    @SuppressWarnings("unchecked") public static List<Object> list(Object o){if(!(o instanceof List))throw new IllegalArgumentException("Expected list");return (List<Object>)o;}
    public static String text(Object o,int bytes){if(!(o instanceof String))throw new IllegalArgumentException("Expected text");String s=(String)o;if(s.isEmpty()||s.getBytes(StandardCharsets.UTF_8).length>bytes)throw new IllegalArgumentException("Text budget");for(char c:s.toCharArray())if(c<32||(c>=127&&c<=159))throw new IllegalArgumentException("Text control");return s;}
    public static String name(Object o){String s=text(o,24);if(!s.matches("[a-z][a-z0-9_]{0,23}"))throw new IllegalArgumentException("Identifier");return s;}
    public static int number(Object o,int low,int high){if(!(o instanceof Long||o instanceof Integer))throw new IllegalArgumentException("Integer required");long n=((Number)o).longValue();if(n<low||n>high)throw new IllegalArgumentException("Integer range");return (int)n;}
    public static void keys(Map<String,Object> map,String...keys){if(!map.keySet().equals(new HashSet<>(Arrays.asList(keys))))throw new IllegalArgumentException("Unknown or missing fields");}
}
