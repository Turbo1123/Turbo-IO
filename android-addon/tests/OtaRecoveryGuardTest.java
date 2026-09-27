package com.turboio.addon;

public final class OtaRecoveryGuardTest {
 static int n;
 static void ok(boolean value){n++;if(!value)throw new AssertionError("guard check "+n);}
 public static void main(String[] args){
  OtaRecoveryGuard g=new OtaRecoveryGuard("eye",100,false);
  g.observe("eye",100);ok(!g.allowed("eye",60099));ok(!g.allowed("eye",120100)); // time alone never unlocks
  ok(!g.confirmHome("wrong","eye",120100));
  g.observe(null,120101);g.observe("eye",120102);ok(!g.allowed("eye",123102)); // failed SDK read not disconnect
  g.observe("other",123103);g.observe("eye",123104);ok(!g.allowed("eye",126104));
  g.observe("",126105);g.observe("eye",126106);ok(!g.allowed("eye",129106)); // one empty sample insufficient
  g.observe("",129107);g.observe("",130107);g.observe("eye",130108);ok(!g.allowed("eye",132107));ok(g.allowed("eye",132108));
  g.observe(null,132109);g.observe("eye",132110);ok(!g.allowed("eye",136109)); // uncertain connection revokes evidence
  ok(g.confirmHome("已回首页","eye",136110));ok(g.allowed("eye",136110));ok(!g.allowed("eye",256111)); // manual approval expires
  OtaRecoveryGuard quiet=new OtaRecoveryGuard("eye",0,false);
  quiet.observe("",0);quiet.observe("",1000);quiet.observe("eye",1001);ok(!quiet.allowed("eye",59999));ok(quiet.allowed("eye",60000));
  OtaRecoveryGuard lost=new OtaRecoveryGuard("eye",0,true);
  lost.observe("",0);lost.observe("",1000);lost.observe("eye",1001);ok(!lost.allowed("eye",119999)); // process lost means explicit confirmation
  ok(!lost.confirmHome("已回首页","eye",119999));ok(lost.confirmHome("已回首页","eye",120000));ok(lost.allowed("eye",120000));
  lost.observe("other",120001);ok(!lost.allowed("eye",125000));ok(!lost.confirmHome("已回首页",null,125001));
  OtaRecoveryGuard fresh=new OtaRecoveryGuard("eye",999999,true);fresh.observe("eye",999999);ok(!fresh.allowed("eye",1120000));
  ok(!fresh.confirmHome("已回首页","eye",999998)); // backwards clock cannot grant
  System.out.println("OTA recovery guard: "+n+" checks; no timer-only unlock.");
 }
}
