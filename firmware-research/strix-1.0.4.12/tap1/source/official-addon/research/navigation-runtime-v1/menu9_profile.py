"""Pinned nine-slot profile, separate from the shipped eight-slot source."""
import struct
import menu8_native_profile as old
WRAPPERS=old.WRAPPERS+[('vm_event',0x107a1dd0,4)]
REPLACEMENTS=old.REPLACEMENTS+[('render_slide',0x10799d6e,4)]
PATCHES=[
 (0x1079a2b8,'f1ee087a','f2ee007a','wheel target maximum 6.0 -> 8.0'),
 (0x107992f0,'efeece40',struct.pack('<f',8.4666667).hex(),'follow target upper bound 6.4667 -> 8.4667'),
 (0x10799328,'efeece40',struct.pack('<f',8.4666667).hex(),'spring position upper bound 6.4667 -> 8.4667'),
]
ALIASES={**old.ALIASES,
 'nav_label_static':'lv_label_set_text_static','nav_always_on':'lv_rayneo_display_screen_always_on',
 'nav_release_always_on':'lv_rayneo_display_screen_release_always_on','nav_screen_on':'lv_rayneo_display_screen_on',
 'nav_force_off':'lv_rayneo_display_force_screen_off',
 'nav_ensure_menu':'rayneo::app::launcher::ViewManager::ensureAppListView',
 'nav_set_state':'rayneo::app::launcher::ViewManager::setState',
 'nav_top_app':'rayneo::service::launcher::LauncherAPI::getCurrentTopAppPkg',
 'nav_monitors':'rayneo::service::launcher::MonitorManager::getInstance',
 'nav_link':'rayneo::service::launcher::MonitorManager::getLinkMonitor',
 'nav_input':'rayneo::service::launcher::MonitorManager::getInputEventMonitor',
 'nav_bonded':'rayneo::service::launcher::LinkMonitor::isBond',
 'nav_folded':'rayneo::service::launcher::InputEventMonitor::isHallFold',
 'nav_business_idle':'rayneo::service::launcher::LauncherAPI::isBussinessIdle',
 'nav_connection':'get_conn_state','nav_stop_event':'lv_event_stop_processing'}
