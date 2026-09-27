package com.turboio.addon;
import java.nio.file.*;import java.io.*;import java.util.zip.*;
public final class OfficialOtaDirectoryTest {
 static int n;interface Work{void run()throws Exception;}static void bad(Work w)throws Exception{try{w.run();throw new AssertionError("accepted invalid directory");}catch(IOException expected){n++;}}
 public static void main(String[] args)throws Exception{
  Path root=Files.createTempDirectory("turboio-ota-directory-");
  try{
   try(ZipInputStream z=new ZipInputStream(Files.newInputStream(Paths.get(args[0])))){ZipEntry e;while((e=z.getNextEntry())!=null){if(!e.getName().matches("[A-Za-z0-9_.]+"))throw new IOException();Files.copy(z,root.resolve(e.getName()));}}
   OtaPackage.verifyDirectory(root);n++;
   Path extra=root.resolve("unexpected");Files.write(extra,new byte[0]);bad(()->OtaPackage.verifyDirectory(root));Files.delete(extra);
   Path file=root.resolve("nuttx_ap.bin"),saved=root.resolveSibling(root.getFileName()+"-saved-ap");Files.move(file,saved);
   try{bad(()->OtaPackage.verifyDirectory(root));Files.createSymbolicLink(file,saved);bad(()->OtaPackage.verifyDirectory(root));Files.delete(file);}finally{Files.move(saved,file);}
   Path small=root.resolve("ota_installer_progress.bin");byte[] original=Files.readAllBytes(small),changed=original.clone();changed[0]^=1;
   Files.write(small,changed);bad(()->OtaPackage.verifyDirectory(root));Files.write(small,original);OtaPackage.verifyDirectory(root);n++;
  }finally{try(DirectoryStream<Path> list=Files.newDirectoryStream(root)){for(Path p:list)Files.delete(p);}Files.delete(root);}
  System.out.println("Official prepared directory: "+n+" checks, read-only production verifier");
 }
}
