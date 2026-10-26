package com.turboio.addon;

/** Display lab page policy (pure): when the TDP1 session may send and renew, and the texts for refusals. */
final class DisplayCopy {
    private DisplayCopy(){}
    /** iOS viewWillDisappear/resume: only while this page is showing, the host Activity is resumed and no page covers it. */
    static boolean foreground(boolean showing,boolean resumed,boolean covered){return showing&&resumed&&!covered;}
    /** A refused query or command names the shared lane state too (an unanswered packet holds the lane for 60 s). */
    static String refused(String state,String lane){
        String base=state!=null&&!state.isEmpty()?state:"未发送：请先连接并进入眼镜 Turbo Display 页面，再查询 SID。";
        return lane!=null&&!lane.isEmpty()&&!lane.equals(base)?base+"\n共享通道："+lane:base;
    }
    /** The system picker pauses the page, which ends a live session. */
    static String picked(boolean hadSession){return hadSession?"已本机缩图，没有发送。选图期间显示会话已暂停，请重新查询 SID 后再发送。":"已本机缩图，没有发送。";}
}
