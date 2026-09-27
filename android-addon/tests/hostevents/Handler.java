package android.os;
public class Handler {public Handler(Looper l){}public void post(Runnable r){r.run();}public void postDelayed(Runnable r,long ms){}public void removeCallbacks(Runnable r){}}
