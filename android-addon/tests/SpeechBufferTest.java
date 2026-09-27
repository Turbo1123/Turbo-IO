package com.turboio.addon;
import java.util.*;
public class SpeechBufferTest {
 static int n;static void check(boolean b){n++;if(!b)throw new AssertionError(n);}
 public static void main(String[] args){SpeechBuffer s=new SpeechBuffer();
 check(s.append("你好",false,false).isEmpty());check(s.append("。",false,false).equals(Arrays.asList("你好。")));
 check(s.append("后半段",false,true).equals(Arrays.asList("后半段")));check(s.append("重复",false,true).isEmpty());s.reset();
 check(s.append("第一句。",true,false).size()==1);check(s.append("第一句。第二句。",true,true).equals(Arrays.asList("第二句。")));
 s.reset();StringBuilder x=new StringBuilder();for(int i=0;i<500;i++)x.append("中");List<String> a=s.append(x.toString(),false,true);check(a.size()==3);check(String.join("",a).equals(x.toString()));
 s.reset();x=new StringBuilder();for(int i=0;i<179;i++)x.append("a");x.append("😀尾");a=s.append(x.toString(),false,true);check(a.get(0).length()==179);check(a.get(1).equals("😀尾"));
 s.reset();check(s.append("  \n\t",false,true).isEmpty());s.reset();s.append("prefix",true,false);try{s.append("rewrite",true,true);throw new AssertionError();}catch(IllegalArgumentException ok){n++;}
 s.reset();char[] huge=new char[12001];Arrays.fill(huge,'a');try{s.append(new String(huge),false,true);throw new AssertionError();}catch(IllegalArgumentException ok){n++;}
 s.reset();check(s.append("3.14 is pi. Next",false,true).equals(Arrays.asList("3.14 is pi.","Next")));
 System.out.println("SpeechBuffer: "+n+" checks");}
}
