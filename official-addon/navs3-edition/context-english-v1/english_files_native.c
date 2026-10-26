#include "english_files.h"
/* Reuse only the pinned stdio/errno/statfs ABI already linked for TurboApps.
 * Binding is side-effect-free. Paths remain independent from all app slots. */
bool ce_files_native_bind(CEFiles *f,CEStoreIO *out){
    TAPFiles native;TAPStoreIO ignored;
    return tap_files_native_bind(&native,&ignored)&&ce_files_bind(f,&native.ops,out);
}
