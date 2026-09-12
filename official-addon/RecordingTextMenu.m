#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "RecordingText.h"
static NSInteger (*TextPriorRows)(id,SEL,id,NSInteger);
static id (*TextPriorCell)(id,SEL,id,id);
static void (*TextPriorSelect)(id,SEL,id,id);
static NSInteger BaseCount(id self,id table){return TextPriorRows(self,@selector(tableView:numberOfRowsInSection:),table,1);}
static NSInteger TextRows(id self,SEL cmd,id table,NSInteger s){NSInteger n=TextPriorRows(self,cmd,table,s);return s==1&&(n==2||n==3)?n+2:n;}
static NSInteger NewRow(id self,id table,NSIndexPath *ip){NSInteger n=BaseCount(self,table);return ip.section==1&&(n==2||n==3)&&ip.row>=n&&ip.row<n+2?ip.row-n:-1;}
static id TextCell(id self,SEL cmd,id table,NSIndexPath *ip){NSInteger row=NewRow(self,table,ip);if(row<0)return TextPriorCell(self,cmd,table,ip);UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.text=row==0?@"全天智记导出":@"转写文字 → 自有模型整理";c.detailTextLabel.text=row==0?@"已保存文字 · 历史全文/原音频仍待接通":@"保留官方 ASR · 手动确认 · 独立 Markdown";c.detailTextLabel.numberOfLines=0;c.imageView.image=[UIImage systemImageNamed:row==0?@"doc.text":@"text.badge.star"];c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;}
static void TextSelect(id self,SEL cmd,UITableView *table,NSIndexPath *ip){NSInteger row=NewRow(self,table,ip);if(row<0){TextPriorSelect(self,cmd,table,ip);return;}[table deselectRowAtIndexPath:ip animated:YES];Class cls=NSClassFromString(row==0?@"TIOLifelogExportsPanel":@"TIORecordingTextPanel");UIViewController *p=row==0?[(UITableViewController *)[cls alloc]initWithStyle:UITableViewStyleInsetGrouped]:[cls new];if(p)[[(UIViewController *)self navigationController] pushViewController:p animated:YES];}
static void TextMarker(id self,SEL cmd){}
void TIOInstallRecordingTextMenu(void){
    Class cls=NSClassFromString(@"TIOPanel");SEL marker=NSSelectorFromString(@"tio_recordingTextMenuV1");if(!cls||class_getInstanceMethod(cls,marker)||!NSClassFromString(@"TIORecordingTextPanel"))return;
    Method rows=class_getInstanceMethod(cls,@selector(tableView:numberOfRowsInSection:)),cell=class_getInstanceMethod(cls,@selector(tableView:cellForRowAtIndexPath:)),select=class_getInstanceMethod(cls,@selector(tableView:didSelectRowAtIndexPath:));
    if(!rows||!cell||!select||method_getNumberOfArguments(rows)!=4||method_getNumberOfArguments(cell)!=4||method_getNumberOfArguments(select)!=4)return;
    if(!class_addMethod(cls,marker,(IMP)TextMarker,"v@:"))return;
    TextPriorRows=(void *)method_setImplementation(rows,(IMP)TextRows);TextPriorCell=(void *)method_setImplementation(cell,(IMP)TextCell);TextPriorSelect=(void *)method_setImplementation(select,(IMP)TextSelect);
}
#ifdef TIO_TEXT_MENU_HOTLOAD
__attribute__((constructor))static void InstallTextMenu(void){dispatch_async(dispatch_get_main_queue(),^{if([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.rayneo.venus.pub"]&&[[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"67"])TIOInstallRecordingTextMenu();});}
#endif
