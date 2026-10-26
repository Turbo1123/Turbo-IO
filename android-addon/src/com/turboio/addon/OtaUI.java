package com.turboio.addon;
import android.app.*;

final class OtaUI {
 static void show(Activity a){
  // A stale journal from an old TAP1 self-sender run blocks every build (via critical()) and
  // cannot be completed by this TVP2 build; explain the way out before any upgrade screen.
  OtaController.init(a);if(OtaController.busy()){EditorialUI.notice(a,OtaController.staleJournalNote());return;}
  if(OfficialOtaBridge.enabled()){OfficialOtaBridge.show(a);return;}if(OfficialOtaPreparation.enabled()){OfficialOtaPreparation.show(a);return;}
  EditorialUI.notice(a,"TVP2 只走官方升级单次授权（GUARD）构建；旧自发包流程已停用");
 }
}
