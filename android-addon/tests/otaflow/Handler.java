package android.os;import java.util.*;public final class Handler {
 private static final Queue<Runnable> q=new java.util.concurrent.ConcurrentLinkedQueue<>();
 public Handler(Looper l){}public boolean post(Runnable r){q.add(r);return true;}public void postDelayed(Runnable r,long ms){}public void removeCallbacks(Runnable r){}
 public static void drain(){int n=0;Runnable r;while((r=q.poll())!=null){if(++n>500)throw new AssertionError("runaway main queue");r.run();}}
}
