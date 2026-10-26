package com.turboio.addon;

/** Display lab page policy: when the session may run, and what a refused query tells the user. */
public final class DisplayCopyTest {
    static int n;static void ok(boolean b,String why){n++;if(!b)throw new AssertionError("copy "+n+" "+why);}
    public static void main(String[] a){
        ok(DisplayCopy.foreground(true,true,false),"visible, resumed, uncovered");
        ok(!DisplayCopy.foreground(true,true,true),"covered by the N8W page");
        ok(!DisplayCopy.foreground(true,false,false)&&!DisplayCopy.foreground(false,true,false),"paused or closed");
        ok(DisplayCopy.refused("查询未提交","执行结果未确认；保留文件，60秒内不重发，请重新查询").contains("60秒"),"refusal carries the lane quarantine");
        ok(DisplayCopy.refused(null,"").startsWith("未发送"),"default refusal");
        ok(DisplayCopy.picked(true).contains("重新查询")&&!DisplayCopy.picked(false).contains("重新查询"),"picking says a re-query is needed only if a session was live");
        System.out.println("DisplayCopyTest: "+n+" checks");
    }
}
