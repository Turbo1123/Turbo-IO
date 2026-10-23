package android.os;
import java.util.*;
/** Runs posted work only when the test drains; delayed work is dropped (the test ticks explicitly). */
public class Handler {
 private static final Queue<Runnable> q=new ArrayDeque<>();
 public Handler(Looper l){}
 public final boolean post(Runnable r){q.add(r);return true;}
 public final boolean postDelayed(Runnable r,long ms){return true;}
 public final void removeCallbacks(Runnable r){}
 public static void drain(){Runnable r;int n=0;while((r=q.poll())!=null){if(++n>500)throw new AssertionError("runaway");r.run();}}
}
