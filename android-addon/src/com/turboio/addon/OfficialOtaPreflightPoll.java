package com.turboio.addon;
import java.util.*;
/** Bounded by the bridge's live foreground grant. Never returns a write type. */
final class OfficialOtaPreflightPoll {
 private long idle=-1,version=-1,battery=-1;
 int[] due(boolean armed,boolean foreground,long now,java.util.function.IntPredicate pending){
  if(!armed||!foreground){idle=version=battery=-1;return new int[0];}
  if(now<0)throw new IllegalArgumentException("clock");
  ArrayList<Integer> out=new ArrayList<>();
  if((version<0||now-version>=60000)&&!pending.test(1)){out.add(1);version=now;}
  if((battery<0||now-battery>=60000)&&!pending.test(2)){out.add(2);battery=now;}
  if((idle<0||now-idle>=10000)&&!pending.test(11)){out.add(11);idle=now;}
  int[] result=new int[out.size()];for(int i=0;i<result.length;i++)result[i]=out.get(i);return result;
 }
}
