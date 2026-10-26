package com.turboio.addon;
import java.nio.file.*;
import java.util.*;

/** Candidate descriptor contract: parse the pinned TAP1 descriptor, fail-closed
 * behavior when unset, and structural rejection of tampered descriptors. */
public final class OfficialOtaCandidateTest {
 static int n;static void ok(boolean v){n++;if(!v)throw new AssertionError("check "+n);}
 interface Work{void run() throws Exception;}
 static void rejects(Work w){n++;try{w.run();}catch(Exception expected){return;}throw new AssertionError("expected rejection "+n);}
 public static void main(String[] args)throws Exception{
  byte[] json=Files.readAllBytes(Paths.get("assets/otacandidate.json"));
  OtaCandidate c=OtaCandidate.parse(json);
  ok("TAP1-TEST-01".equals(c.codeName));
  ok("TAP1-TEST-01".equals(c.confirmToken));
  ok("Strix OS 1.0.4.12".equals(c.baseVersion));
  ok(c.zipSize==9320672&&c.otaSize==9320672);
  ok(c.apSize==9590856);
  ok(c.apBudgetBytes==9600000);
  ok(c.manifestSize==2515);
  ok(c.pins.size()==15);
  ok(c.pins.get("nuttx_ap.bin").size==9590856);
  ok(c.pins.get("nuttx_ap.bin").sha256.equals("65e0a5312361ec785eb9ab1659badf182765f4054d4d95fef4c61ceb49dfa4b4"));
  ok(c.restore!=null&&c.restore.apSize==9466560&&"9156b9419c3557e9bd72dc61692d0b4b".equals(c.restore.apMd5));
  OtaCandidate.drop();rejects(()->OtaCandidate.require());
  OtaCandidate.hold(json);ok(OtaCandidate.require().codeName.equals(c.codeName)&&OtaCandidate.require().pins.size()==c.pins.size());
  OtaCandidate.drop();rejects(()->OtaCandidate.hold(null));
  rejects(()->OtaCandidate.hold("{}".getBytes("UTF-8")));
  Map<String,Object> doc1=BoundedJson.map(BoundedJson.read(json));
  doc1.remove("otaSize");rejects(()->OtaCandidate.parse(BoundedJson.canonical(doc1)));
  Map<String,Object> doc2=BoundedJson.map(BoundedJson.read(json));
  BoundedJson.map(doc2.get("zip")).put("sha256",((String)BoundedJson.map(doc2.get("zip")).get("sha256")).toUpperCase(Locale.ROOT));
  rejects(()->OtaCandidate.parse(BoundedJson.canonical(doc2)));
  Map<String,Object> doc3=BoundedJson.map(BoundedJson.read(json));
  BoundedJson.map(doc3.get("ap")).put("name","evil/path.bin");
  rejects(()->OtaCandidate.parse(BoundedJson.canonical(doc3)));
  Map<String,Object> doc4=BoundedJson.map(BoundedJson.read(json));
  List<Object> pins=BoundedJson.list(doc4.get("payloadPins"));
  Iterator<Object> it=pins.iterator();while(it.hasNext()){Map<String,Object> row=BoundedJson.map(it.next());if("nuttx_ap.bin".equals(row.get("name")))it.remove();}
  rejects(()->OtaCandidate.parse(BoundedJson.canonical(doc4)));
  OtaCandidate.hold(json);
  System.out.println("official ota candidate descriptor checks passed: "+n);
 }
}
