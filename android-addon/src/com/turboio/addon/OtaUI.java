package com.turboio.addon;
import android.app.*;import android.os.*;import android.widget.*;import android.view.WindowManager;

final class OtaUI {
 static void show(Activity a){if(OfficialOtaBridge.enabled()){OfficialOtaBridge.show(a);return;}if(OfficialOtaPreparation.enabled()){OfficialOtaPreparation.show(a);return;}OtaController.init(a);EditorialUI.Screen s=new EditorialUI.Screen(a,"实验固件 · 默认锁定");s.dialog.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);LinearLayout b=s.body;
  b.addView(EditorialUI.text(a,"OTA-02 · 安装期保护版 · 仅供开发者受控验收\n安卓真机刷写尚未验证。仅支持指定 TAP1 / Strix OS 1.0.4.12 原样包；不接受未知固件、不改原厂缓存。刷写存在不可恢复故障风险，原厂回滚不是免风险保证。",15,EditorialUI.INK));
  TextView status=EditorialUI.text(a,"",14,EditorialUI.LIME);b.addView(status);
  EditorialUI.button(a,b,"1 · 导入指定 TAP1 ZIP（本机校验）",false,()->{if(OtaController.busy()){EditorialUI.notice(a,"准备或升级尚未结束，不能替换候选包");return;}DocumentPicker.pick(a,OtaPackage.ZIP_SIZE,OtaController::importPackage);});
  EditorialUI.button(a,b,"2 · 开启 15 分钟准备并只读预检",false,()->EditorialUI.confirm(a,"只读预检，不开始刷写","先关闭官方自动升级，确保无录音、导航、音乐、阅读、提词或对话。眼镜须为 1.0.4.12 且电量 ≥50%。将读取版本、电量、空间和空闲状态；这是本机准备，不是官方页面下载。",OtaController::prepare));
  EditorialUI.button(a,b,"3 · 允许一次 TAP1 实验升级",false,()->{EditText input=new EditText(a);input.setSingleLine(true);input.setHint("输入 TAP1");new AlertDialog.Builder(a).setTitle("单次授权，不自动开始").setMessage("已了解实验风险；保持手机与眼镜供电和蓝牙，不强退。只授权刚校验的指定包。输入 TAP1。").setView(input).setNegativeButton("取消",null).setPositiveButton("授权",(d,w)->OtaController.authorize(input.getText().toString().trim())).show();});
  EditorialUI.button(a,b,"4 · 开始一次升级",true,()->EditorialUI.confirm(a,"确认向眼镜开始升级？","只有授权=1且实时预检通过时才能开始。首次点击会准备独立前台服务，提示就绪后再次确认。此后不能当作普通任务取消；不会自动重试。",OtaController::start));
  EditorialUI.button(a,b,"关闭准备 / 撤销未使用授权",false,OtaController::cancelPreparation);
  EditorialUI.button(a,b,"5 · 眼镜重启后，只读回查状态",false,OtaController::readback);
  b.addView(EditorialUI.text(a,"安装开始后至少保护 60 秒，并等待有效断开/同一眼镜稳定重连；只开放手动回查，不自动发送。App 重启、结果未知或漏掉重连时保持锁定。计时结束不代表安装完成。",13,EditorialUI.MUTED));
  EditorialUI.button(a,b,"恢复辅助 · 已自然重启回首页",false,()->{EditText input=new EditText(a);input.setSingleLine(true);input.setHint("输入：已回首页");new AlertDialog.Builder(a).setTitle("仅用于连接历史不完整").setMessage("只有亲眼确认本次升级已结束、眼镜已自然重启回到可操作首页，才输入“已回首页”。至少等待保护页计时 120 秒且同一眼镜稳定连接；这只是最短等待，不保证安装完成。\n若仍在更新、黑屏或情况不明，请继续等待，不要断电、解绑或强行重启。此操作不解锁、不发送；之后仍须回查和最终检查。").setView(input).setNegativeButton("继续等待",null).setPositiveButton("记录人工确认",(d,w)->OtaController.confirmRecoveryHome(input.getText().toString().trim())).show();});
  EditorialUI.button(a,b,"6 · 已人工检查镜片，解除结果保护",false,()->EditorialUI.confirm(a,"已检查同一副眼镜？","请确认眼镜已回首页、功能正常并核对新功能。版本号相同不能证明 AP 哈希。本操作只解除保护，不重试或宣称自动刷写成功。",OtaController::releaseAfterInspection));
  EditorialUI.button(a,b,"查看本机脱敏诊断",false,()->EditorialUI.notice(a,OtaController.diagnostic()));
  b.addView(EditorialUI.text(a,"通过原厂 MARS_FOTA / business9 的文件模式传输，由眼镜索取分片；不把 ZIP 直接发送给眼镜。只修改 application 的既有候选，另外 13 个负载保持原样。传完≠安装成功。\n不要同时进入官方更新页点击更新。",13,EditorialUI.MUTED));
  Handler h=new Handler(Looper.getMainLooper());Runnable tick=new Runnable(){public void run(){if(!s.dialog.isShowing())return;status.setText(OtaController.status());h.postDelayed(this,500);}};h.post(tick);s.dialog.setOnDismissListener(d->{h.removeCallbacks(tick);if(!OtaController.critical())OtaController.cancelPreparation();});
 }
}
