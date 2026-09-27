package com.turboio.addon;
import java.util.*;
public final class OfficialOtaPreflightPollTest {
 static int checks;
 static void eq(int[] got,int...expected){checks++;if(!Arrays.equals(got,expected))throw new AssertionError(Arrays.toString(got));}
 public static void main(String[] args){
  OfficialOtaPreflightPoll p=new OfficialOtaPreflightPoll();
  eq(p.due(false,true,0,t->false));eq(p.due(true,false,1,t->false));
  eq(p.due(true,true,2,t->false),1,2,11);eq(p.due(true,true,10001,t->false));
  eq(p.due(true,true,10002,t->false),11);eq(p.due(true,true,20002,t->true));
  eq(p.due(true,true,20003,t->false),11);eq(p.due(true,true,60002,t->false),1,2,11);
  eq(p.due(false,true,60003,t->false)); // transfer/unknown/locked stops all polling
  eq(p.due(false,true,120003,t->false));
  eq(p.due(true,true,120004,t->false),1,2,11);eq(p.due(true,false,120005,t->false));
  for(long now=0;now<900000;now+=1000)for(int type:p.due(true,true,now,t->false)){
   checks++;if(type!=1&&type!=2&&type!=11)throw new AssertionError("write query");
  }
  System.out.println("Official OTA armed read-only polling: "+checks+" checks; no write commands");
 }
}
