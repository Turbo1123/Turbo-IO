#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "RecordingExports.h"

// Adds one row to the existing research menu. Does not hook voice or files.
static NSInteger (*PriorRows)(id,SEL,id,NSInteger);
static id (*PriorCell)(id,SEL,id,id);
static id (*PriorHeader)(id,SEL,id,NSInteger);
static id (*PriorFooter)(id,SEL,id,NSInteger);
static void (*PriorSelect)(id,SEL,id,id);
static void (*PriorLoad)(id,SEL);
static void MenuMarker(id self,SEL cmd){}
static NSInteger Rows(id self,SEL cmd,id table,NSInteger section){
    NSInteger count=PriorRows(self,cmd,table,section);
    return section==1&&count==2?3:count;
}
static BOOL IsExportRow(id self,UITableView *table,NSIndexPath *ip){
    return ip.section==1&&ip.row==2&&PriorRows(self,@selector(tableView:numberOfRowsInSection:),table,1)==2;
}
static id Cell(id self,SEL cmd,UITableView *table,NSIndexPath *ip){
    if(!IsExportRow(self,table,ip))return PriorCell(self,cmd,table,ip);
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text=@"录音与文本分享";
    cell.detailTextLabel.text=@"音频 AirDrop / 存储到文件 · TXT/MD 导入分享";
    cell.detailTextLabel.numberOfLines=0;
    cell.imageView.image=[UIImage systemImageNamed:@"square.and.arrow.up"];
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
static id Header(id self,SEL cmd,id table,NSInteger section){return section==1?@"录音与文本导出":PriorHeader(self,cmd,table,section);}
static id Footer(id self,SEL cmd,id table,NSInteger section){
    if(section==1)return @"旁路文字只含开启后收到的全天智记。音频分享使用官方已准备的本机文件，不删原件。当前录音全文的自动 Markdown 导出尚未接通。";
    return PriorFooter(self,cmd,table,section);
}
static void Select(id self,SEL cmd,UITableView *table,NSIndexPath *ip){
    if(!IsExportRow(self,table,ip)){PriorSelect(self,cmd,table,ip);return;}
    [table deselectRowAtIndexPath:ip animated:YES];
    Class cls=NSClassFromString(@"TIORecordingExportsPanel");
    if(cls){UITableViewController *panel=[(UITableViewController *)[cls alloc]initWithStyle:UITableViewStyleInsetGrouped];[[(UIViewController *)self navigationController] pushViewController:panel animated:YES];}
}
static void Load(id self,SEL cmd){
    PriorLoad(self,cmd);
    // Also removes v1's button when this menu-only update is hot-loaded.
    ((UIViewController *)self).navigationItem.leftBarButtonItem=nil;
}
static BOOL Signature(Method m,char result,NSArray<NSString *> *args){
    if(!m||method_getNumberOfArguments(m)!=args.count+2)return NO;
    char *r=method_copyReturnType(m);BOOL ok=r&&r[0]==result;free(r);
    for(unsigned i=0;i<args.count;i++){char *t=method_copyArgumentType(m,i+2);ok=ok&&t&&[args[i] containsString:[NSString stringWithFormat:@"%c",t[0]]];free(t);}return ok;
}
void TIOInstallRecordingExportMenu(void){
    Class cls=NSClassFromString(@"TIOPanel");
    SEL marker=NSSelectorFromString(@"tio_recordingExportMenuV2");
    if(!cls||!NSClassFromString(@"TIORecordingExportsPanel")||class_getInstanceMethod(cls,marker))return;
    Method rows=class_getInstanceMethod(cls,@selector(tableView:numberOfRowsInSection:));
    Method cell=class_getInstanceMethod(cls,@selector(tableView:cellForRowAtIndexPath:));
    Method header=class_getInstanceMethod(cls,@selector(tableView:titleForHeaderInSection:));
    Method footer=class_getInstanceMethod(cls,@selector(tableView:titleForFooterInSection:));
    Method select=class_getInstanceMethod(cls,@selector(tableView:didSelectRowAtIndexPath:));
    Method load=class_getInstanceMethod(cls,@selector(viewDidLoad));
    if(!Signature(rows,'q',@[@"@",@"q"])||!Signature(cell,'@',@[@"@",@"@"])||!Signature(header,'@',@[@"@",@"q"])||!Signature(footer,'@',@[@"@",@"q"])||!Signature(select,'v',@[@"@",@"@"])||!Signature(load,'v',@[]))return;
    if(!class_addMethod(cls,marker,(IMP)MenuMarker,"v@:"))return;
    PriorRows=(void *)method_setImplementation(rows,(IMP)Rows);
    PriorCell=(void *)method_setImplementation(cell,(IMP)Cell);
    PriorHeader=(void *)method_setImplementation(header,(IMP)Header);
    PriorFooter=(void *)method_setImplementation(footer,(IMP)Footer);
    PriorSelect=(void *)method_setImplementation(select,(IMP)Select);
    PriorLoad=(void *)method_setImplementation(load,(IMP)Load);
}
#ifdef TIO_EXPORT_MENU_HOTLOAD
__attribute__((constructor))static void InstallMenu(void){
    dispatch_async(dispatch_get_main_queue(),^{
        if([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.rayneo.venus.pub"]&&[[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"67"])TIOInstallRecordingExportMenu();
    });
}
#endif
