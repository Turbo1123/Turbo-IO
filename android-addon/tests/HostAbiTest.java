package com.turboio.addon;

/** Run once per host: java -Dturboio.host=<1.0.6|1.0.7> HostAbiTest <message> <send> <file> */
public final class HostAbiTest {
    public static void main(String[] a){
        HostAbi abi=HostAbi.get();
        String got=HostAbi.message()+" "+HostAbi.send()+" "+HostAbi.file()+" "+HostAbi.manager()+" "+HostAbi.business()+" "+HostAbi.core();
        String want=a[0]+" "+a[1]+" "+a[2]+" "+a[3]+" "+a[4]+" "+a[5];
        if(!got.equals(want))throw new AssertionError("host "+abi.version+": "+got+" != "+want);
        System.out.println("HostAbiTest "+abi.version+": "+got);
    }
}
