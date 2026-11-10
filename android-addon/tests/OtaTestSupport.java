package com.turboio.addon;
import java.nio.file.*;

/** Shared test setup: hold the pinned candidate descriptor from repo assets. */
public final class OtaTestSupport {
 public static void holdCandidate(){
  try{OtaCandidate.hold(Files.readAllBytes(Paths.get("assets/otacandidate.json")));}
  catch(Exception e){throw new AssertionError("candidate descriptor: "+e);}
 }
}
