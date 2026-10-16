#import <UIKit/UIKit.h>
UIViewController *TIONavigationController(void);
// Voice entry: passive NLP keyword observer ("导航到X/导航去X/带我去X").
// Runs fully headless -- no page is opened; the glasses HUD appearing is the
// success feedback. Opt-out preference key: voiceNavDisabled (default: on).
BOOL TIOVoiceNavMaybeStart(NSString *text); // YES = a NEW voice navigation dispatched.
void TIOVoiceNavStop(void);
// Breadcrumb diagnostics for the headless voice pipeline (shown in 适配与回调).
void TIOVoiceNavTrace(NSString *step);
void TIOVoiceNavTraceReset(void);
NSString *TIOVoiceNavTraceStatus(void);
// Multi-turn voice destination choice: when a search yields several local
// candidates they are streamed into the hijacked assistant chat window (the
// "聊天框") and the panel waits for "第几个" (30s, then defaults to the first).
NSUInteger TIOVoiceNavPendingChoices(void); // 0 = nothing awaiting a choice
BOOL TIOVoiceNavChoose(NSUInteger oneBasedIndex); // YES = consumed a live pending choice
void TIOVoiceNavReject(void); // 用户说「都不对」：清空候选并提示重说（不启动导航）
// Travel-mode follow-up after the destination pick ("怎么去？"): pending only
// when the trigger utterance did not name a mode. 15s timeout applies the
// distance-aware default (walk ≤3km, else drive -- walk planning rejects long
// distances). ChooseMode parses 步行/骑行/驾车 (+ aliases, 随便 → default).
BOOL TIOVoiceNavPendingMode(void); // YES = waiting for a spoken travel mode
BOOL TIOVoiceNavChooseMode(NSString *text); // YES = consumed as the mode answer
NSString *TIOVoiceNavMatchDestination(NSString *text); // pure matcher: destination after normalization, nil = no nav trigger
// Assistant-session lifecycle helpers (implemented in Addon.m).
void TIOVoiceCloseAssistantSession(void); // official stop entry; frees the lens
BOOL TIOAssistantEmit(NSString *piece,BOOL done); // append to the hijacked reply; NO = no owned turn (fall back)
// Post-utterance channel: park the next dialog line; the choice utterance's own
// official NLP response is rewritten with it and forwarded (old-turn emits render
// nowhere once the user has spoken again). 2s without a response → old channel.
void TIOAssistantInjectNext(NSString *text,BOOL done);
